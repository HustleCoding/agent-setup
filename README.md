# agent-setup

My personal setup for AI coding agents: how they talk to me, plus three small skills. One source, installed into every harness on the machine.

## Install on a new laptop

```bash
git clone git@github.com:HustleCoding/agent-setup.git ~/Documents/agent-setup
~/Documents/agent-setup/install.sh
```

Re-run `install.sh` after `git pull`. It is safe to run again. Restart open agent sessions afterwards.

## What is in here

| Path | What it is |
|---|---|
| `rules/style.md` | How replies should read: answer first, 1-3 lines, everyday words, details on request, errors never shortened |
| `rules/subagents.md` | Short report format for subagents, which never see an output style |
| `hooks/style-reminder.sh` | Re-anchors the style on every prompt; one JSON shape works in all three harnesses |
| `skills/` | `grill-me`, `grilling`, `handoff` from [mattpocock/skills](https://github.com/mattpocock/skills), MIT |
| `install.sh` | Detects each harness and writes the files below |

## What install.sh writes

| Harness | Files |
|---|---|
| Claude Code | `~/.claude/output-styles/plain.md`, `outputStyle: "Plain"` and the hook in `settings.json`, a managed block in `~/.claude/CLAUDE.md`, skill symlinks in `~/.claude/skills` |
| Codex | managed block in `~/.codex/AGENTS.md`, `model_verbosity = "low"`, `personality = "none"`, `[features] hooks = true` in `config.toml`, the hook in `hooks.json`, skill symlinks in `~/.codex/skills` |
| DeepSeek Harness | managed block in `~/.dsh/AGENTS.md`, the hook in `hooks.json` loaded through `cordis.patch.yml`, skill symlinks in `~/.dsh/skills` |

Managed blocks sit between `agent-setup:begin` and `agent-setup:end` markers, so anything else in those files survives. A real skill folder that would be replaced is moved to `~/.agent-setup-backup/` first.

## Any other harness

Point it at `rules/style.md` + `rules/subagents.md` as its global instructions file and at `skills/` as a skills folder. Both follow the common `AGENTS.md` and `SKILL.md` formats.

## Not handled by the script

These live in each tool's account or UI, so set them by hand once:

- Claude Code plugins: only `impeccable`. No pstack, vercel, typescript-lsp, context7, linear or playwright plugins.
- claude.ai connectors in Claude Code: roam, Figma and Gmail off.
- Codex plugins: canva, gmail, figma, build-web-apps, stripe, vercel, google-calendar off.

Why this shape: the research behind it is at https://claude.ai/artifact/GBr8ACfQ7UFbPjpVYcZGYd.
