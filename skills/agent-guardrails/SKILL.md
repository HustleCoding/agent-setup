---
name: agent-guardrails
description: Turn recurring coding-agent mistakes into project-specific guardrails and verifiable behavior. Use when asked to harden a repository for agents or prevent repeated corrections and regressions.
---

# Agent guardrails

Find concrete failure patterns in the repository, tests, instructions, and the user's feedback. Check which ones already have effective controls. Do not treat one correction as a universal rule or invent a failure just to add a check.

For the patterns in scope, prefer a change that makes the wrong behavior impossible or harder to express: a clearer API, a better boundary, a type, or a refactor. Otherwise use a narrow lint rule, test, or runtime check. Give failures an actionable message and preserve legitimate cases; prose is useful for judgment that cannot be encoded reliably. Avoid blanket bans borrowed from other projects.

Prevent new instances before cleaning up existing ones when practical. Add or update a regression check that exercises the real failure and a valid case, and show that it fails before the fix when feasible. Integrate it into the project's existing checks rather than adding an unused script.

Verify the affected behavior on its real surface when practical, using isolated data and the user's authorized scope. For user-facing flows, a small feature map or screenshots can make the evidence easier to review. Use model checking, property-based testing, or formal proofs when the risk and project justify them, not as a default dependency.

Report what changed, what evidence passed, and what could not be verified. Guardrails do not authorize deploying, merging, or taking other external actions on their own.
