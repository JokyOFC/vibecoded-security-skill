#!/usr/bin/env bash
# vibecoded-security — directed sweep for vibe-coded security patterns (read-only).
# Usage: vibe-patterns.sh [project-dir] [max-lines-per-check]
# Output: Markdown (pt-BR). Long tokens are redacted in every printed line.
# Portable: bash 3.2+, git (preferred) or grep, perl (for the Unicode check).
set -u

ROOT="${1:-.}"
MAX="${2:-40}"
cd "$ROOT" || { echo "não foi possível acessar $ROOT" >&2; exit 1; }

IN_GIT=no
git rev-parse --is-inside-work-tree >/dev/null 2>&1 && IN_GIT=yes

EXCL_PATH='(^|/)(node_modules|vendor|dist|build|out|coverage|Pods|\.next|\.expo|\.turbo|\.vercel|security-audit)/|\.min\.(js|css)$|\.map$|(^|/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|bun\.lockb|Podfile\.lock|poetry\.lock)$'
# Pattern checks skip prose (docs and agent rules mention these patterns on purpose)
# and this plugin's own files; gitleaks covers secrets in docs.
EXCL_DOCS='\.(md|mdc|mdx|txt|rst)$|(^|/)\.claude/(skills/(audit|scope|guardrails|ai-review)|hooks/vibecoded-secret-guard\.sh)|(^|/)vibe-patterns\.sh$'

# search ERE; $1 = flags (e.g. "-i"), $2 = pattern. Prints path:line:text
search() {
  if [ "$IN_GIT" = yes ]; then
    git grep -nIE $1 -e "$2" -- . 2>/dev/null
  else
    grep -rnIE $1 -e "$2" . 2>/dev/null | sed 's|^\./||'
  fi | grep -Ev "^[^:]*($EXCL_PATH)" | grep -Ev "^[^:]*($EXCL_DOCS):"
}

redact() {
  # 1) keep the type prefix of known key formats, drop the rest;
  # 2) redact long tokens that mix letters and digits (keys, JWT segments, hashes)
  #    but keep identifiers (no digits) and paths (only short segments between "/").
  if command -v perl >/dev/null 2>&1; then
    perl -pe 's/(sk-ant-|sk-|ghp_|github_pat_|xox[abprs]-|AKIA|sb_secret_|sk_live_|rk_live_|sk_test_|whsec_)[A-Za-z0-9_-]{6,}/$1\[REDACTED]/g;
              s{([A-Za-z0-9_+/=-]{28,})}{ my $t = $1; my $mx = 0; for my $s (split m{/}, $t) { $mx = length($s) if length($s) > $mx }
                my $secret = $mx >= 20 && $t =~ /\d/ && (
                     ($t =~ /[a-z]/ && $t =~ /[A-Z]/)
                  || ($t =~ /^[0-9a-fA-F]{32,}$/)
                  || ($t !~ /[_\/-]/ && $t =~ /[A-Za-z]/ && length($t) >= 32));
                $secret ? "[REDACTED]" : $t }ge;'
  else
    sed -E 's/(sk-|ghp_|github_pat_|xox[abprs]-|AKIA|sb_secret_|sk_live_|rk_live_|whsec_)[A-Za-z0-9_-]+/\1[REDACTED]/g; s/[A-Za-z0-9_+=-]{40,}/[REDACTED]/g'
  fi | cut -c1-220
}

TOTAL=0
report() {
  # $1 = title, $2 = why it matters, $3 = flags, $4 = pattern, [$5 = secondary filter ERE (case-insensitive)]
  local out n
  out=$(search "$3" "$4")
  if [ -n "${5:-}" ] && [ -n "$out" ]; then out=$(printf '%s\n' "$out" | grep -iE -e "$5"); fi
  n=$(printf '%s\n' "$out" | grep -c .)
  TOTAL=$((TOTAL + n))
  echo "## $1 — $n ocorrência(s)"
  echo
  echo "_$2_"
  echo
  if [ "$n" -gt 0 ]; then
    echo '```'
    printf '%s\n' "$out" | head -n "$MAX" | redact
    [ "$n" -gt "$MAX" ] && echo "... (+$((n - MAX)) linhas; rode novamente com limite maior ou delegue ao subagente)"
    echo '```'
    echo
  fi
}

