"""Deterministic payload-mapping tests for vipod_youtube.

These tests exercise the pure ``build_payload`` helper with fake raw info
dicts. They never import a real yt-dlp installation, never touch the network,
and never invoke the Apple WebKit JSC provider.
"""

import importlib.util
import json
import math
from pathlib import Path
import sys
import types
import unittest

_MODULE_PATH = (
    Path(__file__).resolve().parents[1]
    / "vipod" / "Features" / "YouTube" / "Infrastructure" / "vipod_youtube.py"
)


def _load_module():
    sys.modules.setdefault("yt_dlp", types.ModuleType("yt_dlp"))
    spec = importlib.util.spec_from_file_location("vipod_youtube_under_test", _MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


vipod_youtube = _load_module()


def _payload(info):
    return vipod_youtube.build_payload(info, 3, 2)


class BuildPayloadOptionalFieldTests(unittest.TestCase):
    def test_all_optional_fields_present(self):
        payload = _payload({
            "id": "abc123def45",
            "title": "Video title",
            "is_live": False,
            "duration": 213.5,
            "thumbnail": "https://i.ytimg.com/vi/abc/hq720.jpg",
            "channel": " Channel Name ",
            "upload_date": "20240105",
            "track": "Song Title",
            "artist": "The Artist",
            "album": "The Album",
            "album_artist": "Album Artist",
            "genre": "Genre",
            "release_date": "20240229",
            "track_number": 7,
            "disc_number_raw": "2/2",
            "formats": [],
        })
        self.assertEqual(payload["id"], "abc123def45")
        self.assertEqual(payload["title"], "Video title")
        self.assertFalse(payload["isLive"])
        self.assertEqual(payload["webkitJSCChallengeCalls"], 3)
        self.assertEqual(payload["webkitJSCChallengeSuccesses"], 2)
        self.assertEqual(payload["duration"], 213.5)
        self.assertEqual(payload["thumbnail"], "https://i.ytimg.com/vi/abc/hq720.jpg")
        self.assertEqual(payload["channel"], "Channel Name")
        self.assertEqual(payload["uploadDate"], "2024-01-05")
        self.assertEqual(payload["music"], {
            "title": "Song Title",
            "artist": "The Artist",
            "album": "The Album",
            "albumArtist": "Album Artist",
            "genre": "Genre",
            "date": "2024-02-29",
            "trackNumber": "7",
            "discNumber": "2/2",
        })
        json.dumps(payload)

    def test_missing_optional_values_are_omitted(self):
        payload = _payload({"id": "x", "title": "T", "formats": []})
        for key in ("duration", "thumbnail", "channel", "uploadDate", "music"):
            self.assertNotIn(key, payload)
        self.assertEqual(payload["formats"], [])

    def test_blank_music_values_omitted(self):
        payload = _payload({
            "id": "x", "title": "T", "track": "   ", "artist": "", "album": None, "formats": [],
        })
        self.assertNotIn("music", payload)

    def test_music_title_comes_from_track_not_video_title(self):
        payload = _payload({"id": "x", "title": "Video title", "track": "Song", "formats": []})
        self.assertEqual(payload["title"], "Video title")
        self.assertEqual(payload["music"]["title"], "Song")

    def test_channel_falls_back_to_uploader(self):
        payload = _payload({"id": "x", "title": "T", "uploader": " Uploader ", "formats": []})
        self.assertEqual(payload["channel"], "Uploader")
        payload = _payload({
            "id": "x", "title": "T", "channel": "Main", "uploader": "Other", "formats": [],
        })
        self.assertEqual(payload["channel"], "Main")

    def test_upload_date_never_maps_to_music_date(self):
        payload = _payload({"id": "x", "title": "T", "upload_date": "20240105", "formats": []})
        self.assertEqual(payload["uploadDate"], "2024-01-05")
        self.assertNotIn("music", payload)


class BuildPayloadDateTests(unittest.TestCase):
    def test_compact_release_date_normalized(self):
        payload = _payload({"id": "x", "title": "T", "release_date": "20240229", "formats": []})
        self.assertEqual(payload["music"]["date"], "2024-02-29")

    def test_hyphenated_and_year_only_dates_pass_through(self):
        for raw, expected in (("2024-02-29", "2024-02-29"), ("2024-02", "2024-02"), (2024, "2024")):
            payload = _payload({"id": "x", "title": "T", "release_date": raw, "formats": []})
            self.assertEqual(payload["music"]["date"], expected, raw)

    def test_release_year_fallback_when_release_date_missing(self):
        payload = _payload({"id": "x", "title": "T", "release_year": 2020, "formats": []})
        self.assertEqual(payload["music"]["date"], "2020")
        payload = _payload({"id": "x", "title": "T", "release_date": None, "release_year": 2020, "formats": []})
        self.assertEqual(payload["music"]["date"], "2020")

    def test_invalid_release_date_is_dropped_without_year_fallback(self):
        payload = _payload({
            "id": "x", "title": "T", "release_date": "20240230", "release_year": 2020, "formats": [],
        })
        self.assertNotIn("date", payload.get("music", {}))

    def test_invalid_calendar_dates_rejected(self):
        for raw in ("20230229", "20241301", "20240010", "20240100", "2024-13", "0000", "0999", "24", "202401"):
            payload = _payload({"id": "x", "title": "T", "release_date": raw, "formats": []})
            self.assertNotIn("date", payload.get("music", {}), raw)


class BuildPayloadNumberTests(unittest.TestCase):
    def test_track_number_forms(self):
        cases = (
            (7, "7"), (" 5 ", "5"), ("2/10", "2/10"), ("10/10", "10/10"), (9999, "9999"),
        )
        for raw, expected in cases:
            payload = _payload({"id": "x", "title": "T", "track_number": raw, "formats": []})
            self.assertEqual(payload["music"]["trackNumber"], expected, raw)

    def test_track_number_limits_and_leading_zeros(self):
        for raw in ("0", "007", "01", "3/2", "1/0", "10000", "0/5", ""):
            payload = _payload({"id": "x", "title": "T", "track_number": raw, "formats": []})
            self.assertNotIn("trackNumber", payload.get("music", {}), raw)

    def test_disc_number_limits_and_fallback(self):
        payload = _payload({"id": "x", "title": "T", "disc_number_raw": "2/2", "formats": []})
        self.assertEqual(payload["music"]["discNumber"], "2/2")
        payload = _payload({"id": "x", "title": "T", "disc_number": 999, "formats": []})
        self.assertEqual(payload["music"]["discNumber"], "999")
        for raw in ("1000", "0", "01", "2/1"):
            payload = _payload({"id": "x", "title": "T", "disc_number": raw, "formats": []})
            self.assertNotIn("discNumber", payload.get("music", {}), raw)


class BuildPayloadThumbnailTests(unittest.TestCase):
    def test_approved_raw_thumbnail_preferred(self):
        payload = _payload({
            "id": "x", "title": "T",
            "thumbnail": "https://i.ytimg.com/vi/abc/hq720.jpg",
            "thumbnails": [{"url": "https://i.ytimg.com/vi/abc/default.jpg"}],
            "formats": [],
        })
        self.assertEqual(payload["thumbnail"], "https://i.ytimg.com/vi/abc/hq720.jpg")

    def test_last_approved_thumbnail_is_fallback(self):
        payload = _payload({
            "id": "x", "title": "T",
            "thumbnail": "https://yt3.ggpht.com/channel-avatar",
            "thumbnails": [
                {"url": "https://evil.example.com/a.jpg"},
                {"url": "https://i.ytimg.com/vi/abc/default.jpg"},
                {"url": "https://img.youtube.com/vi/abc/hq720.jpg"},
            ],
            "formats": [],
        })
        self.assertEqual(payload["thumbnail"], "https://img.youtube.com/vi/abc/hq720.jpg")

    def test_unsafe_urls_rejected(self):
        unsafe = (
            "http://i.ytimg.com/vi/abc/hq720.jpg",
            "https://i.ytimg.com.evil.example/vi/abc/hq720.jpg",
            "https://user@i.ytimg.com/vi/abc/hq720.jpg",
            "https://i.ytimg.com:8443/vi/abc/hq720.jpg",
            "https://yt3.ggpht.com/avatar",
            "https://i.ytimg.com\\@evil.example/x.jpg",
            "javascript:alert(1)",
        )
        for raw in unsafe:
            payload = _payload({"id": "x", "title": "T", "thumbnail": raw, "formats": []})
            self.assertNotIn("thumbnail", payload, raw)

    def test_no_approved_thumbnail_anywhere_omitted(self):
        payload = _payload({
            "id": "x", "title": "T",
            "thumbnails": [{"url": "https://evil.example.com/a.jpg"}, {"url": None}],
            "formats": [],
        })
        self.assertNotIn("thumbnail", payload)


class BuildPayloadDurationTests(unittest.TestCase):
    def test_duration_values(self):
        payload = _payload({"id": "x", "title": "T", "duration": 0, "formats": []})
        self.assertEqual(payload["duration"], 0)
        payload = _payload({"id": "x", "title": "T", "duration": 123, "formats": []})
        self.assertEqual(payload["duration"], 123)
        payload = _payload({"id": "x", "title": "T", "duration": 12.5, "formats": []})
        self.assertEqual(payload["duration"], 12.5)

    def test_invalid_durations_omitted(self):
        for raw in (-1, math.nan, math.inf, -math.inf, True, "300", None):
            payload = _payload({"id": "x", "title": "T", "duration": raw, "formats": []})
            self.assertNotIn("duration", payload, raw)
            json.dumps(payload)


class BuildPayloadFormatTests(unittest.TestCase):
    def test_format_order_headers_and_size_split_preserved(self):
        payload = _payload({
            "id": "x", "title": "T",
            "formats": [
                {
                    "format_id": "140", "ext": "m4a", "protocol": "https",
                    "acodec": "mp4a.40.2", "vcodec": "none",
                    "url": "https://media.example/140.m4a?ip=1",
                    "http_headers": {"User-Agent": "VIPOD", "Referer": "https://www.youtube.com/"},
                    "filesize": 100, "filesize_approx": 90,
                    "tbr": 128.0, "source_preference": 1, "preference": 2,
                },
                {
                    "format_id": "251", "ext": "webm", "protocol": "https",
                    "acodec": "opus", "vcodec": "none",
                    "url": "https://media.example/251.webm",
                    "http_headers": None,
                    "filesize": None, "filesize_approx": 5000,
                },
            ],
        })
        formats = payload["formats"]
        self.assertEqual([f["formatID"] for f in formats], ["140", "251"])
        self.assertEqual(formats[0]["httpHeaders"], {"User-Agent": "VIPOD", "Referer": "https://www.youtube.com/"})
        self.assertEqual(formats[1]["httpHeaders"], {})
        self.assertEqual(formats[0]["filesize"], 100)
        self.assertEqual(formats[0]["filesizeApprox"], 90)
        self.assertIsNone(formats[1]["filesize"])
        self.assertEqual(formats[1]["filesizeApprox"], 5000)
        self.assertEqual(formats[0]["bitrate"], 128.0)
        self.assertEqual(formats[0]["source_preference"], 1)
        self.assertEqual(formats[0]["preference"], 2)


if __name__ == "__main__":
    unittest.main()
