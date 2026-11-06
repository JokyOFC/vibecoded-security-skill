#!/usr/bin/env bash
# vibecoded-security — environment targets (read-only).
# Lists env files, variable NAMES, the TYPE of each value and the HOST each URL
# points to. Never prints a value. Flags privileged values in public-prefixed
# variables and env files that are committed or not git-ignored.
# Usage: env-targets.sh [project-dir]     Portable: bash 3.2+, perl optional.
set -u

ROOT="${1:-.}"
cd "$ROOT" || { echo "não foi possível acessar $ROOT" >&2; exit 1; }

IN_GIT=no
git rev-parse --is-inside-work-tree >/dev/null 2>&1 && IN_GIT=yes

ENV_FILES=$(find . -type f \( -name '.env' -o -name '.env.*' -o -name '*.env' -o -name '.dev.vars' \) \
  -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/security-audit/*' 2>/dev/null | sed 's|^\./||' | sort)

PUBLIC_RE='^(NEXT_PUBLIC_|EXPO_PUBLIC_|VITE_|REACT_APP_|PUBLIC_|NUXT_PUBLIC_|GATSBY_)'
PRIV_NAME_RE='(SECRET|SERVICE_ROLE|SERVICE_KEY|PRIVATE|PASSWORD|PASSWD|ADMIN)'
REVIEW_NAME_RE='(TOKEN|_KEY$|APIKEY|API_KEY)'

jwt_role() {
  # prints the "role" claim of a JWT payload, or nothing
  command -v perl >/dev/null 2>&1 || return 0
  printf '%s' "$1" | cut -d. -f2 | perl -MMIME::Base64 -ne 'tr/-_/+\//; $_ .= "=" x ((4 - length($_) % 4) % 4); my $j = decode_base64($_); print $1 if $j =~ /"role"\s*:\s*"([^"]+)"/' 2>/dev/null
}

classify() {
  # $1 = raw value; echoes "type|host|secretish"
  local v="$1" t="" host="" secretish=no
  v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
  local url_re='^[A-Za-z][A-Za-z0-9+.-]*://'
  local jwt_re='^eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.'
  if [ -z "$v" ]; then t="vazio"
  elif [[ $v =~ $url_re ]]; then
    host=$(printf '%s' "$v" | sed -E 's#^([A-Za-z][A-Za-z0-9+.-]*)://([^@/]*@)?([^/?#]*).*#\1://\3#')
    t="url"
    case "$v" in *://*@*) t="url com credencial embutida"; secretish=yes;; esac
  elif [[ $v =~ $jwt_re ]]; then
    local role; role=$(jwt_role "$v")
    t="jwt${role:+ (role=$role)}"
    [ "$role" = "service_role" ] && secretish=yes
  else
    case "$v" in
      sb_secret_*)        t="chave secreta Supabase"; secretish=yes;;
      sb_publishable_*)   t="chave publicável Supabase";;
      sk_live_*|rk_live_*) t="chave secreta Stripe (produção)"; secretish=yes;;
      sk_test_*|rk_test_*) t="chave secreta Stripe (teste)"; secretish=yes;;
      pk_live_*|pk_test_*) t="chave publicável Stripe";;
      whsec_*)            t="segredo de webhook"; secretish=yes;;
      sk-ant-*)           t="chave Anthropic"; secretish=yes;;
      sk-*)               t="chave estilo OpenAI (sk-)"; secretish=yes;;
      AKIA*)              t="chave AWS"; secretish=yes;;
      ghp_*|github_pat_*) t="token GitHub"; secretish=yes;;
      xox?-*)             t="token Slack"; secretish=yes;;
      AIza*)              t="chave Google API";;
      -----BEGIN*)        t="chave privada"; secretish=yes;;
      true|false|TRUE|FALSE|0|1|yes|no) t="flag";;
      *)
        if printf '%s' "$v" | grep -Eq '^[0-9]+$'; then t="número"
        else t="texto (${#v} caracteres)"; fi;;
    esac
  fi
  printf '%s|%s|%s' "$t" "$host" "$secretish"
}

is_local_host() {
  case "$1" in
    *://localhost*|*://127.*|*://0.0.0.0*|*://host.docker.internal*|*://*.local|*://*.local:*|*://10.*|*://192.168.*|*://172.1[6-9].*|*://172.2[0-9].*|*://172.3[01].*|*://\[::1\]*) return 0;;
  esac
  return 1
}

echo "# Alvos de ambiente"
echo
echo "Nenhum valor é exibido. URLs mostram apenas esquema e host. Arquivos analisados: $(printf '%s\n' "$ENV_FILES" | grep -c .)"
echo

ALERTS=0
REMOTE_HOSTS=""

if [ -z "$ENV_FILES" ]; then
  echo "Nenhum arquivo .env encontrado. Verifique variáveis definidas no painel de hospedagem, no CI, em ecosystem.config.* (PM2) e em docker compose."
fi

while IFS= read -r f <&3; do
  [ -z "$f" ] && continue
  status=""
  if [ "$IN_GIT" = yes ]; then
    if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
      case "$f" in
        *.example|*.sample|*.template|*.dist) status="versionado (arquivo de exemplo — confirme que não tem valores reais)";;
        *) status="**VERSIONADO NO GIT — tratar valores como comprometidos**"; ALERTS=$((ALERTS + 1));;
      esac
    elif git check-ignore -q "$f" 2>/dev/null; then
      status="ignorado pelo git"
    else
      status="**não ignorado pelo git (risco de commit acidental)**"; ALERTS=$((ALERTS + 1))
    fi
  fi
  echo "## $f"
  [ -n "$status" ] && echo "Situação: $status"
  echo
  echo "| Variável | Tipo do valor | Alvo | Alerta |"
  echo "|---|---|---|---|"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue;; esac
    line="${line#export }"
    name="${line%%=*}"
    [ "$name" = "$line" ] && continue
    name=$(printf '%s' "$name" | tr -d '[:space:]')
    printf '%s' "$name" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$' || continue
    value="${line#*=}"
    value=$(printf '%s' "$value" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+#.*$//; s/[[:space:]]+$//')
    res=$(classify "$value")
    vtype="${res%%|*}"; rest="${res#*|}"; host="${rest%%|*}"; secretish="${rest#*|}"
    alert=""
    if printf '%s' "$name" | grep -Eq "$PUBLIC_RE"; then
      if [ "$secretish" = yes ] || printf '%s' "$name" | grep -Eq "$PRIV_NAME_RE"; then
        alert="**CRÍTICO: valor privilegiado em variável pública (vai para o bundle do cliente)**"; ALERTS=$((ALERTS + 1))
      elif printf '%s' "$name" | grep -Eq "$REVIEW_NAME_RE"; then
        alert="revisar: pública — ok só se for chave pública/anon"
      fi
    fi
    target="—"
    if [ -n "$host" ]; then
      if is_local_host "$host"; then target="$host (local)"
      else
        target="$host (**remoto**)"
        case " $REMOTE_HOSTS " in *" $host "*) ;; *) REMOTE_HOSTS="$REMOTE_HOSTS $host";; esac
      fi
    fi
    echo "| \`$name\` | $vtype | $target | $alert |"
  done < "$f"
  echo
done 3<<EOF
$ENV_FILES
EOF

echo "## Resumo"
echo
echo "- Alertas: $ALERTS"
if [ -n "$REMOTE_HOSTS" ]; then
  echo "- Hosts remotos referenciados (confirme com o responsável quais são produção antes de executar testes, seeds, migrations ou o app):"
  for h in $REMOTE_HOSTS; do echo "  - $h"; done
else
  echo "- Nenhum host remoto encontrado em arquivos .env."
fi
echo
echo "ENV_ALERTS=$ALERTS"
echo "REMOTE_HOSTS=$(printf '%s' "$REMOTE_HOSTS" | sed 's/^ //')"
