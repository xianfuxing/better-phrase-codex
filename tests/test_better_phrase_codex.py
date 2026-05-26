from __future__ import annotations

import importlib.util
import io
import json
import os
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HOOK_PATH = ROOT / "hooks" / "better_phrase_codex.py"


def load_hook_module():
    spec = importlib.util.spec_from_file_location("better_phrase_codex", HOOK_PATH)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


bp = load_hook_module()


class DetectorTests(unittest.TestCase):
    def test_strips_fenced_blocks_and_inline_code(self):
        cleaned = bp.clean("hello ```secret english words``` see `foo()` world")
        self.assertNotIn("secret", cleaned)
        self.assertNotIn("foo", cleaned)
        self.assertIn("hello", cleaned)

    def test_strips_command_lines(self):
        self.assertEqual(bp.clean("/help me please\nhow are you today"), "how are you today")
        self.assertEqual(bp.clean("!ls -la\nhow are you today"), "how are you today")

    def test_routes_english_to_polish(self):
        self.assertEqual(bp.route_intent("how are you today", True), "polish")
        self.assertEqual(bp.route_intent("how are you today", False), "polish")

    def test_routes_chinese_to_translate_when_enabled(self):
        self.assertEqual(bp.route_intent("请帮我检查这个项目", True), "translate")

    def test_chinese_is_silent_when_translation_disabled(self):
        self.assertIsNone(bp.route_intent("请帮我检查这个项目", False))

    def test_code_like_tokens_are_silent(self):
        self.assertIsNone(bp.route_intent("useState useEffect useMemo", True))

    def test_tail_only_heuristic_uses_short_trailing_prompt(self):
        long_body = "这是一段很长的中文粘贴内容。" * 12
        self.assertEqual(
            bp.extract_user_intent(long_body + " what does this mean please"),
            "what does this mean please",
        )


class HookTests(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.old_home = os.environ.get("CODEX_BETTER_PHRASE_HOME")
        os.environ["CODEX_BETTER_PHRASE_HOME"] = self.tmpdir.name

    def tearDown(self):
        if self.old_home is None:
            os.environ.pop("CODEX_BETTER_PHRASE_HOME", None)
        else:
            os.environ["CODEX_BETTER_PHRASE_HOME"] = self.old_home
        self.tmpdir.cleanup()

    def run_hook(self, payload: object) -> str:
        stdin = io.StringIO(json.dumps(payload) if not isinstance(payload, str) else payload)
        stdout = io.StringIO()
        code = bp.run_hook(stdin=stdin, stdout=stdout)
        self.assertEqual(code, 0)
        return stdout.getvalue()

    def suppress_hint(self):
        cfg = bp.load_config()
        cfg["hint_shown_count"] = bp.HINT_LIMIT
        bp.save_config(cfg)

    def test_invalid_json_is_silent(self):
        self.assertEqual(self.run_hook("not json"), "")

    def test_empty_prompt_is_silent(self):
        self.assertEqual(self.run_hook({"prompt": ""}), "")

    def test_english_prompt_emits_codex_hook_output(self):
        self.suppress_hint()
        out = self.run_hook({"prompt": "how are you today"})
        parsed = json.loads(out)
        ctx = parsed["hookSpecificOutput"]["additionalContext"]
        self.assertEqual(parsed["hookSpecificOutput"]["hookEventName"], "UserPromptSubmit")
        self.assertIn("English tip", ctx)
        self.assertNotIn("{timing_ms}", ctx)

    def test_translate_toggle_controls_chinese_output(self):
        self.suppress_hint()
        out = self.run_hook({"prompt": "请帮我检查这个项目"})
        self.assertIn("English:", json.loads(out)["hookSpecificOutput"]["additionalContext"])

        bp.set_translate_enabled(False)
        self.assertEqual(self.run_hook({"prompt": "请帮我检查这个项目"}), "")

    def test_hint_footer_disappears_after_limit(self):
        for _ in range(bp.HINT_LIMIT):
            self.run_hook({"prompt": "how are you today"})

        out = self.run_hook({"prompt": "how are you today"})
        ctx = json.loads(out)["hookSpecificOutput"]["additionalContext"]
        self.assertNotIn("Chinese translation is on by default", ctx)


if __name__ == "__main__":
    unittest.main()
