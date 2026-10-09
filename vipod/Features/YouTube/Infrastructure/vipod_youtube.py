"""Python entry point for the in-process YouTube extraction proof of concept."""

import calendar
import json
import math
from importlib.metadata import version
import re
from functools import wraps
from urllib.parse import urlsplit

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


_THUMBNAIL_HOSTS = frozenset({"i.ytimg.com", "img.youtube.com"})
_MUSIC_TEXT_FIELDS = (
    ("title", "track"),
    ("artist", "artist"),
    ("album", "album"),
    ("albumArtist", "album_artist"),
    ("genre", "genre"),
)
_METADATA_DATE_PATTERN = re.compile(r"[1-9]\d{3}(?:-\d{2}(?:-\d{2})?)?")
_COMPACT_DATE_PATTERN = re.compile(r"(\d{4})(\d{2})(\d{2})")


def _music_text(value):
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        text = str(value)
    elif isinstance(value, float):
        if not math.isfinite(value):
            return None
        text = str(int(value)) if value.is_integer() else str(value)
    elif isinstance(value, str):
        text = value
    else:
        return None
    return text.strip() or None


def _plain_text(value):
    if not isinstance(value, str):
        return None
    return value.strip() or None


def _metadata_date(value):
    text = _music_text(value)
    if text is None:
        return None
    compact = _COMPACT_DATE_PATTERN.fullmatch(text)
    normalized = "-".join(compact.groups()) if compact else text
    if _METADATA_DATE_PATTERN.fullmatch(normalized) is None:
        return None
    pieces = normalized.split("-")
    year = int(pieces[0])
    if len(pieces) == 1:
        return normalized
    month = int(pieces[1])
    if not 1 <= month <= 12:
        return None
    if len(pieces) == 2:
        return normalized
    day = int(pieces[2])
    if not 1 <= day <= calendar.monthrange(year, month)[1]:
        return None
    return normalized


def _metadata_number(value, max_digits):
    text = _music_text(value)
    if text is None:
        return None
    part = r"[1-9]\d{0,%d}" % (max_digits - 1)
    if re.fullmatch(r"%s(?:/%s)?" % (part, part), text) is None:
        return None
    number, _, total = text.partition("/")
    if total and int(number) > int(total):
        return None
    return text


def _finite_duration(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    if not math.isfinite(value) or value < 0:
        return None
    return value


def _approved_thumbnail_url(value):
    if not isinstance(value, str):
        return None
    url = value.strip()
    if not url or "\\" in url or any(character.isspace() for character in url):
        return None
    try:
        parts = urlsplit(url)
        port = parts.port
    except ValueError:
        return None
    if parts.scheme != "https" or parts.username is not None or parts.password is not None or port is not None:
        return None
    host = (parts.hostname or "").lower().rstrip(".")
    if host not in _THUMBNAIL_HOSTS:
        return None
    return url


def _select_thumbnail(info):
    approved = []
    thumbnails = info.get("thumbnails")
    if isinstance(thumbnails, list):
        for entry in thumbnails:
            if isinstance(entry, dict):
                url = _approved_thumbnail_url(entry.get("url"))
                if url is not None:
                    approved.append(url)
    raw = _approved_thumbnail_url(info.get("thumbnail"))
    if raw is not None:
        return raw
    return approved[-1] if approved else None


def _nullish(info, primary, fallback):
    value = info.get(primary)
    return info.get(fallback) if value is None else value


def _music_payload(info):
    music = {}
    for target_key, source_key in _MUSIC_TEXT_FIELDS:
        value = _music_text(info.get(source_key))
        if value is not None:
            music[target_key] = value
    date = _metadata_date(_nullish(info, "release_date", "release_year"))
    if date is not None:
        music["date"] = date
    track_number = _metadata_number(_nullish(info, "track_number", "track_number_raw"), 4)
    if track_number is not None:
        music["trackNumber"] = track_number
    disc_number = _metadata_number(_nullish(info, "disc_number", "disc_number_raw"), 3)
    if disc_number is not None:
        music["discNumber"] = disc_number
    return music


def build_payload(info, challenge_calls, challenge_successes):
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
            "filesize": item.get("filesize"),
            "filesizeApprox": item.get("filesize_approx"),
            "bitrate": item.get("tbr"),
            "source_preference": item.get("source_preference"),
            "preference": item.get("preference"),
        })
    payload = {
        "id": info.get("id"),
        "title": info.get("title"),
        "isLive": bool(info.get("is_live")),
        "formats": formats,
        "webkitJSCChallengeCalls": challenge_calls,
        "webkitJSCChallengeSuccesses": challenge_successes,
    }
    duration = _finite_duration(info.get("duration"))
    if duration is not None:
        payload["duration"] = duration
    thumbnail = _select_thumbnail(info)
    if thumbnail is not None:
        payload["thumbnail"] = thumbnail
    channel = _plain_text(info.get("channel")) or _plain_text(info.get("uploader"))
    if channel is not None:
        payload["channel"] = channel
    upload_date = _metadata_date(info.get("upload_date"))
    if upload_date is not None:
        payload["uploadDate"] = upload_date
    music = _music_payload(info)
    if music:
        payload["music"] = music
    return payload


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

    payload = build_payload(
        info,
        _APPLE_WEBKIT_CHALLENGE_CALLS - calls_before,
        _APPLE_WEBKIT_CHALLENGE_SUCCESSES - successes_before,
    )
    return json.dumps(payload)
