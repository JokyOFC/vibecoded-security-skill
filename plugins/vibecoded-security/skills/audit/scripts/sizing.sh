#!/usr/bin/env bash
# vibecoded-security — project sizing and stack detection (read-only).
# Usage: sizing.sh [project-dir]
# Prints a Markdown summary (pt-BR) followed by KEY=VALUE lines used by the
# scoping phase. Portable: bash 3.2+ (macOS), GNU or BSD grep/awk/sed, git optional.
set -u

ROOT="${1:-.}"
cd "$ROOT" || { echo "não foi possível acessar $ROOT" >&2; exit 1; }

EXCLUDE='(^|/)(node_modules|vendor|dist|build|out|coverage|Pods|DerivedData|\.next|\.nuxt|\.expo|\.turbo|\.vercel|\.git|security-audit|__pycache__|\.venv|venv|\.dart_tool)/|\.min\.(js|css)$|\.map$|(^|/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|bun\.lockb|Podfile\.lock|poetry\.lock|Gemfile\.lock|composer\.lock|Cargo\.lock)$'

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  FILES=$(git ls-files -co --exclude-standard 2>/dev/null | grep -Ev "$EXCLUDE")
  SOURCE="git (rastreados + não rastreados não ignorados)"
else
  FILES=$(find . -type f 2>/dev/null | sed 's|^\./||' | grep -Ev "$EXCLUDE")
  SOURCE="find (sem git)"
fi

# --- helpers ---------------------------------------------------------------
sel()        { printf '%s\n' "$FILES" | grep -E "$1"; }                  # files whose path matches ERE
count_files(){ sel "$1" | grep -c . ; }
# lines matching content ERE across files selected by path ERE; $3 = extra grep flags
count_hits() { sel "$1" | tr '\n' '\0' | xargs -0 grep -hE ${3:-} -e "$2" /dev/null 2>/dev/null | grep -c . ; }
# files (paths) whose content matches
hit_list()   { sel "$1" | tr '\n' '\0' | xargs -0 grep -lE ${3:-} -e "$2" /dev/null 2>/dev/null; }
loc_of()     { tr '\n' '\0' | xargs -0 cat -- /dev/null 2>/dev/null | wc -l | tr -d ' '; }
has_dep()    { printf '%s\n' "$MANIFESTS" | tr '\n' '\0' | xargs -0 grep -lE -e "$1" /dev/null 2>/dev/null | grep -q . ; }

CODE_RE='\.(ts|tsx|js|jsx|mjs|cjs|py|swift|kt|kts|java|go|rb|php|dart|cs|rs|vue|svelte|scala|ex|exs)$'
TEST_RE='(^|/)(__tests__|tests?|spec|specs|e2e|cypress|playwright)/|\.(test|spec)\.[A-Za-z]+$|_test\.(go|py)$|(^|/)test_[^/]*\.py$'

TOTAL_FILES=$(printf '%s\n' "$FILES" | grep -c .)
APP_LOC=$(sel "$CODE_RE" | grep -Ev "$TEST_RE" | loc_of)
TEST_LOC=$(sel "$CODE_RE" | grep -E "$TEST_RE" | loc_of)
SQL_LOC=$(sel '\.sql$' | loc_of)

# Manifests (package.json, python) for dependency detection
MANIFESTS=$(sel '(^|/)(package\.json|requirements[^/]*\.txt|pyproject\.toml|Pipfile|pubspec\.yaml|Podfile|build\.gradle(\.kts)?)$')

