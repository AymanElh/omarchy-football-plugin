"""Regression tests for api.py (standard library only).

Run:  python3 -m unittest discover -s tests -v
"""
import gzip
import http.server
import json
import subprocess
import threading
import time
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


class DripHandler(http.server.BaseHTTPRequestHandler):
    """Sends valid headers, then one byte at a time, far slower than the deadline."""

    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", "100000")
        self.end_headers()
        try:
            for _ in range(200):
                self.wfile.write(b" ")
                self.wfile.flush()
                time.sleep(0.25)
        except OSError:
            pass

    def log_message(self, *args):
        pass


class DeadlineTests(unittest.TestCase):
    def test_drip_fed_response_hits_the_request_deadline(self):
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), DripHandler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            with mock.patch.object(api, "REQUEST_DEADLINE", 1.0):
                started = time.monotonic()
                with self.assertRaises(ValueError):
                    api._download(f"http://127.0.0.1:{server.server_port}/", {}, 5)
                self.assertLess(time.monotonic() - started, 3.0)
        finally:
            server.shutdown()
            server.server_close()

    def test_watchdog_answers_and_exits_when_a_command_overruns(self):
        code = ("import sys, time; sys.path.insert(0, %r); import api; api.start_deadline(0.5); time.sleep(30)"
                % os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
        started = time.monotonic()
        result = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, timeout=10)
        self.assertLess(time.monotonic() - started, 5.0)
        self.assertEqual(json.loads(result.stdout), {"error": "timeout"})
        self.assertEqual(result.returncode, 0)


class OutputBoundTests(unittest.TestCase):
    def test_long_text_is_clipped(self):
        out = json.loads(api.serialize_bounded({"name": "x" * 10000}))
        self.assertEqual(len(out["name"]), api.MAX_TEXT)

    def test_collections_are_capped(self):
        out = json.loads(api.serialize_bounded([{"events": list(range(5000))} for _ in range(api.MAX_ITEMS + 500)]))
        self.assertEqual(len(out), api.MAX_ITEMS)
        self.assertEqual(len(out[0]["events"]), api.MAX_NESTED_ITEMS)
        many = json.loads(api.serialize_bounded({str(i): i for i in range(api.MAX_DICT_KEYS * 3)}))
        self.assertEqual(len(many), api.MAX_DICT_KEYS)

    def test_nesting_is_capped(self):
        deep = current = {}
        for _ in range(50):
            current["a"] = {}
            current = current["a"]
        text = api.serialize_bounded(deep)
        depth, node = 0, json.loads(text)
        while isinstance(node, dict) and node:
            node = node["a"]
            depth += 1
        self.assertLessEqual(depth, api.MAX_DEPTH + 1)

    def test_total_output_is_bounded_and_keeps_a_prefix(self):
        with mock.patch.object(api, "MAX_OUTPUT_BYTES", 50000):
            rows = [{"id": str(i), "text": "y" * 300} for i in range(1000)]
            text = api.serialize_bounded({"matches": rows, "daysLeft": 3})
        self.assertLessEqual(len(text.encode()), 50000)
        out = json.loads(text)
        self.assertEqual(out["daysLeft"], 3)
        self.assertEqual(out["matches"][0]["id"], "0")
        self.assertLess(len(out["matches"]), 1000)

    def test_unshrinkable_oversize_becomes_an_error(self):
        with mock.patch.object(api, "MAX_OUTPUT_BYTES", 100):
            self.assertEqual(json.loads(api.serialize_bounded({"a": "z" * 300})), {"error": "response too large"})

    def test_only_the_first_answer_is_printed(self):
        with mock.patch.object(api, "_emitted", False), mock.patch.object(api.sys, "stdout") as out:
            api.emit_answer({"first": 1})
            api.emit_answer({"second": 2})
        self.assertEqual(out.write.call_count, 1)


class CommandSmokeTests(unittest.TestCase):
    """Run commands that need no network end to end, through main()."""

    def run_api(self, *args):
        script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "api.py")
        result = subprocess.run([sys.executable, script, *args], capture_output=True, text=True, timeout=20)
        self.assertEqual(result.stderr, "")
        self.assertEqual(result.returncode, 0)
        return json.loads(result.stdout)

    def test_pulse_without_teams_or_leagues(self):
        out = self.run_api("pulse", "", "", '{"alerts": false, "dry": true}')
        self.assertEqual(out["teams"], {})
        self.assertEqual(out["failed"], 0)

    def test_unknown_and_missing_commands_answer_with_an_error(self):
        self.assertIn("Unknown command", self.run_api("nope")["error"])
        self.assertIn("No command", self.run_api()["error"])

    def test_empty_league_matches(self):
        self.assertEqual(self.run_api("league-matches", "")["matches"], [])


if __name__ == "__main__":
    unittest.main()
