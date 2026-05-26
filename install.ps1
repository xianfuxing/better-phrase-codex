param(
    [string]$CodexHome = "$env:USERPROFILE\.codex"
)

$ErrorActionPreference = "Stop"

function Get-PythonCommand {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        $path = $python.Source
        if ($path -like "* *") {
            $short = (cmd.exe /C "for %I in (`"$path`") do @echo %~sI").Trim()
            if ($short) {
                return $short
            }
        }
        return $path
    }

    $default = "C:\Program Files\Python313\python.exe"
    if (Test-Path $default) {
        return "C:\Progra~1\Python313\python.exe"
    }

    throw "Python was not found. Install Python 3.9+ or add it to PATH."
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Trust-Hook {
    param(
        [Parameter(Mandatory = $true)][string]$CodexExe,
        [Parameter(Mandatory = $true)][string]$Cwd
    )

    $script = @"
import json
import subprocess
import sys

codex = r"$CodexExe"
cwd = r"$Cwd"
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
"@

    $script | & (Get-PythonCommand)
}

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$hookDir = Join-Path $CodexHome "hooks"
$scriptSource = Join-Path $repoRoot "hooks\better_phrase_codex.py"
$scriptDest = Join-Path $hookDir "better_phrase_codex.py"
$hooksJsonPath = Join-Path $CodexHome "hooks.json"

New-Item -ItemType Directory -Force -Path $hookDir | Out-Null
Copy-Item -LiteralPath $scriptSource -Destination $scriptDest -Force

$pythonCmd = Get-PythonCommand
$scriptCmdPath = $scriptDest
if ($scriptCmdPath -like "* *") {
    $scriptCmdPath = '"' + $scriptCmdPath + '"'
}

$template = Get-Content -LiteralPath (Join-Path $repoRoot "hooks.json.template") -Raw
$hooksJson = $template.Replace("__PYTHON_CMD__", $pythonCmd).Replace("__SCRIPT_PATH__", $scriptCmdPath)
Write-Utf8NoBom -Path $hooksJsonPath -Content $hooksJson

$codex = Get-Command codex -ErrorAction SilentlyContinue
if (-not $codex -and (Test-Path "$env:LOCALAPPDATA\OpenAI\Codex\bin")) {
    $codex = Get-ChildItem "$env:LOCALAPPDATA\OpenAI\Codex\bin" -Recurse -Filter codex.exe |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

if ($codex) {
    Trust-Hook -CodexExe $codex.Source -Cwd $repoRoot
} else {
    Write-Warning "Codex CLI not found. Restart Codex and approve the hook trust prompt if shown."
}

Write-Host "Installed Better Phrase Codex hook:"
Write-Host "  $scriptDest"
Write-Host "  $hooksJsonPath"
Write-Host "Restart Codex Desktop or open a new conversation to test it."
