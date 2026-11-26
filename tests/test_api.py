"""Regression tests for api.py (standard library only).

Run:  python3 -m unittest discover -s tests -v
"""
import gzip
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import api  # noqa: E402

MARKUP = '<img src="https://example.invalid/tracker">Messi &lt;b&gt;&#x41;'


class PlainTextTests(unittest.TestCase):
    def test_tags_are_neutralised(self):
        out = api.plain_text(MARKUP, 300)
        self.assertNotIn("<", out)
        self.assertNotIn(">", out)

    def test_entities_are_neutralised(self):
        out = api.plain_text("A &lt;b&gt; B &#x41; C &amp; D", 300)
        self.assertNotRegex(out, r"&#?\w+;")

    def test_normal_names_survive(self):
        self.assertEqual(api.plain_text("Brighton & Hove Albion", 300), "Brighton & Hove Albion")
        self.assertEqual(api.plain_text("Atlético Madrid", 300), "Atlético Madrid")

    def test_control_characters_removed_and_length_bounded(self):
        self.assertEqual(api.plain_text("a\x00b\x1bc", 10), "abc")
        self.assertEqual(len(api.plain_text("x" * 1000, 120)), 120)

    def test_notify_sends_neutralised_text(self):
        with mock.patch.object(api.subprocess, "run") as run:
            api.notify(MARKUP, MARKUP)
        command = run.call_args[0][0]
        title, body = command[-2], command[-1]
        for text in (title, body):
            self.assertNotIn("<", text)
            self.assertNotIn(">", text)
        self.assertIn("--", command[:-2])  # text comes after the option terminator


class DownloadLimitTests(unittest.TestCase):
    def test_gzip_bomb_is_refused(self):
        bomb = gzip.compress(b"0" * (api.MAX_BYTES + 1024))
        self.assertLess(len(bomb), api.MAX_BYTES)          # passes the compressed-size check
        with self.assertRaises(ValueError):
            api.bounded_gunzip(bomb)

    def test_normal_gzip_roundtrip(self):
        self.assertEqual(api.bounded_gunzip(gzip.compress(b'{"ok": true}')), b'{"ok": true}')

    def test_corrupt_gzip_is_a_value_error(self):
        with self.assertRaises(ValueError):
            api.bounded_gunzip(b"\x1f\x8b not really gzip")


class NormaliseTests(unittest.TestCase):
    def test_markup_in_team_name_stays_data(self):
        event = {
            "id": "1", "date": "2026-11-26T20:00Z",
            "status": {"type": {"state": "pre", "name": "STATUS_SCHEDULED", "detail": "", "shortDetail": ""}},
            "competitions": [{"competitors": [
                {"homeAway": "home", "id": "1", "score": "0", "team": {"id": "1", "displayName": MARKUP, "shortDisplayName": MARKUP}},
                {"homeAway": "away", "id": "2", "score": "0", "team": {"id": "2", "displayName": "B", "shortDisplayName": "B"}},
            ]}],
        }
        match = api.normalize_event(event, "esp.1")
        self.assertIsInstance(match, dict)
        self.assertIsInstance(match["home"], str)


if __name__ == "__main__":
    unittest.main()
