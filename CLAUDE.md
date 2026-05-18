# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A single Bash script (`codex-linux.sh`) that bootstraps an AI coding environment on Linux: installs Node.js 22, bubblewrap, `@openai/codex`, `@anthropic-ai/claude-code`, and `cc-switch-cli`, then generates config files for both tools.

## Shell script conventions

- `set -euo pipefail` is used throughout.
- The script is written for Bash (not POSIX sh). `[[` and here-strings are fine.
- Distro detection is done via `/etc/os-release` (`ID` and `ID_LIKE` fields).
- Package installation uses sudo when available, falling back to direct execution.
- Config files are written with heredocs; directories are `chmod 700`, auth files `chmod 600`.

## Testing

No test suite exists. To validate changes to the script:

```bash
shellcheck codex-linux.sh
```

For a dry-run, run the script and kill it at the first interactive prompt (API key input), or test individual functions in isolation.

## Config files generated

| File | Tool | Content |
|------|------|---------|
| `~/.codex/auth.json` | Codex | OpenAI API key |
| `~/.codex/config.toml` | Codex | Model provider (`rightcode`), model, base URL |
| `~/.claude/settings.json` | Claude Code | DeepSeek Anthropic-compatible API credentials and model env vars |
