#!/usr/bin/env bash
# vibecoded-security — install/update/remove security guardrails in a project.
# Idempotent: managed blocks are delimited by markers and replaced on re-run;
# managed files carry a header and are overwritten; nothing else is touched.
# Portable: bash 3.2+ (macOS), awk, sed; jq or python3 only for --hook.
set -u

usage() {
  cat <<'EOF'
Usage: inject.sh [options] [project-dir]

Targets (none given = --auto):
  --claude-md     Upsert the core block into CLAUDE.md (or into AGENTS.md when the
                  project has AGENTS.md and no CLAUDE.md — creating CLAUDE.md there
                  would stop Claude Code from reading AGENTS.md)
  --agents-md     Upsert the core block into AGENTS.md (created if missing)
  --rules         Write path-scoped rules to .claude/rules/ (database + api;
                  ai with --ai; mobile with --mobile)
  --ai            Include the AI chatbot/agent rules
  --mobile        Include the mobile rules
  --cursor        Write .cursor/rules/vibecoded-security.mdc
  --copilot       Upsert the core block into .github/copilot-instructions.md
  --hook          Install the warn-only PostToolUse guard (.claude/hooks + .claude/settings.json)
  --gitignore     Add /security-audit/ to .gitignore
  --auto          claude-md + rules + gitignore, plus agents-md/cursor/copilot when
                  those files or folders already exist, plus ai/mobile when detected

Modes:
  --remove        Remove everything this script manages (selected targets, or all)
  --dry-run       Print what would change and change nothing
  -h, --help      Show this help
EOF
}

HERE="$(cd "$(dirname "$0")" && pwd)"
TPL="$HERE/../templates"
BEGIN_MARK='<!-- vibecoded-security:begin'
END_MARK='<!-- vibecoded-security:end -->'
HOOK_CMD='"$CLAUDE_PROJECT_DIR"/.claude/hooks/vibecoded-secret-guard.sh'

DO_CLAUDE=0 DO_AGENTS=0 DO_RULES=0 DO_AI=0 DO_MOBILE=0 DO_CURSOR=0 DO_COPILOT=0 DO_HOOK=0 DO_GITIGNORE=0
AUTO=0 REMOVE=0 DRY=0 ANY=0 ROOT="."

while [ $# -gt 0 ]; do
  case "$1" in
    --claude-md) DO_CLAUDE=1; ANY=1;;
    --agents-md) DO_AGENTS=1; ANY=1;;
    --rules)     DO_RULES=1; ANY=1;;
    --ai)        DO_AI=1;;
    --mobile)    DO_MOBILE=1;;
    --cursor)    DO_CURSOR=1; ANY=1;;
    --copilot)   DO_COPILOT=1; ANY=1;;
    --hook)      DO_HOOK=1; ANY=1;;
    --gitignore) DO_GITIGNORE=1; ANY=1;;
    --auto)      AUTO=1;;
    --remove)    REMOVE=1;;
    --dry-run)   DRY=1;;
    -h|--help)   usage; exit 0;;
    -*)          echo "unknown option: $1" >&2; usage >&2; exit 2;;
    *)           ROOT="$1";;
  esac
  shift
done

cd "$ROOT" || { echo "cannot cd to $ROOT" >&2; exit 1; }

say()  { if [ "$DRY" = 1 ]; then echo "[dry-run] $*"; else echo "$*"; fi; }
note() { echo "note: $*"; }

