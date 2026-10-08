"""Python entry point for the in-process YouTube extraction proof of concept."""

import json
from importlib.metadata import version
import re
from functools import wraps

import yt_dlp

_APPLE_WEBKIT_DIAGNOSTICS_READY = False
_APPLE_WEBKIT_CHALLENGE_CALLS = 0
_APPLE_WEBKIT_CHALLENGE_SUCCESSES = 0


class DiagnosticLogger:
    @staticmethod
    def _safe_challenge_message(message: str) -> str:
        redacted = re.sub(r"(?i)https?://[^\s\"'<>]+", "<URL redacted>", message)
        redacted = re.sub(r"(?i)([?&](?:sig|signature|n|expire|ei|ip|key|lsig|sparams|spc|pot)=)[^&\s]+", r"\1<redacted>", redacted)
        redacted = re.sub(r"(?i)(input|request|requests|response|token)\s*=\s*[^,\n]+", r"\1=<redacted>", redacted)
        return redacted[:280]

    def debug(self, message: str) -> None:
        lowered = message.lower()
        signals = (
            "js challenge providers:",
            "attempting to solve",
            "solved all",
            "not all js challenges",
            "solving challenge, script length:",
            "constructing webview",
            "webview constructed",
        )
        if any(signal in lowered for signal in signals):
            print(f"YOUTUBE_POC: yt-dlp diagnostic: {self._safe_challenge_message(message)}", flush=True)

    def warning(self, message: str) -> None:
        if "challenge" in message.lower():
            print(f"YOUTUBE_POC: yt-dlp warning: {self._safe_challenge_message(message)}", flush=True)

    def error(self, message: str) -> None:
        if "challenge" in message.lower():
            print(f"YOUTUBE_POC: yt-dlp error: {self._safe_challenge_message(message)}", flush=True)


def enable_safe_apple_jsc_diagnostics() -> None:
    global _APPLE_WEBKIT_DIAGNOSTICS_READY
    if _APPLE_WEBKIT_DIAGNOSTICS_READY:
        return

    from yt_dlp_plugins.extractor.ytjsc import AppleWebKitJCP

    current = AppleWebKitJCP._run_js_runtime
    if getattr(current, "_vipod_diagnostic_wrapper", False):
        return

    @wraps(current)
    def diagnostic_run(self, script: str) -> str:
        global _APPLE_WEBKIT_CHALLENGE_CALLS, _APPLE_WEBKIT_CHALLENGE_SUCCESSES
        _APPLE_WEBKIT_CHALLENGE_CALLS += 1
        print(f"YOUTUBE_POC: Apple WebKit JSC executing a challenge script ({len(script)} characters; source suppressed).", flush=True)
        try:
            result = current(self, script)
        except Exception as error:
            print(f"YOUTUBE_POC: Apple WebKit JSC challenge failed ({type(error).__name__}); details suppressed.", flush=True)
            raise
        print("YOUTUBE_POC: Apple WebKit JSC returned a challenge result (value suppressed).", flush=True)
        _APPLE_WEBKIT_CHALLENGE_SUCCESSES += 1
        return result

    diagnostic_run._vipod_diagnostic_wrapper = True
    AppleWebKitJCP._run_js_runtime = diagnostic_run
    _APPLE_WEBKIT_DIAGNOSTICS_READY = True


def extract(url: str) -> str:
    calls_before = _APPLE_WEBKIT_CHALLENGE_CALLS
    successes_before = _APPLE_WEBKIT_CHALLENGE_SUCCESSES
    print(
        "YOUTUBE_POC: in-process extraction started; "
        f"yt-dlp={version('yt-dlp')}, yt-dlp-ejs={version('yt-dlp-ejs')}, "
        f"apple-webkit-jsi={version('yt-dlp-apple-webkit-jsi')}",
        flush=True,
    )
    enable_safe_apple_jsc_diagnostics()
    options = {
        "quiet": True,
        "verbose": True,
        "no_warnings": True,
        "logger": DiagnosticLogger(),
        "noplaylist": True,
        "skip_download": True,
        "extract_flat": False,
        "cachedir": False,
        "extractor_args": {"youtube": {"jsc_trace": ["true"], "player_client": ["web_embedded", "web", "visionos"]}},
        "socket_timeout": 25,
        "retries": 0,
        "extractor_retries": 0,
        "fragment_retries": 0,
        "js_runtimes": {},
    }
    with yt_dlp.YoutubeDL(options) as downloader:
        info = downloader.extract_info(url, download=False)
    if not isinstance(info, dict) or info.get("_type") == "playlist" or info.get("is_live"):
        raise ValueError("Only public, single, non-live YouTube videos are supported.")

    formats = []
    for item in info.get("formats", []):
        formats.append({
            "formatID": item.get("format_id"),
            "extension": item.get("ext"),
            "protocol": item.get("protocol"),
            "audioCodec": item.get("acodec"),
            "videoCodec": item.get("vcodec"),
            "url": item.get("url"),
            "httpHeaders": item.get("http_headers") or {},
            "filesize": item.get("filesize") or item.get("filesize_approx"),
            "bitrate": item.get("tbr"),
            "source_preference": item.get("source_preference"),
            "preference": item.get("preference"),
        })
    return json.dumps({
        "id": info.get("id"),
        "title": info.get("title"),
        "isLive": bool(info.get("is_live")),
        "formats": formats,
        "webkitJSCChallengeCalls": _APPLE_WEBKIT_CHALLENGE_CALLS - calls_before,
        "webkitJSCChallengeSuccesses": _APPLE_WEBKIT_CHALLENGE_SUCCESSES - successes_before,
    })
