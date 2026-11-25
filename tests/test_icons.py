"""Topic icon allowlist checks for recent_chats.py. Run from the repo root:
python3 -m unittest tests/test_icons.py"""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from recent_chats import load_allowlist, parse_args, pick_prompt, valid_icon  # noqa: E402


class IconTests(unittest.TestCase):
    def test_valid_icon_accepts_listed(self):
        self.assertEqual(valid_icon("key", {"key"}), "key")

    def test_valid_icon_rejects_unlisted_and_emoji(self):
        self.assertIsNone(valid_icon("🔑", {"key"}))
        self.assertIsNone(valid_icon("sparkles.rectangle.stack.fill.badge", {"key"}))

    def test_allowlist_file_loads(self):
        self.assertGreaterEqual(len(load_allowlist(ROOT / "icons.json")), 40)

    def test_bare_run_has_icon_off(self):
        self.assertEqual(parse_args([]).icon, "off")

    def test_prompt_embeds_allowlist(self):
        allow = load_allowlist(ROOT / "icons.json")
        p = pick_prompt(allow)
        for name in allow:
            self.assertIn(name, p)



class RepickTests(unittest.TestCase):
    """An off-list pick is remembered as no icon, so it isn't asked about again."""

    def setUp(self):
        import tempfile
        import recent_chats as rc
        self.rc = rc
        self.tmp = Path(tempfile.mkdtemp())
        self.saved = (rc.CHAT_ICONS, rc.FOLDER_ICONS, rc.haiku)
        rc.CHAT_ICONS = self.tmp / "chat-icons.json"
        rc.FOLDER_ICONS = self.tmp / "folder-icons.json"
        self.calls = 0

    def tearDown(self):
        self.rc.CHAT_ICONS, self.rc.FOLDER_ICONS, self.rc.haiku = self.saved

    def fake(self, reply):
        def h(prompt):
            self.calls += 1
            return reply
        self.rc.haiku = h

    def run_chat(self, allow):
        rows = [{"id": "c1", "title": "t", "status": "waiting"}]
        info = {"c1": {"key": "k", "opening": "o", "reply": "r"}}
        return self.rc.chat_extras(rows, info, {}, True, False, True, False, allow)

    def test_offlist_chat_pick_not_reasked(self):
        self.fake('[{"id": "c1", "icon": "pencil.line"}]')
        auto, _, _ = self.run_chat({"key"})
        self.assertIsNone(valid_icon(auto["c1"], {"key"}))
        self.run_chat({"key"})
        self.assertEqual(self.calls, 1)

    def test_empty_allowlist_sends_nothing(self):
        self.fake('[]')
        self.run_chat(set())
        self.assertEqual(self.calls, 0)

    def test_offlist_folder_pick_not_reasked(self):
        self.fake('{"f": "pencil.line"}')
        out = self.rc.folder_icons({"f"}, True, False, {"key"})
        self.assertIsNone(valid_icon(out["f"][0], {"key"}))
        self.rc.folder_icons({"f"}, True, False, {"key"})
        self.assertEqual(self.calls, 1)

    def test_empty_allowlist_no_folder_call(self):
        self.fake('{}')
        self.rc.folder_icons({"f"}, True, False, set())
        self.assertEqual(self.calls, 0)


if __name__ == "__main__":
    unittest.main()


class LastMessageTests(unittest.TestCase):
    """Group by Day uses the newest message's time, not the file's."""

    def test_newest_timestamp_wins(self):
        from recent_chats import last_message_at
        recs = [{"timestamp": "2026-11-20T10:00:00Z"}, {"timestamp": "2026-11-21T09:30:00.500Z"}, {}]
        self.assertAlmostEqual(last_message_at(recs, 0), 1795253400.5)

    def test_falls_back_without_timestamps(self):
        from recent_chats import last_message_at
        self.assertEqual(last_message_at([{}, {"timestamp": "bad"}], 42.0), 42.0)