# ---------------------------------------------------------------- detection --
detect_ai() {
  find . -maxdepth 4 \( -name node_modules -o -name .git \) -prune -o \
    \( -name package.json -o -name 'requirements*.txt' -o -name pyproject.toml \) -print 2>/dev/null | \
    tr '\n' '\0' | xargs -0 grep -lE -e '"openai"|"@anthropic-ai/sdk"|"ai"[[:space:]]*:|"@ai-sdk/|langchain|llamaindex|llama[-_]index|"@modelcontextprotocol/sdk"|"@google/genai"|"@google/generative-ai"|(^|[^a-z_-])(openai|anthropic)([^a-z_-]|$)' /dev/null 2>/dev/null | grep -q . && return 0
  find . -maxdepth 4 -name '*.json' -not -path '*/node_modules/*' 2>/dev/null | head -n 500 | tr '\n' '\0' | \
    xargs -0 grep -l -e '@n8n/n8n-nodes-langchain' /dev/null 2>/dev/null | grep -q . && return 0
  [ -f .mcp.json ] && return 0
  return 1
}
detect_mobile() {
  { [ -d ios ] || [ -d android ] || [ -f eas.json ]; } && return 0
  [ -f app.json ] && grep -q '"expo"' app.json 2>/dev/null && return 0
  return 1
}

if [ "$ANY" = 0 ] || [ "$AUTO" = 1 ]; then
  if [ "$REMOVE" = 1 ] && [ "$ANY" = 0 ]; then
    DO_CLAUDE=1 DO_AGENTS=1 DO_RULES=1 DO_AI=1 DO_MOBILE=1 DO_CURSOR=1 DO_COPILOT=1 DO_HOOK=1 DO_GITIGNORE=1
  else
    DO_CLAUDE=1 DO_RULES=1 DO_GITIGNORE=1
    [ -f AGENTS.md ] && DO_AGENTS=1
    [ -d .cursor ] && DO_CURSOR=1
    [ -f .github/copilot-instructions.md ] && DO_COPILOT=1
    detect_ai && DO_AI=1
    detect_mobile && DO_MOBILE=1
  fi
fi

# ------------------------------------------------------------------ helpers --
upsert_block() {   # $1 = target file
  local f="$1" tmp
  if [ -f "$f" ] && grep -q "$BEGIN_MARK" "$f"; then
    tmp="$f.vcs-tmp.$$"
    awk -v bf="$TPL/core-block.md" -v b="$BEGIN_MARK" -v e="$END_MARK" '
      BEGIN { while ((getline line < bf) > 0) blk = blk line "\n"; close(bf) }
      index($0, b) == 1 { if (!done) { printf "%s", blk; done = 1 } skip = 1; next }
      index($0, e) == 1 { if (skip) { skip = 0; next } }
      !skip { print }
    ' "$f" > "$tmp"
    if cmp -s "$tmp" "$f"; then rm -f "$tmp"; say "unchanged: $f"; return; fi
    if [ "$DRY" = 1 ]; then rm -f "$tmp"; say "update block in $f"; return; fi
    mv "$tmp" "$f"; say "updated block in $f"
  else
    if [ "$DRY" = 1 ]; then say "append block to $f$( [ -f "$f" ] || echo ' (new file)')"; return; fi
    mkdir -p "$(dirname "$f")"
    if [ -s "$f" ]; then
      [ -n "$(tail -c 1 "$f")" ] && printf '\n' >> "$f"
      printf '\n' >> "$f"
    fi
    cat "$TPL/core-block.md" >> "$f"
    say "added block to $f"
  fi
}

remove_block() {   # $1 = target file
  local f="$1" tmp
  [ -f "$f" ] && grep -q "$BEGIN_MARK" "$f" || return 0
  if [ "$DRY" = 1 ]; then say "remove block from $f"; return; fi
  tmp="$f.vcs-tmp.$$"
  # blank lines are held back one step so the separator added before the block goes away with it
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    index($0, b) == 1 { pending = 0; skip = 1; next }
    index($0, e) == 1 { if (skip) { skip = 0; next } }
    skip { next }
    $0 == "" { if (pending) print ""; pending = 1; next }
    { if (pending) { print ""; pending = 0 } print }
    END { if (pending) print "" }
  ' "$f" > "$tmp" && mv "$tmp" "$f"
  say "removed block from $f"
}