# --- entry points ----------------------------------------------------------
ROUTE_FILE_RE='(^|/)app/(.*/)?route\.(ts|tsx|js|jsx|mjs)$'
EP_NEXT_ROUTE_FILES=$(count_files "$ROUTE_FILE_RE")
# each exported HTTP method in a route file is its own endpoint
EP_NEXT_ROUTE=$(count_hits "$ROUTE_FILE_RE" 'export[[:space:]]+(async[[:space:]]+)?function[[:space:]]+(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)|export[[:space:]]+const[[:space:]]+(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)[[:space:]]*=|export[[:space:]]*\{[^}]*(GET|POST|PUT|PATCH|DELETE)')
[ "$EP_NEXT_ROUTE" -lt "$EP_NEXT_ROUTE_FILES" ] && EP_NEXT_ROUTE=$EP_NEXT_ROUTE_FILES
EP_NEXT_PAGES_API=$(count_files '(^|/)pages/api/.*\.(ts|tsx|js|jsx|mjs)$')
SERVER_ACTION_FILES=$(hit_list "$CODE_RE" "['\"]use server['\"]")
EP_SERVER_ACTION_FILES=$(printf '%s\n' "$SERVER_ACTION_FILES" | grep -c .)
if [ "$EP_SERVER_ACTION_FILES" -gt 0 ]; then
  EP_SERVER_ACTIONS=$(printf '%s\n' "$SERVER_ACTION_FILES" | tr '\n' '\0' | xargs -0 grep -hE -e 'export[[:space:]]+(default[[:space:]]+)?async[[:space:]]+function|export[[:space:]]+const[[:space:]]+[A-Za-z0-9_]+[[:space:]]*=[[:space:]]*async' /dev/null 2>/dev/null | grep -c .)
else
  EP_SERVER_ACTIONS=0
fi
EP_NODE_ROUTES=$(count_hits '\.(ts|js|mjs|cjs)$' "(app|router|server|api|fastify|routes?|r)\.(get|post|put|patch|delete|all|route)\([[:space:]]*['\"\`]/")
EP_NEST=$(count_hits '\.ts$' '@(Get|Post|Put|Patch|Delete|All)\(')
EP_PY_ROUTES=$(count_hits '\.py$' '@[A-Za-z_][A-Za-z0-9_]*\.(get|post|put|patch|delete|route|api_route)\(')
EP_DJANGO=$(count_hits '(^|/)urls\.py$' '(^|[^A-Za-z_])(re_)?path\(')
EP_EDGE_FN=$(count_files '^supabase/functions/[^/_][^/]*/index\.(ts|js)$')
EP_TOTAL=$((EP_NEXT_ROUTE + EP_NEXT_PAGES_API + EP_SERVER_ACTIONS + EP_NODE_ROUTES + EP_NEST + EP_PY_ROUTES + EP_DJANGO + EP_EDGE_FN))

# --- database objects in migrations -----------------------------------------
DB_TABLES=$(count_hits '\.sql$' 'create[[:space:]]+table' -i)
DB_POLICIES=$(count_hits '\.sql$' 'create[[:space:]]+policy' -i)
DB_RLS_ON=$(count_hits '\.sql$' 'enable[[:space:]]+row[[:space:]]+level[[:space:]]+security' -i)
DB_RLS_OFF=$(count_hits '\.sql$' 'disable[[:space:]]+row[[:space:]]+level[[:space:]]+security' -i)
DB_DEFINER=$(count_hits '\.sql$' 'security[[:space:]]+definer' -i)
DB_VIEWS=$(count_hits '\.sql$' 'create[[:space:]]+(or[[:space:]]+replace[[:space:]]+)?(materialized[[:space:]]+)?view' -i)
PRISMA_MODELS=$(count_hits '\.prisma$' '^model[[:space:]]')

# --- automations (n8n) -------------------------------------------------------
N8N_FILES=$(hit_list '\.json$' '"n8n-nodes-|"@n8n/n8n-nodes-')
N8N_WORKFLOWS=$(printf '%s\n' "$N8N_FILES" | grep -c .)
if [ "$N8N_WORKFLOWS" -gt 0 ]; then
  N8N_WEBHOOKS=$(printf '%s\n' "$N8N_FILES" | tr '\n' '\0' | xargs -0 grep -hoE -e 'n8n-nodes-base\.(webhook|formTrigger)' /dev/null 2>/dev/null | grep -c .)
  N8N_AI=$(printf '%s\n' "$N8N_FILES" | tr '\n' '\0' | xargs -0 grep -hoE -e '@n8n/n8n-nodes-langchain\.[A-Za-z]+' /dev/null 2>/dev/null | grep -c .)
  N8N_CHAT=$(printf '%s\n' "$N8N_FILES" | tr '\n' '\0' | xargs -0 grep -hoE -e 'chatTrigger' /dev/null 2>/dev/null | grep -c .)
  N8N_CODE=$(printf '%s\n' "$N8N_FILES" | tr '\n' '\0' | xargs -0 grep -hoE -e 'n8n-nodes-base\.(code|executeCommand|function)"' /dev/null 2>/dev/null | grep -c .)
