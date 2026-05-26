param(
    [string]$CodexHome = "$env:USERPROFILE\.codex",
    [switch]$Purge
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function ConvertTo-OrderedJson {
    param([Parameter(Mandatory = $true)]$Object)
    return ($Object | ConvertTo-Json -Depth 20)
}

$hooksJsonPath = Join-Path $CodexHome "hooks.json"
$hookScriptPath = Join-Path $CodexHome "hooks\better_phrase_codex.py"
$configDir = Join-Path $CodexHome "better-phrase"

if (-not (Test-Path -LiteralPath $hooksJsonPath)) {
    Write-Host "No Codex hooks.json found. Nothing to remove from hook config."
} else {
    $backupPath = "$hooksJsonPath.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -LiteralPath $hooksJsonPath -Destination $backupPath -Force

    $raw = Get-Content -LiteralPath $hooksJsonPath -Raw
    $config = $raw | ConvertFrom-Json
    $removed = 0

    if ($config.hooks -and $config.hooks.UserPromptSubmit) {
        $keptEntries = @()
        foreach ($entry in @($config.hooks.UserPromptSubmit)) {
            if ($entry.hooks) {
                $keptHooks = @()
                foreach ($hook in @($entry.hooks)) {
                    $command = [string]$hook.command
                    $commandWindows = [string]$hook.commandWindows
                    if ($command.Contains("better_phrase_codex.py") -or $commandWindows.Contains("better_phrase_codex.py")) {
                        $removed += 1
                    } else {
                        $keptHooks += $hook
                    }
                }
                if ($keptHooks.Count -gt 0) {
                    $entry.hooks = $keptHooks
                    $keptEntries += $entry
                }
            } else {
                $command = [string]$entry.command
                $commandWindows = [string]$entry.commandWindows
                if ($command.Contains("better_phrase_codex.py") -or $commandWindows.Contains("better_phrase_codex.py")) {
                    $removed += 1
                } else {
                    $keptEntries += $entry
                }
            }
        }

        if ($keptEntries.Count -gt 0) {
            $config.hooks.UserPromptSubmit = $keptEntries
        } else {
            $config.hooks.PSObject.Properties.Remove("UserPromptSubmit")
        }

        if ($config.hooks.PSObject.Properties.Count -eq 0) {
            $config.PSObject.Properties.Remove("hooks")
        }
    }

    Write-Utf8NoBom -Path $hooksJsonPath -Content ((ConvertTo-OrderedJson $config) + "`n")
    Write-Host "Removed $removed Better Phrase Codex hook entry/entries."
    Write-Host "Backup written to:"
    Write-Host "  $backupPath"
}

if ($Purge) {
    if (Test-Path -LiteralPath $hookScriptPath) {
        Remove-Item -LiteralPath $hookScriptPath -Force
        Write-Host "Removed hook script:"
        Write-Host "  $hookScriptPath"
    }

    if (Test-Path -LiteralPath $configDir) {
        Remove-Item -LiteralPath $configDir -Recurse -Force
        Write-Host "Removed Better Phrase Codex config:"
        Write-Host "  $configDir"
    }
} else {
    Write-Host "Installed script and local config were left in place."
    Write-Host "Re-run with -Purge to remove them too."
}

Write-Host "Restart Codex Desktop or open a new conversation to pick up the change."
