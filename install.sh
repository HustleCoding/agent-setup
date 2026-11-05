#!/bin/bash
# Installs this setup into every agent harness found on the machine.
# Safe to re-run: it converges to the same state (run it again after `git pull`).
# Harnesses: Claude Code (~/.claude), Codex (~/.codex), DeepSeek Harness (~/.dsh).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="bash '$REPO/hooks/style-reminder.sh'"
BACKUP="$HOME/.agent-setup-backup/$(date +%Y%m%d-%H%M%S)"
BEGIN="<!-- agent-setup:begin (managed by $REPO/install.sh, edit the repo not this block) -->"
END="<!-- agent-setup:end -->"

say() { printf '  %s\n' "$*"; }
has() { [ -d "$HOME/$1" ] || command -v "$2" >/dev/null 2>&1; }
command -v python3 >/dev/null || { echo "install.sh needs python3 on PATH" >&2; exit 1; }

# Write $2 between the markers in file $1, keeping anything else the file holds.
managed_block() {
  mkdir -p "$(dirname "$1")"
  python3 -I - "$1" "$BEGIN" "$END" "$2" <<'PY'
import sys, os, re
path, begin, end, body = sys.argv[1:5]
text = open(path).read() if os.path.exists(path) else ""
block = f"{begin}\n{body.strip()}\n{end}\n"
pat = re.compile(re.escape(begin.split(" (")[0]) + r".*?" + re.escape(end) + r"\n?", re.S)
text = pat.sub(lambda _: block, text) if pat.search(text) else (text.rstrip() + "\n\n" + block if text.strip() else block)
open(path, "w").write(text)
PY
}

# Add our UserPromptSubmit hook to a Claude-format hooks JSON file, dropping older copies of it.
# Optional $2: a top-level outputStyle value to set in the same file.
merge_hook_json() {
  mkdir -p "$(dirname "$1")"
  python3 -I - "$1" "$HOOK" "${2:-}" <<'PY'
import sys, os, json
path, cmd, style = sys.argv[1:4]
data = json.load(open(path)) if os.path.exists(path) and open(path).read().strip() else {}
hooks = data.setdefault("hooks", {})
groups = [g for g in hooks.get("UserPromptSubmit", [])
          if not any("style-reminder" in h.get("command", "") for h in g.get("hooks", []))]
groups.append({"hooks": [{"type": "command", "command": cmd, "timeout": 5}]})
hooks["UserPromptSubmit"] = groups
if style:
    data["outputStyle"] = style
open(path, "w").write(json.dumps(data, indent=2) + "\n")
PY
}

# Symlink every repo skill into $1, so `git pull` updates them in place.
link_skills() {
  mkdir -p "$1"
  for src in "$REPO"/skills/*/; do
    name="$(basename "$src")"; dst="$1/$name"
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
      mkdir -p "$BACKUP/$(basename "$(dirname "$1")")"; mv "$dst" "$BACKUP/$(basename "$(dirname "$1")")/"
      say "moved existing $dst to $BACKUP"
    fi
    ln -sfn "${src%/}" "$dst"
  done
}

STYLE="$(cat "$REPO/rules/style.md")"
SUBAGENTS="$(cat "$REPO/rules/subagents.md")"
AGENTS_MD="$STYLE

$SUBAGENTS"

if has .claude claude; then
  echo "Claude Code"
  mkdir -p "$HOME/.claude/output-styles"
  printf -- '---\nname: Plain\ndescription: Answer first, everyday words, 1-3 lines unless asked for more\nkeep-coding-instructions: true\n---\n\n%s\n' "$STYLE" > "$HOME/.claude/output-styles/plain.md"
  managed_block "$HOME/.claude/CLAUDE.md" "$SUBAGENTS"
  merge_hook_json "$HOME/.claude/settings.json" "Plain"
  link_skills "$HOME/.claude/skills"
  say "output style Plain, CLAUDE.md subagent block, hook, skills"
fi

if has .codex codex; then
  echo "Codex"
  managed_block "$HOME/.codex/AGENTS.md" "$AGENTS_MD"
  merge_hook_json "$HOME/.codex/hooks.json"
  touch "$HOME/.codex/config.toml"
  python3 -I - "$HOME/.codex/config.toml" <<'PY'
import sys, re
path = sys.argv[1]; t = open(path).read()
for key, val in (("model_verbosity", '"low"'), ("personality", '"none"')):
    line = f"{key} = {val}"
    t = re.sub(rf"^{key}\s*=.*$", line, t, count=1, flags=re.M) if re.search(rf"^{key}\s*=", t, re.M) else line + "\n" + t
if re.search(r"^\[features\]", t, re.M):
    if not re.search(r"^\[features\][^\[]*^hooks\s*=", t, re.M | re.S):
        t = re.sub(r"^\[features\]\n", "[features]\nhooks = true\n", t, count=1, flags=re.M)
    else:
        t = re.sub(r"(^\[features\][^\[]*?^)hooks\s*=[^\n]*", r"\1hooks = true", t, count=1, flags=re.M | re.S)
else:
    t = t.rstrip() + "\n\n[features]\nhooks = true\n"
open(path, "w").write(t)
PY
  link_skills "$HOME/.codex/skills"
  say "AGENTS.md, verbosity low, personality none, hook, skills"
fi

if has .dsh dsh; then
  echo "DeepSeek Harness"
  managed_block "$HOME/.dsh/AGENTS.md" "$AGENTS_MD"
  merge_hook_json "$HOME/.dsh/hooks.json"
  PATCH="$HOME/.dsh/cordis.patch.yml"
  if ! grep -q 'hooks-claude-code' "$PATCH" 2>/dev/null; then
    [ -s "$PATCH" ] || echo "# Home-level dsh patch layer, applied after every profile layer." > "$PATCH"
    printf -- "- insert:\n    - id: hooks-claude-code\n      name: '@deepseek-ai/dsh-hooks-claude-code'\n      config:\n        configPath: %s\n" "$HOME/.dsh/hooks.json" >> "$PATCH"
  fi
  link_skills "$HOME/.dsh/skills"
  say "AGENTS.md, hook bridge, skills"
fi

echo "Done. Restart open sessions to pick it up."