else
  N8N_WEBHOOKS=0; N8N_AI=0; N8N_CHAT=0; N8N_CODE=0
fi

# --- stack detection ---------------------------------------------------------
STACK=""
add_stack() { STACK="${STACK}${STACK:+, }$1"; }
has_dep '"next"[[:space:]]*:'                 && add_stack "Next.js"
has_dep '"react"[[:space:]]*:'                && add_stack "React"
has_dep '"expo"[[:space:]]*:'                 && add_stack "Expo"
has_dep '"react-native"[[:space:]]*:'         && add_stack "React Native"
has_dep '"@supabase/supabase-js"'             && add_stack "Supabase JS"
has_dep '"@prisma/client"|"prisma"[[:space:]]*:' && add_stack "Prisma"
has_dep '"drizzle-orm"'                       && add_stack "Drizzle"
has_dep '"express"[[:space:]]*:'              && add_stack "Express"
has_dep '"fastify"[[:space:]]*:'              && add_stack "Fastify"
has_dep '"@nestjs/core"'                      && add_stack "NestJS"
has_dep '"hono"[[:space:]]*:'                 && add_stack "Hono"
has_dep '"firebase"|"firebase-admin"'         && add_stack "Firebase"
has_dep '"stripe"[[:space:]]*:'               && add_stack "Stripe"
has_dep '(^|[^a-z])(fastapi)([^a-z]|$)'        && add_stack "FastAPI"
has_dep '(^|[^a-z])(django)([^a-z]|$)'         && add_stack "Django"
has_dep '(^|[^a-z])(flask)([^a-z]|$)'          && add_stack "Flask"
[ -n "$(sel '\.swift$' | head -1)" ]           && add_stack "Swift"
[ -n "$(sel '\.(kt|kts)$' | head -1)" ]        && add_stack "Kotlin"
[ -n "$(sel 'pubspec\.yaml$' | head -1)" ]     && add_stack "Flutter"
[ "$N8N_WORKFLOWS" -gt 0 ]                     && add_stack "n8n ($N8N_WORKFLOWS workflows)"

SUPABASE=no
{ has_dep '"@supabase/supabase-js"' || [ -n "$(sel '^supabase/(config\.toml|migrations/)' | head -1)" ]; } && SUPABASE=yes

MOBILE=no
{ has_dep '"expo"[[:space:]]*:|"react-native"[[:space:]]*:' || [ -n "$(sel '(^|/)(ios|android)/|\.swift$|\.(kt|kts)$|pubspec\.yaml$' | head -1)" ]; } && MOBILE=yes

