#import "EmbeddedPythonRuntime.h"
#import <TargetConditionals.h>

#if TARGET_OS_IOS
#import <Python/Python.h>
#import <dispatch/dispatch.h>
#import <regex.h>

static dispatch_once_t VIPODPythonInitializationOnce;
static NSError *VIPODPythonInitializationError;

static NSError *VIPODPythonError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"VIPOD.EmbeddedPython" code:code userInfo:@{
        NSLocalizedDescriptionKey: message
    }];
}

static NSString *VIPODPythonPath(NSString *resourcePath, NSString *relativePath) {
    return [resourcePath stringByAppendingPathComponent:relativePath];
}

static NSError *VIPODPythonStatusError(PyStatus status, NSString *stage) {
    NSString *detail = status.err_msg ? [NSString stringWithUTF8String:status.err_msg] : @"No CPython detail was provided.";
    NSString *category = PyStatus_IsExit(status)
        ? [NSString stringWithFormat:@"CPython requested exit %d", status.exitcode]
        : @"CPython initialization error";
    return VIPODPythonError((NSInteger)status.exitcode, [NSString stringWithFormat:@"%@ (%@): %@", category, stage, detail]);
}

static BOOL VIPODPythonAppendPath(PyConfig *configuration, NSString *path, NSError **error) {
    wchar_t *widePath = Py_DecodeLocale(path.fileSystemRepresentation, NULL);
    if (!widePath) {
        if (error) *error = VIPODPythonError(1, [NSString stringWithFormat:@"CPython could not encode a bundled module path: %@", path.lastPathComponent]);
        return NO;
    }
    PyStatus status = PyWideStringList_Append(&configuration->module_search_paths, widePath);
    PyMem_RawFree(widePath);
    if (PyStatus_Exception(status)) {
        if (error) *error = VIPODPythonStatusError(status, @"module search path");
        return NO;
    }
    return YES;
}

static void VIPODPythonConfigure(NSError **error) {
    @autoreleasepool {
        NSBundle *bundle = NSBundle.mainBundle;
        NSString *resourcePath = bundle.resourcePath;
        NSString *pythonHome = VIPODPythonPath(resourcePath, @"python");
        NSString *pythonVersionPath = VIPODPythonPath(pythonHome, @"lib/python3.14");
        NSString *dynamicModulesPath = VIPODPythonPath(pythonVersionPath, @"lib-dynload");
        NSString *applicationModulesPath = VIPODPythonPath(resourcePath, @"youtube-python");
        NSString *certificatesPath = VIPODPythonPath(applicationModulesPath, @"certifi/cacert.pem");

        BOOL isDirectory = NO;
        if (![NSFileManager.defaultManager fileExistsAtPath:pythonVersionPath isDirectory:&isDirectory] || !isDirectory) {
            *error = VIPODPythonError(2, @"The bundled Python standard library is missing. Run scripts/bootstrap-youtube-runtime.sh and build the iOS target.");
            return;
        }
        if (![NSFileManager.defaultManager fileExistsAtPath:applicationModulesPath isDirectory:&isDirectory] || !isDirectory) {
            *error = VIPODPythonError(3, @"The bundled yt-dlp Python packages are missing. Run scripts/bootstrap-youtube-runtime.sh and build the iOS target.");
            return;
        }
        if (![NSFileManager.defaultManager fileExistsAtPath:certificatesPath]) {
            *error = VIPODPythonError(4, @"The bundled HTTPS certificate bundle is missing.");
            return;
        }

        setenv("PYTHONHOME", pythonHome.fileSystemRepresentation, 1);
        NSString *pythonPath = [@[pythonVersionPath, dynamicModulesPath, applicationModulesPath] componentsJoinedByString:@":"];
        setenv("PYTHONPATH", pythonPath.fileSystemRepresentation, 1);
        setenv("SSL_CERT_FILE", certificatesPath.fileSystemRepresentation, 1);

        PyPreConfig preconfiguration;
        PyPreConfig_InitIsolatedConfig(&preconfiguration);
        preconfiguration.utf8_mode = 1;
        PyStatus status = Py_PreInitialize(&preconfiguration);
        if (PyStatus_Exception(status)) {
            *error = VIPODPythonStatusError(status, @"pre-initialization");
            return;
        }

        PyConfig configuration;
        PyConfig_InitIsolatedConfig(&configuration);
        configuration.use_environment = 0;
        configuration.parse_argv = 0;
        configuration.write_bytecode = 0;
        configuration.install_signal_handlers = 0;
        configuration.buffered_stdio = 0;
        configuration.safe_path = 1;

        status = PyConfig_SetBytesString(&configuration, &configuration.home, pythonHome.fileSystemRepresentation);
        if (PyStatus_Exception(status)) {
            *error = VIPODPythonStatusError(status, @"setting PYTHONHOME");
            PyConfig_Clear(&configuration);
            return;
        }

        for (NSString *path in @[pythonVersionPath, dynamicModulesPath, applicationModulesPath]) {
            NSError *pathError;
            if (!VIPODPythonAppendPath(&configuration, path, &pathError)) {
                *error = pathError;
                PyConfig_Clear(&configuration);
                return;
            }
        }
        configuration.module_search_paths_set = 1;

        status = Py_InitializeFromConfig(&configuration);
        NSError *configurationError = PyStatus_Exception(status)
            ? VIPODPythonStatusError(status, @"interpreter initialization")
            : nil;
        PyConfig_Clear(&configuration);
        if (configurationError) {
            *error = configurationError;
            return;
        }

        // CPython initialization leaves this thread holding the GIL. Detach its initial
        // thread state so arbitrary later worker threads can pair Ensure/Release safely.
        (void)PyEval_SaveThread();
        NSLog(@"YOUTUBE_POC: embedded CPython %@ initialized; isolated bundle paths and certifi HTTPS roots configured.",
              [NSString stringWithUTF8String:Py_GetVersion()]);
    }
}

