# Maintaining vibecoded-security

This repository is a Claude Code plugin marketplace with one plugin: `plugins/vibecoded-security`.

## Layout
- `.claude-plugin/marketplace.json` — marketplace; the plugin entry name must equal `plugins/vibecoded-security/.claude-plugin/plugin.json` `name`.
- `plugins/vibecoded-security/skills/audit/` — the orchestrator. `references/` holds one file per phase plus `ai-agent-security.md` and `scoping-and-estimation.md`; `scripts/` holds the read-only helpers.
- `skills/scope`, `skills/ai-review` — thin skills that reuse `../audit/references` and `../audit/scripts`. Keep the four skill folders side by side.
- `skills/guardrails/` — `scripts/inject.sh` and the `templates/` it installs into user projects.
- `agents/` — `security-sweeper` (cheap model, read-only breadth) and `security-verifier` (independent review).

## Conventions
- Prompt text (SKILL.md, references, agents, injected rules) is written in English. Everything shown to the end user — questions, plans, findings, reports, script output — is Brazilian Portuguese.
- `${CLAUDE_SKILL_DIR}` is substituted only inside SKILL.md. Reference files use the placeholder `<AUDIT_DIR>`, defined by each SKILL.md.
- Do not write `$1`, `$2` or `$name`-style tokens in SKILL.md bodies: Claude Code substitutes them with arguments.
- Keep each SKILL.md under 500 lines; move detail into references.
- Scripts must run on macOS bash 3.2 and BSD tools: no `declare -A`, `mapfile`, `${var,,}`, `grep -P`, `sed -i`, `stat -c` or `find -printf`. Never print secret values; redact long tokens.
- Injected content lives between `<!-- vibecoded-security:begin` and `<!-- vibecoded-security:end -->` markers or in files named `vibecoded-security*`; the installer must never touch anything else.

## Before committing
- `bash -n` every script and run them against a fixture project (sizing, env-targets, vibe-patterns, inject install → re-run unchanged → remove).
- `claude plugin validate .` and `claude plugin validate plugins/vibecoded-security`.
- Bump `version` in `plugin.json` for user-visible changes.