# --- AI / LLM detection --------------------------------------------------------
AI_DEPS=""
add_ai() { AI_DEPS="${AI_DEPS}${AI_DEPS:+, }$1"; }
has_dep '"openai"[[:space:]]*:|(^|[^a-z_-])openai([^a-z_-]|$)'      && add_ai "openai"
has_dep '"@anthropic-ai/sdk"|(^|[^a-z_-])anthropic([^a-z_-]|$)'     && add_ai "anthropic"
has_dep '"ai"[[:space:]]*:|"@ai-sdk/'                                && add_ai "Vercel AI SDK"
has_dep '"langchain"|"@langchain/|(^|[^a-z_-])langchain'            && add_ai "LangChain"
has_dep '"llamaindex"|llama[-_]index'                                && add_ai "LlamaIndex"
has_dep '"@modelcontextprotocol/sdk"|(^|[^a-z_-])mcp([^a-z_-]|$)'   && add_ai "MCP SDK"
has_dep '"@google/genai"|"@google/generative-ai"|google-genai'      && add_ai "Google Gemini"
has_dep '"groq-sdk"|"@mistralai/|"cohere-ai"|"ollama"|"openrouter'  && add_ai "outros provedores"
has_dep 'crewai|autogen|pydantic[-_]ai|"@openai/agents"'            && add_ai "framework de agentes"
has_dep '"@pinecone-database/|"@qdrant/|"chromadb"|"weaviate'       && add_ai "vector store"
AI_CODE=$(count_hits "$CODE_RE" 'chat\.completions|responses\.create|messages\.create|generateText|streamText|generateObject|ChatOpenAI|ChatAnthropic|createReactAgent|AgentExecutor|tool_choice|McpServer|dangerouslyAllowBrowser')
AI_VECTOR=$(count_hits '\.sql$' 'create[[:space:]]+extension[[:space:]]+(if[[:space:]]+not[[:space:]]+exists[[:space:]]+)?"?vector' -i)
AI=no
{ [ -n "$AI_DEPS" ] || [ "$AI_CODE" -gt 0 ] || [ "$N8N_AI" -gt 0 ] || [ "$AI_VECTOR" -gt 0 ]; } && AI=yes

# --- infra -------------------------------------------------------------------
INF_DOCKER=$(count_files '(^|/)Dockerfile[^/]*$')
INF_COMPOSE=$(count_files '(^|/)(docker-)?compose[^/]*\.ya?ml$')
INF_GHA=$(count_files '^\.github/workflows/.*\.ya?ml$')
INF_PM2=$(count_files '(^|/)ecosystem\.config\.[a-z]+$')
INF_NGINX=$(count_hits '\.conf$' 'server_name')
INF_SYSTEMD=$(count_files '\.service$')
INF_TF=$(count_files '\.tf$')
INF_PAAS=$(count_files '(^|/)(vercel\.json|netlify\.toml|fly\.toml|render\.yaml|railway\.json)$')
SELF_HOSTED=no
[ $((INF_DOCKER + INF_COMPOSE + INF_PM2 + INF_NGINX + INF_SYSTEMD + INF_TF)) -gt 0 ] && SELF_HOSTED=yes
AUTOMATIONS=no
[ "$N8N_WORKFLOWS" -gt 0 ] && AUTOMATIONS=yes

# --- classification ------------------------------------------------------------
class_loc() {
  if   [ "$1" -lt 5000 ];   then echo 0
  elif [ "$1" -lt 20000 ];  then echo 1
  elif [ "$1" -lt 80000 ];  then echo 2
  elif [ "$1" -lt 250000 ]; then echo 3
  else echo 4; fi
}
class_ep() {
  if   [ "$1" -lt 15 ];  then echo 0
  elif [ "$1" -lt 50 ];  then echo 1
  elif [ "$1" -lt 150 ]; then echo 2
  elif [ "$1" -lt 400 ]; then echo 3
  else echo 4; fi
}
C1=$(class_loc "$APP_LOC"); C2=$(class_ep "$EP_TOTAL")
C=$C1; [ "$C2" -gt "$C" ] && C=$C2
case $C in 0) SIZE=XS;; 1) SIZE=S;; 2) SIZE=M;; 3) SIZE=L;; *) SIZE=XL;; esac

if [ "$TEST_LOC" -eq 0 ]; then TEST_RATIO=none
else TEST_RATIO=$(awk -v t="$TEST_LOC" -v a="$APP_LOC" 'BEGIN{ if (a==0) {print "ok"} else if (t/a < 0.10) {print "low"} else {print "ok"} }'); fi

lang_loc() { sel "$1" | grep -Ev "$TEST_RE" | loc_of; }

# --- output --------------------------------------------------------------------
cat <<EOF
# Dimensionamento do projeto