BOOL VIPODPythonInitialize(NSError **error) {
    dispatch_once(&VIPODPythonInitializationOnce, ^{
        NSError *initializationError = nil;
        VIPODPythonConfigure(&initializationError);
        VIPODPythonInitializationError = initializationError;
    });
    if (VIPODPythonInitializationError) {
        if (error) *error = VIPODPythonInitializationError;
        return NO;
    }
    return YES;
}

static NSString *VIPODRedactedPythonText(NSString *text) {
    NSError *regexError;
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:@"(?i)https?://[^\\s\\\"'<>]+" options:0 error:&regexError];
    if (!expression || regexError) return @"Python returned an error; URL details were suppressed.";
    NSString *redacted = [expression stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@"<URL redacted>"];
    if (redacted.length > 320) redacted = [[redacted substringToIndex:320] stringByAppendingString:@"…"];
    return redacted;
}

static NSError *VIPODPythonCurrentException(void) {
    PyObject *exceptionType = NULL;
    PyObject *exceptionValue = NULL;
    PyObject *traceback = NULL;
    PyErr_Fetch(&exceptionType, &exceptionValue, &traceback);
    PyErr_NormalizeException(&exceptionType, &exceptionValue, &traceback);

    NSString *typeName = @"PythonError";
    NSString *message = @"No exception details were available.";
    if (exceptionType) {
        PyObject *name = PyObject_GetAttrString(exceptionType, "__name__");
        if (name) {
            const char *nameBytes = PyUnicode_AsUTF8(name);
            if (nameBytes) typeName = [NSString stringWithUTF8String:nameBytes];
            Py_DECREF(name);
        }
    }
    if (exceptionValue) {
        PyObject *description = PyObject_Str(exceptionValue);
        if (description) {
            const char *descriptionBytes = PyUnicode_AsUTF8(description);
            if (descriptionBytes) message = VIPODRedactedPythonText([NSString stringWithUTF8String:descriptionBytes]);
            Py_DECREF(description);
        }
    }

    Py_XDECREF(exceptionType);
    Py_XDECREF(exceptionValue);
    Py_XDECREF(traceback);
    PyErr_Clear();
    return VIPODPythonError(10, [NSString stringWithFormat:@"Python %@: %@", typeName, message]);
}

NSString * _Nullable VIPODPythonExtract(NSString *videoID, NSError **error) {
    NSError *initializationError;
    if (!VIPODPythonInitialize(&initializationError)) {
        if (error) *error = initializationError;
        return nil;
    }

    @autoreleasepool {
        PyGILState_STATE gil = PyGILState_Ensure();
        PyObject *module = NULL;
        PyObject *function = NULL;
        PyObject *argument = NULL;
        PyObject *arguments = NULL;
        PyObject *response = NULL;
        NSString *json = nil;
        NSError *pythonError = nil;

        module = PyImport_ImportModule("vipod_youtube");
        if (!module) goto python_error;
        function = PyObject_GetAttrString(module, "extract");
        if (!function) goto python_error;
        argument = PyUnicode_FromString(videoID.UTF8String);
        if (!argument) goto python_error;
        arguments = PyTuple_Pack(1, argument);
        if (!arguments) goto python_error;
        response = PyObject_CallObject(function, arguments);
        if (!response) goto python_error;
        if (!PyUnicode_Check(response)) {
            pythonError = VIPODPythonError(11, @"Python extractor returned a non-text result.");
            goto cleanup;
        }
        const char *bytes = PyUnicode_AsUTF8(response);
        if (!bytes) goto python_error;
        json = [NSString stringWithUTF8String:bytes];
        if (!json) {
            pythonError = VIPODPythonError(12, @"Python extractor returned invalid UTF-8.");
            goto cleanup;
        }
        VIPODPythonLog([NSString stringWithFormat:@"In-process yt-dlp returned %lu JSON characters.", (unsigned long)json.length]);
        goto cleanup;

python_error:
        pythonError = VIPODPythonCurrentException();

cleanup:
        Py_XDECREF(response);
        Py_XDECREF(arguments);
        Py_XDECREF(argument);
        Py_XDECREF(function);
        Py_XDECREF(module);
        PyGILState_Release(gil);
        if (pythonError) {
            VIPODPythonLog(pythonError.localizedDescription);
            if (error) *error = pythonError;
            return nil;
        }
        return json;
    }
}

void VIPODPythonLog(NSString *message) {
    NSLog(@"YOUTUBE_POC: %@", message);
}
#else
BOOL VIPODPythonInitialize(NSError **error) { return NO; }
NSString * _Nullable VIPODPythonExtract(NSString *videoID, NSError **error) { return nil; }
void VIPODPythonLog(NSString *message) { NSLog(@"YOUTUBE_POC: %@", message); }
#endif
