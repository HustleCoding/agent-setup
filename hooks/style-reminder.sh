#!/bin/bash
# UserPromptSubmit hook, same JSON shape for Claude Code, Codex and dsh.
# Re-anchors the reply style every turn; standing rules alone fade over a long session.
echo '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"Reply per your global style rules: answer first, 1-3 lines, everyday words, details only when asked."}}'