Fonte da lista de arquivos: $SOURCE · arquivos considerados: $TOTAL_FILES (exclui dependências, builds, lockfiles e minificados)

## Tamanho
| Medida | Valor |
|---|---|
| Código de aplicação (linhas, sem testes) | $APP_LOC |
| Código de teste (linhas) | $TEST_LOC |
| SQL (linhas) | $SQL_LOC |
| Pontos de entrada estimados | $EP_TOTAL |
| **Classe de tamanho** | **$SIZE** |

## Linhas por linguagem (sem testes)
| Linguagem | Linhas |
|---|---|
| TypeScript | $(lang_loc '\.(ts|tsx)$') |
| JavaScript | $(lang_loc '\.(js|jsx|mjs|cjs)$') |
| Python | $(lang_loc '\.py$') |
| Swift | $(lang_loc '\.swift$') |
| Kotlin/Java | $(lang_loc '\.(kt|kts|java)$') |
| Dart | $(lang_loc '\.dart$') |
| Outras (go, rb, php, cs, rs, vue, svelte...) | $(lang_loc '\.(go|rb|php|cs|rs|vue|svelte|scala|ex|exs)$') |

## Pontos de entrada
| Tipo | Quantidade |
|---|---|
| Next.js route handlers (métodos exportados em $EP_NEXT_ROUTE_FILES arquivos app/**/route.*) | $EP_NEXT_ROUTE |
| Next.js API routes (pages/api) | $EP_NEXT_PAGES_API |
| Server actions (funções exportadas em $EP_SERVER_ACTION_FILES arquivos "use server") | $EP_SERVER_ACTIONS |
| Rotas Node (express/fastify/hono...) | $EP_NODE_ROUTES |
| Controllers NestJS | $EP_NEST |
| Rotas Python (FastAPI/Flask) | $EP_PY_ROUTES |
| Rotas Django (urls.py) | $EP_DJANGO |
| Supabase Edge Functions | $EP_EDGE_FN |

## Banco de dados (migrations)
| Objeto | Ocorrências |
|---|---|
| create table | $DB_TABLES |
| create policy | $DB_POLICIES |
| enable row level security | $DB_RLS_ON |
| disable row level security | $DB_RLS_OFF |
| security definer | $DB_DEFINER |
| views | $DB_VIEWS |
| modelos Prisma | $PRISMA_MODELS |

## Automações
| Item | Quantidade |
|---|---|
| Workflows n8n versionados | $N8N_WORKFLOWS |
| Nós webhook/form | $N8N_WEBHOOKS |
| Nós de IA (langchain) | $N8N_AI |
| Chat triggers | $N8N_CHAT |
| Nós de código/comando | $N8N_CODE |

## Stack detectada
${STACK:-nenhuma identificada automaticamente}

## IA / LLM
- Dependências: ${AI_DEPS:-nenhuma}
- Chamadas/sinais no código: $AI_CODE
- Extensão vector no banco: $AI_VECTOR

## Infraestrutura
| Item | Quantidade |
|---|---|
| Dockerfiles | $INF_DOCKER |
| docker compose | $INF_COMPOSE |
| GitHub Actions workflows | $INF_GHA |
| PM2 ecosystem | $INF_PM2 |
| configs nginx | $INF_NGINX |
| units systemd | $INF_SYSTEMD |
| Terraform | $INF_TF |
| PaaS (Vercel/Netlify/Fly/Render/Railway) | $INF_PAAS |

> Contagens são heurísticas para estimar esforço, não um inventário de segurança. O inventário real é feito na Fase 0.

SIZE_CLASS=$SIZE
APP_LOC=$APP_LOC
ENTRY_POINTS=$EP_TOTAL
AI_DETECTED=$AI
MOBILE_DETECTED=$MOBILE
SUPABASE_DETECTED=$SUPABASE
SELF_HOSTED_INFRA=$SELF_HOSTED
AUTOMATIONS_DETECTED=$AUTOMATIONS
TEST_RATIO=$TEST_RATIO
EOF
