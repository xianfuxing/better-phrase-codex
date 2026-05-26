#!/usr/bin/env bash
set -euo pipefail

CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_DIR="$CODEX_HOME_DIR/hooks"
SCRIPT_SOURCE="$REPO_ROOT/hooks/better_phrase_codex.py"
SCRIPT_DEST="$HOOK_DIR/better_phrase_codex.py"
HOOKS_JSON="$CODEX_HOME_DIR/hooks.json"

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

write_utf8_no_bom() {
  local path="$1"
  local content="$2"
  "$PYTHON_CMD" - "$path" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
content = sys.stdin.read()
path.write_text(content, encoding="utf-8", newline="\n")
PY
}

trust_hook() {
  local codex_bin="$1"
  local cwd="$2"
  "$PYTHON_CMD" - "$codex_bin" "$cwd" <<'PY'
import json
import subprocess
import sys

codex = sys.argv[1]
cwd = sys.argv[2]
proc = subprocess.Popen(
    [codex, "app-server", "--listen", "stdio://"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    encoding="utf-8",
    bufsize=1,
)

def send(obj):
    proc.stdin.write(json.dumps(obj) + "\n")
    proc.stdin.flush()

def read_response(target_id):
    while True:
        line = proc.stdout.readline()
        if not line:
            raise RuntimeError(proc.stderr.read())
        msg = json.loads(line)
        if msg.get("id") == target_id:
            return msg

send({"method":"initialize","id":1,"params":{"clientInfo":{"name":"better_phrase_codex_installer","title":"Better Phrase Codex Installer","version":"0.1.0"}}})
read_response(1)
send({"method":"initialized","params":{}})
send({"method":"hooks/list","id":2,"params":{"cwds":[cwd]}})
listed = read_response(2)
hooks = listed["result"]["data"][0]["hooks"]
target = next((h for h in hooks if h.get("eventName") == "userPromptSubmit" and "better_phrase_codex.py" in (h.get("command") or "")), None)
if target is None:
    raise RuntimeError("Better Phrase hook was not discovered by Codex.")
send({
    "method":"config/batchWrite",
    "id":3,
    "params":{
        "edits":[{
            "keyPath":"hooks.state",
            "value":{target["key"]:{"trusted_hash":target["currentHash"]}},
            "mergeStrategy":"upsert"
        }],
        "reloadUserConfig":True
    }
})
print(json.dumps(read_response(3)))
proc.terminate()
PY
}

mkdir -p "$HOOK_DIR"
cp "$SCRIPT_SOURCE" "$SCRIPT_DEST"

PYTHON_CMD="$(python_cmd)"
"$PYTHON_CMD" - "$PYTHON_CMD" "$SCRIPT_DEST" "$HOOKS_JSON" <<'PY'
import json
import pathlib
import sys

python_cmd, script_path, hooks_json = sys.argv[1:4]
command = f'{python_cmd} "{script_path}"' if " " in script_path else f"{python_cmd} {script_path}"
payload = {
    "hooks": {
        "UserPromptSubmit": [
            {
                "hooks": [
                    {
                        "type": "command",
                        "command": command,
                        "commandWindows": command,
                        "timeout": 10,
                        "statusMessage": "Checking Better Phrase",
                    }
                ]
            }
        ]
    }
}
pathlib.Path(hooks_json).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY

CODEX_BIN="${CODEX_BIN:-}"
if [[ -z "$CODEX_BIN" ]]; then
  CODEX_BIN="$(command -v codex || true)"
fi
if [[ -z "$CODEX_BIN" && -d "${LOCALAPPDATA:-}/OpenAI/Codex/bin" ]]; then
  CODEX_BIN="$(find "${LOCALAPPDATA}/OpenAI/Codex/bin" -name codex.exe | sort | tail -n 1 || true)"
fi

if [[ -n "$CODEX_BIN" ]]; then
  trust_hook "$CODEX_BIN" "$REPO_ROOT"
else
  echo "Codex CLI not found. Restart Codex and approve the hook trust prompt if shown." >&2
fi

echo "Installed Better Phrase Codex hook:"
echo "  $SCRIPT_DEST"
echo "  $HOOKS_JSON"
echo "Restart Codex Desktop or open a new conversation to test it."
