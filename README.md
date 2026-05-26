# Better Phrase Codex

English phrasing polish and Chinese-to-English translation for Codex Desktop, powered by Codex `UserPromptSubmit` hooks.

Inspired by [roseduan/better-phrase](https://github.com/roseduan/better-phrase), adapted for Codex hooks.

## What It Does

- English input: injects a Better Phrase block before Codex answers, with grammar tips and a natural rewrite.
- Chinese input: injects a natural English version before Codex answers.
- Code, commands, and low-signal input: stays silent.
- Runs locally: no API calls, no telemetry.

## Requirements

- Codex Desktop or Codex CLI with hook support.
- Python 3.9+ on PATH, or installed under `C:\Program Files\Python313\python.exe` on Windows.

## Install

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

macOS / Linux:

```bash
bash ./install.sh
```

Restart Codex Desktop or open a new conversation, then test:

```text
how are you taday
```

If Codex asks whether to trust the hook, approve it. The installer also writes the trust entry automatically by using Codex `app-server` when the Codex CLI is available.

## Uninstall

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -Purge
```

macOS / Linux:

```bash
bash ./uninstall.sh
bash ./uninstall.sh --purge
```

The default uninstall removes only the Better Phrase Codex hook entry from `~/.codex/hooks.json` and writes a timestamped backup. The purge mode also removes the installed hook script and local Better Phrase config.

## Files

- `hooks/better_phrase_codex.py` - hook implementation.
- `hooks.json.template` - Codex hook config template.
- `install.ps1` - installs the script and hook config into `%USERPROFILE%\.codex`.
- `install.sh` - same installer for POSIX shells.
- `uninstall.ps1` - removes the hook from Codex on Windows.
- `uninstall.sh` - removes the hook from Codex on macOS / Linux.
- `tests/` - stdlib `unittest` coverage for detection, routing, hook output, and config toggles.

## Toggle Chinese Translation

```powershell
python $env:USERPROFILE\.codex\hooks\better_phrase_codex.py translate
python $env:USERPROFILE\.codex\hooks\better_phrase_codex.py translate off
python $env:USERPROFILE\.codex\hooks\better_phrase_codex.py translate on
```

English polish stays on. To disable everything, run the uninstall script.

## Test

```bash
python -m unittest discover -s tests
```

## License

Apache-2.0.
