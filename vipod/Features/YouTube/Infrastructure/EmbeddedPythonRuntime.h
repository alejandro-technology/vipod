#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT BOOL VIPODPythonInitialize(NSError * _Nullable * _Nullable error);
FOUNDATION_EXPORT NSString * _Nullable VIPODPythonExtract(NSString *videoID, NSError * _Nullable * _Nullable error);
FOUNDATION_EXPORT void VIPODPythonLog(NSString *message);

NS_ASSUME_NONNULL_END
