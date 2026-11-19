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


if __name__ == "__main__":
    unittest.main()