write_owned() {    # $1 = template, $2 = destination
  if [ -f "$2" ] && cmp -s "$1" "$2"; then say "unchanged: $2"; return; fi
  if [ "$DRY" = 1 ]; then say "write $2"; return; fi
  mkdir -p "$(dirname "$2")"
  cp "$1" "$2"
  say "wrote $2"
}

remove_owned() {   # $1 = destination
  [ -f "$1" ] || return 0
  if [ "$DRY" = 1 ]; then say "delete $1"; return; fi
  rm -f "$1"; say "deleted $1"
}

claude_md_target() {
  if   [ -f CLAUDE.md ]; then echo CLAUDE.md
  elif [ -f .claude/CLAUDE.md ]; then echo .claude/CLAUDE.md
  elif [ -f AGENTS.md ]; then echo AGENTS.md
  else echo CLAUDE.md; fi
}

settings_edit() {  # $1 = add|remove ; edits .claude/settings.json
  local s=.claude/settings.json
  local tmp="$s.vcs-tmp.$$"
  if [ "$1" = remove ] && [ ! -f "$s" ]; then return 0; fi
  if [ "$DRY" = 1 ]; then say "$1 PostToolUse hook entry in $s"; return 0; fi
  mkdir -p .claude
  [ -f "$s" ] || echo '{}' > "$s"
  if command -v jq >/dev/null 2>&1; then
    jq --arg cmd "$HOOK_CMD" --arg mode "$1" '
      .hooks = (.hooks // {})
      | .hooks.PostToolUse = (
          ((.hooks.PostToolUse // [])
            | map(.hooks = ((.hooks // []) | map(select(.command != $cmd))))
            | map(select((.hooks | length) > 0)))
          + (if $mode == "add" then [{"matcher": "Write|Edit", "hooks": [{"type": "command", "command": $cmd}]}] else [] end))
      | if (.hooks.PostToolUse | length) == 0 then del(.hooks.PostToolUse) else . end
      | if (.hooks | length) == 0 then del(.hooks) else . end
    ' "$s" > "$tmp"
    if [ -s "$tmp" ]; then mv "$tmp" "$s"; else rm -f "$tmp"; echo "error: could not edit $s with jq" >&2; return 1; fi
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$s" "$HOOK_CMD" "$1" <<'PY' || { echo "error: could not edit settings with python3" >&2; return 1; }
import json, sys
path, cmd, mode = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as fh:
    data = json.load(fh)
hooks = data.setdefault("hooks", {})
groups = []
for g in hooks.get("PostToolUse", []):
    g["hooks"] = [h for h in g.get("hooks", []) if h.get("command") != cmd]
    if g["hooks"]:
        groups.append(g)
if mode == "add":
    groups.append({"matcher": "Write|Edit", "hooks": [{"type": "command", "command": cmd}]})
if groups:
    hooks["PostToolUse"] = groups
else:
    hooks.pop("PostToolUse", None)
if not hooks:
    data.pop("hooks", None)
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY
  else
    note "jq and python3 not found. Add this to .claude/settings.json manually:"
    echo '{ "hooks": { "PostToolUse": [ { "matcher": "Write|Edit", "hooks": [ { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/vibecoded-secret-guard.sh" } ] } ] } }'
    return 0
  fi
  if [ "$1" = add ]; then say "added PostToolUse hook entry in $s"; else say "removed PostToolUse hook entry from $s"; fi
}

gitignore_edit() { # $1 = add|remove
  local g=.gitignore tmp
  if [ "$1" = add ]; then
    if git ls-files security-audit 2>/dev/null | grep -q .; then
      note "the project already tracks files in security-audit/. Not ignoring it; choose another folder for audit artifacts."
      return 0
    fi
    if [ -f "$g" ] && grep -qxE '/?security-audit/?' "$g"; then say "unchanged: $g"; return; fi
    if [ "$DRY" = 1 ]; then say "add /security-audit/ to $g"; return; fi
    local needs_nl=0
    [ -s "$g" ] && [ -n "$(tail -c 1 "$g")" ] && needs_nl=1
    [ "$needs_nl" = 1 ] && printf '\n' >> "$g"
    printf '# vibecoded-security audit artifacts (may contain unfixed vulnerabilities)\n/security-audit/\n' >> "$g"
    say "added /security-audit/ to $g"
  else
    [ -f "$g" ] && grep -q '^/security-audit/$' "$g" || return 0
    if [ "$DRY" = 1 ]; then say "remove /security-audit/ from $g"; return; fi
    tmp="$g.vcs-tmp.$$"
    grep -vxE '/security-audit/|# vibecoded-security audit artifacts.*' "$g" > "$tmp"; mv "$tmp" "$g"
    say "removed /security-audit/ from $g"
  fi
}

# --------------------------------------------------------------------- run --
if [ "$REMOVE" = 1 ]; then
  [ "$DO_CLAUDE" = 1 ] && { remove_block CLAUDE.md; remove_block .claude/CLAUDE.md; }
  [ "$DO_AGENTS" = 1 ] || [ "$DO_CLAUDE" = 1 ] && remove_block AGENTS.md
  [ "$DO_COPILOT" = 1 ] && remove_block .github/copilot-instructions.md
  [ "$DO_RULES" = 1 ] && for r in database api ai mobile; do remove_owned ".claude/rules/vibecoded-security-$r.md"; done
  [ "$DO_CURSOR" = 1 ] && remove_owned .cursor/rules/vibecoded-security.mdc
  [ "$DO_HOOK" = 1 ] && { remove_owned .claude/hooks/vibecoded-secret-guard.sh; settings_edit remove; }
  [ "$DO_GITIGNORE" = 1 ] && gitignore_edit remove
  echo "done (remove)."
  exit 0
fi

if [ "$DO_CLAUDE" = 1 ]; then
  T=$(claude_md_target)
  if [ "$T" = AGENTS.md ]; then
    note "project has AGENTS.md and no CLAUDE.md: Claude Code reads AGENTS.md in that case, so the block goes there (creating CLAUDE.md would stop AGENTS.md from loading)."
    DO_AGENTS=1
  else
    upsert_block "$T"
  fi
fi
[ "$DO_AGENTS" = 1 ] && upsert_block AGENTS.md
[ "$DO_COPILOT" = 1 ] && upsert_block .github/copilot-instructions.md

if [ "$DO_RULES" = 1 ]; then
  write_owned "$TPL/rules/vibecoded-security-database.md" .claude/rules/vibecoded-security-database.md
  write_owned "$TPL/rules/vibecoded-security-api.md" .claude/rules/vibecoded-security-api.md
  [ "$DO_AI" = 1 ] && write_owned "$TPL/rules/vibecoded-security-ai.md" .claude/rules/vibecoded-security-ai.md
  [ "$DO_MOBILE" = 1 ] && write_owned "$TPL/rules/vibecoded-security-mobile.md" .claude/rules/vibecoded-security-mobile.md
fi

if [ "$DO_CURSOR" = 1 ]; then
  MDC_TMP="${TMPDIR:-/tmp}/vcs-cursor.$$"
  {
    printf -- '---\ndescription: Security guardrails for AI-generated code (vibecoded-security)\nglobs:\nalwaysApply: true\n---\n'
    sed -e '/^<!-- vibecoded-security:/d' "$TPL/core-block.md"
  } > "$MDC_TMP"
  write_owned "$MDC_TMP" .cursor/rules/vibecoded-security.mdc
  rm -f "$MDC_TMP"
fi

if [ "$DO_HOOK" = 1 ]; then
  write_owned "$TPL/hooks/vibecoded-secret-guard.sh" .claude/hooks/vibecoded-secret-guard.sh
  [ "$DRY" = 1 ] || chmod +x .claude/hooks/vibecoded-secret-guard.sh
  settings_edit add
fi

[ "$DO_GITIGNORE" = 1 ] && gitignore_edit add

echo "done."
