# AGENTS.md

This file is for future coding agents working on Better Phrase Codex. Keep it focused on context that is not obvious from reading the code.

## Project Intent

Better Phrase Codex is a Codex Desktop / Codex CLI adaptation of [roseduan/better-phrase](https://github.com/roseduan/better-phrase). Preserve the core idea: local deterministic prompt detection, then inject lightweight writing help only when useful.

The project should stay small and dependency-free. Prefer Python standard library and plain shell/PowerShell over package-manager setup unless a new need is strong enough to justify the extra installation surface.

## Non-Obvious Codex Hook Constraints

- Codex hook JSON must be UTF-8 without BOM on Windows. BOM-encoded `hooks.json` has caused hooks to fail silently.
- Windows hook commands are sensitive to quoted paths with spaces. The installer intentionally uses short paths for common Python installs, such as `C:\Progra~1\Python313\python.exe`.
- Codex may require hook trust state in addition to `hooks.json`. The installers try to write trust through `codex app-server`; if that fails, users may need to approve the hook in Codex.
- Keep hook failures silent. A bad payload, missing Python feature, malformed config, or logging failure should not break the user's Codex session.

## Product Behavior

- English polish is the core feature and should remain always on.
- Chinese-to-English translation is a user toggle and defaults to on.
- Code, command-like prompts, short acknowledgements, and low-signal inputs should stay silent.
- The tail-only heuristic exists because Codex hooks do not expose paste metadata. Do not remove it unless Codex adds a better signal.
- The prompt templates are intentionally forceful about prepending the Better Phrase block. Codex otherwise sometimes treats the hook context as optional background.

## Repository Conventions

- Commit as `xianfuxing <xianfuxing@126.com>` for this repository.
- Use Conventional Commit prefixes: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`.
- Keep README user-facing. Put maintainer-only context here instead.
- Do not commit generated files such as `__pycache__/`.

## Verification

Run the stdlib test suite before pushing behavior changes:

```bash
python -m unittest discover -s tests
```

On this Windows workstation, Python is known to exist at:

```powershell
C:\Program Files\Python313\python.exe
```

Installer or hook changes should be checked on Windows first because most of the previous integration issues were Windows path, encoding, or Codex trust related.

## Release Notes For Agents

If you rewrite Git history in this repo, preserve the requested author identity and use `git push --force-with-lease`, not plain force push.

If you change the installed hook command format, test a fresh Codex conversation. A script can compile and unit tests can pass while Codex still ignores a hook due to trust, path quoting, or encoding.
