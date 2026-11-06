#!/usr/bin/env bash
# vibecoded-security — PostToolUse guard for Write/Edit (warn-only, never blocks).
# Scans the file Claude just wrote for patterns AI-generated code commonly
# introduces (hardcoded secrets, privileged keys in public env vars, LLM keys in
# the browser, disabled TLS/RLS/JWT checks, open CORS) and feeds a warning back
# to Claude through additionalContext. Never prints secret values.
# Suppress a reviewed line by adding the comment: vibecoded-security:allow
# Managed by vibecoded-security; re-run /vibecoded-security:guardrails to update.
set -u

INPUT=$(cat)

if command -v jq >/dev/null 2>&1; then
  FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
else
  FILE=$(printf '%s' "$INPUT" | tr '\n' ' ' | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
fi

[ -n "$FILE" ] && [ -f "$FILE" ] || exit 0

case "$FILE" in
  */node_modules/*|*/.git/*|*/security-audit/*|*.lock|*package-lock.json|*.min.js|*.map) exit 0;;
  *.md|*.mdc|*.mdx|*.txt|*.rst) exit 0;;                       # prose mentions patterns on purpose
  */vibecoded-secret-guard.sh|*/vibe-patterns.sh) exit 0;;
esac

ISSUES=""
add() { ISSUES="${ISSUES}- $1"$'\n'; }

# grep helper: prints line numbers of matches, skipping allowlisted lines
lines() {
  grep -nE $1 -e "$2" "$FILE" 2>/dev/null | grep -v 'vibecoded-security:allow' | cut -d: -f1 | head -n 5 | tr '\n' ',' | sed 's/,$//'
}

PUBLIC_PRIV='(NEXT_PUBLIC_|EXPO_PUBLIC_|VITE_|REACT_APP_|NUXT_PUBLIC_)[A-Za-z0-9_]*(SECRET|SERVICE|PRIVATE|ADMIN|PASSWORD)'
PUBLIC_LLM='(NEXT_PUBLIC_|EXPO_PUBLIC_|VITE_|REACT_APP_)[A-Za-z0-9_]*(OPENAI|ANTHROPIC|GEMINI|GOOGLE_AI|GROQ|MISTRAL|COHERE|DEEPSEEK|OPENROUTER|LLM)'

base=$(basename "$FILE")
case "$base" in
  .env|.env.*|*.env|.dev.vars)
    if git -C "$(dirname "$FILE")" ls-files --error-unmatch "$base" >/dev/null 2>&1; then
      case "$base" in
        *.example|*.sample|*.template) ;;
        *) add "$FILE is tracked by git. Secret files must be git-ignored and their values treated as compromised.";;
      esac
    fi
    l=$(lines "" "^[[:space:]]*(export[[:space:]]+)?$PUBLIC_PRIV"); [ -n "$l" ] && add "line(s) $l: privileged value in a public-prefixed variable (it is bundled into the client)."
    l=$(lines "" "^[[:space:]]*(export[[:space:]]+)?$PUBLIC_LLM"); [ -n "$l" ] && add "line(s) $l: LLM provider key in a public-prefixed variable (exposes the key, enables denial of wallet)."
    ;;
  *)
    l=$(lines "" 'sk-[A-Za-z0-9_-]{20,}|sk-ant-[A-Za-z0-9_-]{10,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{20,}|xox[abprs]-[A-Za-z0-9-]{10,}|sb_secret_[A-Za-z0-9_-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----')
    [ -n "$l" ] && add "line(s) $l: looks like a hardcoded secret. Move it to a server-side env var or secret manager and rotate it."
    l=$(lines "" 'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}')
    [ -n "$l" ] && add "line(s) $l: hardcoded JWT. If it is a service_role key it bypasses RLS; never ship it in code."
    l=$(lines "" "$PUBLIC_PRIV"); [ -n "$l" ] && add "line(s) $l: privileged key read from a public-prefixed env var."
    l=$(lines "" "dangerouslyAllowBrowser|$PUBLIC_LLM"); [ -n "$l" ] && add "line(s) $l: LLM provider key used in the browser. Call the model from the server."
    l=$(lines "" 'rejectUnauthorized:[[:space:]]*false|NODE_TLS_REJECT_UNAUTHORIZED|verify[[:space:]]*=[[:space:]]*False'); [ -n "$l" ] && add "line(s) $l: TLS certificate verification disabled."
    l=$(lines "" "origin:[[:space:]]*['\"]\\*['\"]|Access-Control-Allow-Origin['\"]?[[:space:]]*[:,][[:space:]]*['\"]\\*"); [ -n "$l" ] && add "line(s) $l: CORS open to any origin. Never combine with credentials; prefer an explicit allowlist."
    l=$(lines "-i" 'disable[[:space:]]+row[[:space:]]+level[[:space:]]+security'); [ -n "$l" ] && add "line(s) $l: RLS disabled. Do not loosen database access control to get unblocked."
    l=$(lines "-i" 'using[[:space:]]*\([[:space:]]*true[[:space:]]*\)|with[[:space:]]+check[[:space:]]*\([[:space:]]*true[[:space:]]*\)'); [ -n "$l" ] && add "line(s) $l: policy open to every row (true). Scope it by auth.uid() or tenant."
    l=$(lines "-i" 'verify_jwt[[:space:]]*=[[:space:]]*false'); [ -n "$l" ] && add "line(s) $l: edge function without JWT verification. It needs its own authentication (e.g. webhook signature)."
    ;;
esac

[ -z "$ISSUES" ] && exit 0

MSG="vibecoded-security guard (warning, not a block) for ${FILE}:"$'\n'"${ISSUES}If a line is intentional and reviewed, explain why to the user and add the comment 'vibecoded-security:allow' to it. Never print secret values."

if command -v jq >/dev/null 2>&1; then
  jq -n --arg m "$MSG" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}'
else
  ESC=$(printf '%s' "$MSG" | awk 'BEGIN{ORS=""} { gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/\t/,"\\t"); if (NR>1) print "\\n"; print }')
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$ESC"
fi
exit 0