report_files() {
  # like report, but lists files with counts
  local out n
  if [ "$IN_GIT" = yes ]; then out=$(git grep -cIE $2 -e "$3" -- . 2>/dev/null)
  else out=$(grep -rcIE $2 -e "$3" . 2>/dev/null | grep -v ':0$' | sed 's|^\./||'); fi
  out=$(printf '%s\n' "$out" | grep -Ev "^[^:]*($EXCL_PATH)" | grep -Ev "^[^:]*($EXCL_DOCS):" | grep .)
  n=$(printf '%s\n' "$out" | grep -c .)
  echo "## $1 — $n arquivo(s)"
  echo
  if [ "$n" -gt 0 ]; then echo '```'; printf '%s\n' "$out" | head -n "$MAX"; echo '```'; echo; fi
}

echo "# Varredura de padrões vibecodados"
echo
echo "Diretório: $(pwd) · fonte: $([ "$IN_GIT" = yes ] && echo 'git grep (arquivos rastreados)' || echo 'grep recursivo')"
echo "Tokens longos aparecem como [REDACTED]. Cada ocorrência é um ponto de partida para leitura, não um achado confirmado."
echo

report "Placeholders e afrouxamentos" "Lógica provisória que foi para produção ou controle desligado para 'destravar'." \
  "-i" 'todo|fixme|hack|xxx|placeholder|temporar|workaround|bypass|skip.?auth|for testing|disable.?(auth|security|rls|csrf)'

report "Segurança condicionada a ambiente" "Checagem de auth/permissão que muda com NODE_ENV/__DEV__/DEBUG." \
  "" 'NODE_ENV|__DEV__|DEBUG' 'auth|admin|secur|skip|bypass|allow|verify|permission|role|token|cors'

report "Chaves privilegiadas no código" "service_role, chaves secretas e privadas devem existir só no servidor e nunca hardcoded." \
  "-i" 'service_role|service_key|private_key|secret_key|sb_secret_'

report "Segredo em variável pública" "Prefixos públicos vão para o bundle do cliente: tudo ali é público." \
  "" '(NEXT_PUBLIC_|EXPO_PUBLIC_|VITE_|REACT_APP_|NUXT_PUBLIC_)[A-Za-z0-9_]*(SECRET|SERVICE|PRIVATE|ADMIN|PASSWORD)'

report "Literais com cara de segredo" "Confirme com gitleaks; valores reais devem ser rotacionados." \
  "" "sk-[A-Za-z0-9_-]{20,}|sk-ant-|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}|github_pat_|xox[abprs]-|-----BEGIN [A-Z ]*PRIVATE KEY-----|sb_secret_|(sk|rk)_live_[A-Za-z0-9]{10,}|whsec_[A-Za-z0-9]{10,}"

report "CORS aberto e TLS desligado" "Origem * com credenciais e verificação de certificado desligada." \
  "" "origin:[[:space:]]*['\"]\\*|Access-Control-Allow-Origin.*\\*|rejectUnauthorized:[[:space:]]*false|verify[[:space:]]*=[[:space:]]*False|NODE_TLS_REJECT_UNAUTHORIZED"

report "Sinks perigosos" "HTML/código/comando montado a partir de dados (inclusive saída de LLM)." \
  "" 'dangerouslySetInnerHTML|innerHTML[[:space:]]*=|eval\(|new Function\(|child_process|execSync|shell[[:space:]]*=[[:space:]]*True'

report "Banco: sinais de alerta" "RLS desligado, policy aberta, SECURITY DEFINER e Edge Function sem JWT." \
  "-i" 'disable[[:space:]]+row[[:space:]]+level[[:space:]]+security|verify_jwt[[:space:]]*=[[:space:]]*false|security[[:space:]]+definer|using[[:space:]]*\([[:space:]]*true[[:space:]]*\)|with[[:space:]]+check[[:space:]]*\([[:space:]]*true[[:space:]]*\)'

report "Autorização baseada em metadata editável" "user_metadata/raw_user_meta_data pode ser alterado pelo próprio usuário." \
  "" 'user_metadata|raw_user_meta_data'

report_files "Arquivos com \"use server\" (cada função exportada é um endpoint público)" "" "['\"]use server['\"]"

report_files "Escapes de tipo (revise os que estão em auth/permissão)" "" '@ts-ignore|@ts-expect-error|as any'

report "Testes de fachada" "Testes que não testam, pulados ou que passam sem nada." \
  "" 'expect\(true\)|\.skip\(|xit\(|xdescribe\(|passWithNoTests'

echo "# IA, chatbots e agentes"
echo

