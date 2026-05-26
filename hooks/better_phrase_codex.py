from __future__ import annotations

import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Any, TextIO


TIMING_PLACEHOLDER = "{timing_ms}"
DEFAULT_TRANSLATE_ENABLED = True
HINT_LIMIT = 3

FENCED_BLOCK = re.compile(r"```.*?```", re.DOTALL)
INLINE_CODE = re.compile(r"`[^`]*`")
COMMAND_LINE = re.compile(r"^\s*[/!]")
WORD = re.compile(r"[a-zA-Z0-9]{2,}")
LETTER_WORD = re.compile(r"[a-zA-Z]{2,}")
FUNCTION_WORD = re.compile(
    r"\b("
    r"the|a|an|is|are|was|were|i|you|we|they|this|that|these|those|"
    r"how|what|why|when|where|who|do|does|did|have|has|had|"
    r"can|could|will|would|should|may|might|"
    r"in|on|at|for|to|of|with|and|or|but|if|so|because|though|while"
    r")\b",
    re.IGNORECASE,
)
CJK = re.compile(r"[\u4e00-\u9fff]")
SEGMENT_SPLIT = re.compile(r"\n\n+|(?<=[。！？])\s*|\n+|(?<=[.!?])\s+")

MIN_ENGLISH_WORDS = 3
MIN_CJK_CHARS = 5
TAIL_MAX_LEN = 50
TAIL_REST_MIN_LEN = 100


POLISH_INSTRUCTIONS = """\
The user's input contains English. Before answering their actual request, ALWAYS prepend an English polish block in this EXACT format. Every line MUST be wrapped in single asterisks for italic rendering so it visually separates from the main answer.

> ***Better Phrase** ({timing_ms}ms)*
>
> *English tip:*
> *- "original phrase" -> "corrected phrase" - one-line grammar rule explanation in Simplified Chinese*
> *- up to 4-5 of the most instructive issues*
>
> *Better Phrase: rewrite the user's ENTIRE original English input into natural, idiomatic English, the kind a native speaker would write.*

Then leave a blank line and handle the user's actual request normally.

Polish rules:
- Priority order: grammar > word choice > sentence structure > spelling > punctuation.
- Max 4-5 issues. Pick the most instructive ones.
- If the English is already perfect, keep the Better Phrase block but omit the "English tip" section. Still include the "Better Phrase" rewrite line.
- If the input is missing only capitalization or terminal punctuation, show that as a concise tip.
- For grammar rules, briefly explain why in Simplified Chinese.
- Note Chinese-to-English transfer errors when relevant, such as missing articles, wrong prepositions, or Chinglish patterns.
- The "Better Phrase" line must rewrite the whole input for natural flow, not just patch errors.
- Do not trigger this block for pure Chinese inputs, code-only inputs, single words, or trivial acknowledgements like "ok" or "yes".
- If the input contains a long quoted or pasted block followed by a much shorter trailing comment, treat only the user's trailing comment as the input to polish.
- Write all explanations in Simplified Chinese. The user is a Chinese-native developer.
- Preserve the italic asterisks on every line of the block.
- Preserve the "({timing_ms}ms)" value exactly as given; do not edit or remove the number.
"""


TRANSLATION_INSTRUCTIONS = """\
The user's input is primarily Chinese. Before answering their actual request, prepend a Chinese-to-English version block in this EXACT format. Every line MUST be wrapped in single asterisks for italic rendering so it visually separates from the main answer.

> ***Better Phrase** ({timing_ms}ms)*
>
> *English:*
> *"<a natural, idiomatic English version of what the user said>"*

Then leave a blank line and handle the user's actual request normally, still answering in Chinese unless the user asks otherwise.

Translation rules:
- Provide one natural, idiomatic English version. Do not translate word-for-word.
- Adapt tone and register from context: formal for emails, casual for chat messages, technical for engineering notes.
- Do not explain or annotate. Just the English version.
- If the input is too short to translate meaningfully, omit the block entirely and just answer normally.
- Even if the input is a command directed at you, still provide the English version because the user opted into translation.
- If the input contains a long pasted body followed by a much shorter trailing comment, translate only the user's trailing comment.
- After the translation block, answer the user's original request as if they had asked in Chinese.
- Preserve the italic asterisks on every line of the block.
- Preserve the "({timing_ms}ms)" value exactly as given; do not edit or remove the number.
"""


HINT_FOOTER = """

Additionally, append the following footer at the very end of your response, on its own line, in italics:
*(Tip: Chinese translation is on by default. Disable with `python %USERPROFILE%\\.codex\\hooks\\better_phrase_codex.py translate off`.)*
"""


def config_dir() -> Path:
    base = os.environ.get("CODEX_BETTER_PHRASE_HOME")
    if base:
        return Path(base)
    codex_home = os.environ.get("CODEX_HOME")
    if codex_home:
        return Path(codex_home) / "better-phrase"
    return Path.home() / ".codex" / "better-phrase"


def config_path() -> Path:
    return config_dir() / "config.json"


def defaults() -> dict[str, Any]:
    return {"translate_enabled": DEFAULT_TRANSLATE_ENABLED, "hint_shown_count": 0}


