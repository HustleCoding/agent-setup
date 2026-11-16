#!/bin/bash
# Installs this setup into every agent harness found on the machine.
# Safe to re-run: it converges to the same state (run it again after `git pull`).
# Harnesses: Claude Code (~/.claude), Codex (~/.codex), DeepSeek Harness (~/.dsh).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP="$HOME/.agent-setup-backup/$(date +%Y%m%d-%H%M%S)"
BEGIN="<!-- agent-setup:begin (managed by $REPO/install.sh, edit the repo not this block) -->"
END="<!-- agent-setup:end -->"

say() { printf '  %s\n' "$*"; }
has() { [ -d "$HOME/$1" ] || command -v "$2" >/dev/null 2>&1; }
command -v python3 >/dev/null || { echo "install.sh needs python3 on PATH" >&2; exit 1; }
HOOK="$(python3 -I -c 'import shlex, sys; print("bash " + shlex.quote(sys.argv[1]))' "$REPO/hooks/style-reminder.sh")"

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
import sys, os, json, shlex
path, cmd, style = sys.argv[1:4]
data = json.load(open(path)) if os.path.exists(path) and open(path).read().strip() else {}
hooks = data.setdefault("hooks", {})
def is_our_hook(hook):
    if hook.get("type") != "command":
        return False
    command = hook.get("command", "")
    try:
        parts = shlex.split(command)
    except ValueError:
        # Older installs did not escape apostrophes in the repository path.
        return command.startswith("bash '") and command.endswith("/hooks/style-reminder.sh'")
    return (len(parts) == 2 and os.path.basename(parts[0]) == "bash"
            and parts[1].endswith("/hooks/style-reminder.sh"))
groups = []
for group in hooks.get("UserPromptSubmit", []):
    old = group.get("hooks", [])
    kept = [hook for hook in old if not is_our_hook(hook)]
    if len(kept) == len(old):
        groups.append(group)
    elif kept:
        groups.append({**group, "hooks": kept})
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
path = sys.argv[1]
original = open(path).read()
lines = original.splitlines(keepends=True)
try:
    import tomllib
except ImportError:
    tomllib = None
if tomllib:
    try:
        tomllib.loads(original)
    except tomllib.TOMLDecodeError as exc:
        sys.exit(f"Cannot update invalid TOML in {path}: {exc}")
values = {"model_verbosity": '"low"', "personality": '"none"'}
found = set()
section = None
features_header = None
hooks_found = False
multiline = None

def next_multiline(line, multiline):
    quote = None
    i = 0
    while i < len(line):
        if multiline:
            if multiline == '"""' and line[i] == "\\":
                i += 2
            elif line.startswith(multiline, i):
                i += 3
                multiline = None
            else:
                i += 1
        elif quote:
            if quote == '"' and line[i] == "\\":
                i += 2
            elif line[i] == quote:
                quote = None
                i += 1
            else:
                i += 1
        elif line[i] == "#":
            break
        elif line.startswith(('"""', "'''"), i):
            multiline = line[i:i + 3]
            i += 3
        elif line[i] in ('"', "'"):
            quote = line[i]
            i += 1
        else:
            i += 1
    return multiline

for i, line in enumerate(lines):
    if multiline is None:
        header = re.match(r"^[ \t]*(\[\[?[^\n]+?\]\]?)[ \t]*(?:#.*)?$", line.rstrip("\r\n"))
        if header:
            section = header.group(1)
            if re.fullmatch(r"\[[ \t]*(?:features|\"features\"|'features')[ \t]*\]", section):
                section = "[features]"
                features_header = i
        else:
            if section is None and re.match(r"^[ \t]*(?:features|\"features\"|'features')[ \t]*(?:=|\.)", line):
                sys.exit(f"Cannot safely update inline or dotted features in {path}; use a [features] table")
            assignment = re.match(r"^([ \t]*)(model_verbosity|personality|hooks|\"(?:model_verbosity|personality|hooks)\"|'(?:model_verbosity|personality|hooks)')[ \t]*=", line)
            if assignment:
                indent, raw_key = assignment.groups()
                key = raw_key.strip("\"'")
                value = values.get(key) if section is None else ("true" if section == "[features]" and key == "hooks" else None)
                if value is not None:
                    if line[assignment.end():].lstrip().startswith(('"""', "'''")):
                        sys.exit(f"Cannot update multiline {key} in {path}; set it manually and retry")
                    lines[i] = f"{indent}{raw_key} = {value}\n"
                    if section is None:
                        found.add(key)
                    else:
                        hooks_found = True
    multiline = next_multiline(line, multiline)

if features_header is None:
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"
    lines.extend(["\n[features]\n", "hooks = true\n"])
elif not hooks_found:
    if not lines[features_header].endswith("\n"):
        lines[features_header] += "\n"
    lines.insert(features_header + 1, "hooks = true\n")
lines[:0] = [f"{key} = {value}\n" for key, value in values.items() if key not in found]
updated = "".join(lines)
if tomllib:
    try:
        parsed = tomllib.loads(updated)
        if any(parsed.get(key) != value.strip('"') for key, value in values.items()) or parsed.get("features", {}).get("hooks") is not True:
            sys.exit(f"Cannot safely update settings in {path}; check its table and key syntax")
    except (tomllib.TOMLDecodeError, AttributeError) as exc:
        sys.exit(f"Cannot safely update settings in {path}: {exc}")
open(path, "w").write(updated)
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
