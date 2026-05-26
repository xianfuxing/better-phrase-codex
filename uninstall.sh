#!/usr/bin/env bash
set -euo pipefail

PURGE=false
for arg in "$@"; do
  case "$arg" in
    --purge)
      PURGE=true
      ;;
    -h|--help)
      cat <<'EOF'
Better Phrase Codex uninstaller.

Usage:
  bash ./uninstall.sh
  bash ./uninstall.sh --purge

Options:
  --purge       Also delete the installed hook script and local config.
  -h, --help    Show this help and exit.
EOF
      exit 0
      ;;
    *)
      printf "Unknown flag: %s (try --help)\n" "$arg" >&2
      exit 2
      ;;
  esac
done

CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
HOOKS_JSON="$CODEX_HOME_DIR/hooks.json"
HOOK_SCRIPT="$CODEX_HOME_DIR/hooks/better_phrase_codex.py"
CONFIG_DIR="$CODEX_HOME_DIR/better-phrase"

python_cmd() {
  if command -v python3 >/dev/null 2>&1; then
    command -v python3
  elif command -v python >/dev/null 2>&1; then
    command -v python
  else
    echo "python3 not found on PATH" >&2
    exit 1
  fi
}

PYTHON_CMD="$(python_cmd)"

if [[ ! -f "$HOOKS_JSON" ]]; then
  echo "No Codex hooks.json found. Nothing to remove from hook config."
else
  BACKUP="$HOOKS_JSON.backup-$(date +%Y%m%d-%H%M%S)"
  cp "$HOOKS_JSON" "$BACKUP"
  "$PYTHON_CMD" - "$HOOKS_JSON" <<'PY'
import json
import os
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8-sig"))
removed = 0

hooks = data.get("hooks")
if isinstance(hooks, dict):
    entries = hooks.get("UserPromptSubmit")
    if isinstance(entries, list):
        kept_entries = []
        for entry in entries:
            nested = entry.get("hooks") if isinstance(entry, dict) else None
            if isinstance(nested, list):
                kept_hooks = []
                for hook in nested:
                    command = str(hook.get("command", "")) if isinstance(hook, dict) else ""
                    command_windows = str(hook.get("commandWindows", "")) if isinstance(hook, dict) else ""
                    if "better_phrase_codex.py" in command or "better_phrase_codex.py" in command_windows:
                        removed += 1
                    else:
                        kept_hooks.append(hook)
                if kept_hooks:
                    entry["hooks"] = kept_hooks
                    kept_entries.append(entry)
            else:
                command = str(entry.get("command", "")) if isinstance(entry, dict) else ""
                command_windows = str(entry.get("commandWindows", "")) if isinstance(entry, dict) else ""
                if "better_phrase_codex.py" in command or "better_phrase_codex.py" in command_windows:
                    removed += 1
                else:
                    kept_entries.append(entry)

        if kept_entries:
            hooks["UserPromptSubmit"] = kept_entries
        else:
            hooks.pop("UserPromptSubmit", None)

    if not hooks:
        data.pop("hooks", None)

tmp = path.with_suffix(path.suffix + ".tmp")
tmp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
os.replace(tmp, path)
print(removed)
PY
  echo "Backup written to:"
  echo "  $BACKUP"
fi

if [[ "$PURGE" == "true" ]]; then
  if [[ -f "$HOOK_SCRIPT" ]]; then
    rm -f "$HOOK_SCRIPT"
    echo "Removed hook script:"
    echo "  $HOOK_SCRIPT"
  fi

  if [[ -d "$CONFIG_DIR" ]]; then
    rm -rf "$CONFIG_DIR"
    echo "Removed Better Phrase Codex config:"
    echo "  $CONFIG_DIR"
  fi
else
  echo "Installed script and local config were left in place."
  echo "Re-run with --purge to remove them too."
fi

echo "Restart Codex Desktop or open a new conversation to pick up the change."