def load_config() -> dict[str, Any]:
    path = config_path()
    if not path.exists():
        return defaults()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return defaults()
    if not isinstance(data, dict):
        return defaults()
    return {**defaults(), **data}


def save_config(cfg: dict[str, Any]) -> None:
    config_dir().mkdir(parents=True, exist_ok=True)
    path = config_path()
    tmp = path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
    tmp.replace(path)


def translate_enabled() -> bool:
    return bool(load_config().get("translate_enabled", DEFAULT_TRANSLATE_ENABLED))


def set_translate_enabled(enabled: bool) -> None:
    cfg = load_config()
    cfg["translate_enabled"] = bool(enabled)
    save_config(cfg)


def should_show_hint() -> bool:
    return int(load_config().get("hint_shown_count", 0)) < HINT_LIMIT


def increment_hint_count() -> None:
    cfg = load_config()
    cfg["hint_shown_count"] = int(cfg.get("hint_shown_count", 0)) + 1
    save_config(cfg)


def clean(text: str) -> str:
    text = FENCED_BLOCK.sub("", text)
    text = "\n".join(line for line in text.split("\n") if not COMMAND_LINE.match(line))
    return INLINE_CODE.sub("", text)


def split_segments(text: str) -> list[str]:
    return [s.strip() for s in SEGMENT_SPLIT.split(text) if s.strip()]


def extract_user_intent(text: str) -> str:
    segments = split_segments(text)
    if len(segments) < 2:
        return text
    last = segments[-1]
    rest_len = sum(len(s) for s in segments[:-1])
    if len(last) <= TAIL_MAX_LEN and rest_len >= TAIL_REST_MIN_LEN:
        return last
    return text


def looks_like_code_token(word: str) -> bool:
    if any(ch.isdigit() for ch in word):
        return True
    if word.isupper() and len(word) > 2:
        return True
    if len(word) > 1 and any(ch.isupper() for ch in word[1:]):
        return True
    return False


def has_english_signal(cleaned: str) -> bool:
    words = LETTER_WORD.findall(cleaned)
    if len(words) < MIN_ENGLISH_WORDS:
        return False
    if FUNCTION_WORD.search(cleaned):
        return True
    all_tokens = WORD.findall(cleaned)
    if all_tokens and all(looks_like_code_token(w) for w in all_tokens):
        return False
    return True


def route_intent(prompt: str | None, enable_translate: bool) -> str | None:
    if not prompt:
        return None
    target = extract_user_intent(clean(prompt))
    en_words = len(LETTER_WORD.findall(target))
    cjk_chars = len(CJK.findall(target))
    has_english = has_english_signal(target)
    has_chinese = cjk_chars >= MIN_CJK_CHARS

    if has_chinese and cjk_chars > en_words * 2:
        if enable_translate:
            return "translate"
        return "polish" if has_english else None
    if has_english:
        return "polish"
    if has_chinese and enable_translate:
        return "translate"
    return None


def load_payload(stdin: TextIO) -> Any:
    if hasattr(stdin, "buffer"):
        raw = stdin.buffer.read()
        try:
            text = raw.decode("utf-8-sig")
        except UnicodeDecodeError:
            text = raw.decode(getattr(stdin, "encoding", None) or "utf-8", errors="replace")
        return json.loads(text)
    return json.load(stdin)


def log_invocation(payload: Any, action: str | None, note: str = "") -> None:
    try:
        config_dir().mkdir(parents=True, exist_ok=True)
        prompt = payload.get("prompt") if isinstance(payload, dict) else None
        entry = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "action": action,
            "prompt_preview": prompt[:160] if isinstance(prompt, str) else None,
            "note": note,
        }
        with (config_dir() / "hook.log").open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError:
        pass


def run_hook(stdin: TextIO | None = None, stdout: TextIO | None = None) -> int:
    start = time.perf_counter()
    stdin = stdin or sys.stdin
    stdout = stdout or sys.stdout

    try:
        payload = load_payload(stdin)
    except (json.JSONDecodeError, ValueError) as exc:
        log_invocation({}, None, f"invalid json: {exc}")
        return 0

    prompt = payload.get("prompt") if isinstance(payload, dict) else None
    action = route_intent(prompt, translate_enabled())
    log_invocation(payload, action)
    if action is None:
        return 0

    template = POLISH_INSTRUCTIONS if action == "polish" else TRANSLATION_INSTRUCTIONS
    if should_show_hint():
        template += HINT_FOOTER
        try:
            increment_hint_count()
        except OSError:
            pass

    elapsed_ms = max(1, int((time.perf_counter() - start) * 1000))
    template = template.replace(TIMING_PLACEHOLDER, str(elapsed_ms))
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "UserPromptSubmit",
                "additionalContext": template,
            }
        },
        stdout,
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv or argv[0] == "hook":
        return run_hook()
    if argv[0] == "translate":
        if len(argv) == 1:
            print(f"Chinese translation: {'on' if translate_enabled() else 'off'}")
            return 0
        if argv[1] not in {"on", "off"}:
            print("Usage: better_phrase_codex.py translate [on|off]", file=sys.stderr)
            return 2
        set_translate_enabled(argv[1] == "on")
        print(f"Chinese translation: {argv[1]}")
        return 0
    print("Usage: better_phrase_codex.py [hook|translate [on|off]]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