report "Chave de LLM no cliente" "dangerouslyAllowBrowser ou chave de provedor em variável pública expõe a chave e abre denial of wallet." \
  "" 'dangerouslyAllowBrowser|(NEXT_PUBLIC_|EXPO_PUBLIC_|VITE_|REACT_APP_)[A-Za-z0-9_]*(OPENAI|ANTHROPIC|GEMINI|GOOGLE_AI|GROQ|MISTRAL|COHERE|DEEPSEEK|OPENROUTER|LLM)'

report_files "Definições de ferramentas/agentes (inventário de IA)" "" 'tool_choice|tools:[[:space:]]*\[|function_call|createReactAgent|AgentExecutor|McpServer|@modelcontextprotocol|n8n-nodes-langchain|generateText|streamText|chat\.completions|messages\.create|responses\.create'

report "Entrada interpolada no prompt de sistema" "Texto do usuário dentro das instruções facilita prompt injection; envie como mensagem/dado delimitado." \
  "" "role:[[:space:]]*['\"]system['\"].*\\\$\\{|(system|systemPrompt|system_prompt|instructions)[[:space:]]*[:=][[:space:]]*\`[^\`]*\\\$\\{"

report "Saída de LLM usada como código/SQL/HTML" "Saída do modelo é entrada não confiável." \
  "" '(completion|response|output|result|answer|message)[A-Za-z0-9_.]*.*(eval\(|new Function\(|dangerouslySetInnerHTML|\$queryRawUnsafe|\.raw\(|exec\()'

report "Identidade vinda de argumentos de ferramenta" "Tool que recebe userId/tenantId do modelo permite agir em nome de outro usuário." \
  "" '(userId|user_id|tenantId|tenant_id|accountId|account_id)[[:space:]]*:[[:space:]]*(z\.|\{[[:space:]]*type)'

echo "# Caracteres invisíveis ou bidirecionais"
echo
echo "_Instruções ocultas em arquivos de regras de IA e código (Trojan Source / rules file backdoor). BOM no início de arquivo costuma ser inofensivo._"
echo
if command -v perl >/dev/null 2>&1; then
  if [ "$IN_GIT" = yes ]; then LIST_CMD="git grep -Il -e . -- ."; else LIST_CMD="grep -rIl -e . ."; fi
  UNI=$($LIST_CMD 2>/dev/null | grep -Ev "($EXCL_PATH)" | tr '\n' '\0' | \
    xargs -0 perl -CSD -ne 'if (/[\x{200B}-\x{200F}\x{202A}-\x{202E}\x{2060}-\x{2064}\x{FEFF}\x{E0000}-\x{E007F}]/) { print "$ARGV:$.\n" } close ARGV if eof' 2>/dev/null)
  n=$(printf '%s\n' "$UNI" | grep -c .)
  echo "Ocorrências: $n"
  [ "$n" -gt 0 ] && { echo '```'; printf '%s\n' "$UNI" | head -n "$MAX"; echo '```'; }
else
  echo "perl indisponível — verificação não executada (lacuna)."
fi
echo

echo "# Arqueologia do git"
echo
if [ "$IN_GIT" = yes ]; then
  if [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
    echo "**Clone raso: o histórico está incompleto. Peça um clone completo para esta etapa.**"
    echo
  fi
  echo "## Commits com mensagens suspeitas"
  echo '```'
  git log --all --oneline -i -E --grep='cors|rls|auth|bypass|disable|temp|workaround|hotfix|secret|token|key|security|hack' 2>/dev/null | head -n "$MAX"
  echo '```'
  echo
  echo "## Commits que adicionaram ou removeram padrões perigosos (busca sem diferenciar maiúsculas)"
  echo
  for s in 'DISABLE ROW LEVEL SECURITY' 'verify_jwt = false' 'rejectUnauthorized: false' "origin: '*'" 'origin: "*"' 'service_role' 'dangerouslyAllowBrowser' 'BEGIN PRIVATE KEY'; do
    hits=$(git log --all --oneline -i -S"$s" 2>/dev/null | head -n 15)
    [ -n "$hits" ] && { echo "### \`$s\`"; echo '```'; printf '%s\n' "$hits"; echo '```'; }
  done
  echo
  echo "## Arquivos de segredo que já estiveram no histórico"
  echo '```'
  git log --all --name-only --pretty=format: 2>/dev/null | grep -E '(^|/)\.env($|\.)|\.pem$|\.p12$|\.key$|id_rsa|service-account.*\.json$|credentials\.json$' | grep -Ev '\.(example|sample|template)$' | sort -u | head -n "$MAX"
  echo '```'
else
  echo "Não é um repositório git — etapa não executada (lacuna)."
fi
echo
echo "PATTERN_HITS=$TOTAL"
