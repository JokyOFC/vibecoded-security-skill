# Phase 2 — Deterministic tools → `security-audit/02-tools.md`

Tools run **before** manual reading, to steer it. Rules:
- Install tools only from official sources (official release, OS package manager, `pipx`, official container image) and **outside the project**: never change `package.json`, lockfiles or configs to run a scanner.
- Never run `npx <package>` without confirming the package name is the official one (slopsquatting applies to the auditor too).
- A tool that cannot be installed is an explicit gap in the report, not a skipped step.
- Save full outputs under `security-audit/02-tools/` and only a summary (counts by severity, top items) in `02-tools.md`.
- Every command below is read-only for the project.

## Bundled sweep (always)

```bash
bash <AUDIT_DIR>/scripts/vibe-patterns.sh . > security-audit/02-tools/vibe-patterns.md
```

Portable (bash 3.2+, git grep/grep, perl). It covers: placeholder and loosened-control patterns, security gated on `NODE_ENV`/`__DEV__`, privileged keys and public-prefixed secrets, CORS/TLS bypasses, dangerous sinks, Supabase/SQL red flags, `"use server"` files, type escapes, facade tests, AI-specific red flags (`dangerouslyAllowBrowser`, public LLM keys, tool definitions, MCP), secret-like literals (redacted in the output), invisible/bidirectional Unicode (hidden instructions in rules files and code) and git archaeology (commits that loosened controls or removed secrets, case-insensitive). Every line it prints has long tokens redacted.

## Secrets (always redacted)

```bash
gitleaks git --redact -v --log-opts="--all" .   # full history, all branches
gitleaks dir --redact -v .                       # current tree, including untracked files such as .env
# gitleaks older than 8.19: gitleaks detect --redact -v
```

If the clone is shallow (`git rev-parse --is-shallow-repository` prints `true`), history scans are incomplete: say so, or ask for a full clone.

## Dependencies and package existence

```bash
npm audit --audit-level=high        # or: pnpm audit / yarn npm audit / pip-audit
osv-scanner -r .                     # v2 syntax: osv-scanner scan source -r .
npm view <package> repository.url time.created maintainers   # each little-known direct dependency
```

A direct dependency created recently, with no repository, or whose name is one typo away from a popular package, is a `SUSPEITO` supply-chain finding.

## SAST

```bash
semgrep scan --config p/owasp-top-ten --config p/secrets \
  --config p/typescript --config p/nodejs --config p/react --config p/nextjs
```

Use only the rule packs for languages present (`p/python`, `p/kotlin`, `p/swift`…) and confirm each pack exists in the registry. Add the language security linter where available (`eslint-plugin-security`, `bandit`).

## Database (Postgres / Supabase) — read-only catalog queries

Run `<AUDIT_DIR>/scripts/rls-audit.sql` with a read-only role, against a local copy or, if the user allows, production (catalog reads only):

```bash
psql "<read-only connection string>" -f <AUDIT_DIR>/scripts/rls-audit.sql > security-audit/02-tools/rls-audit.txt
```

It lists: tables without RLS in exposed schemas, tables with RLS but no policy (deny-all: intentional or a broken process?), every policy for one-by-one review, views without `security_invoker` and materialized views (bypass RLS), `SECURITY DEFINER` functions in exposed schemas and their `search_path`, storage policies, and grants to `anon`/`authenticated`. In Supabase, complement with the dashboard Security Advisor. Never print the connection string.

## Containers and IaC

`trivy fs .` and `trivy config .` (Dockerfiles, compose files, Kubernetes, Terraform).

## Server (only with read-only access the user granted)

```bash
ss -tulpn                                                    # open ports and owners
sudo ufw status verbose                                      # or iptables/nft
sudo sshd -T | grep -Ei 'permitrootlogin|passwordauthentication|pubkeyauthentication'
ps -eo user,pid,cmd | grep -Ei 'node|pm2|n8n|nginx|postgres'  # app processes running as root?
ls -l <paths of .env files>                                  # permissions of secret files
getent passwd | awk -F: '$3>=1000 || $3==0'                  # human and root accounts (unknown users → rule 9)
for u in $(cut -d: -f1 /etc/passwd); do sudo crontab -l -u "$u" 2>/dev/null | sed "s/^/$u: /"; done
nginx -v; node -v; lsb_release -a
```

Unknown users, SSH keys, cron entries or processes trigger rule 9.

## Headers and TLS

`curl -sI https://<host>` (HSTS, CSP, CORS, cookie flags) per public host and tenant domain; `testssl.sh <host>` when available.

## Light DAST

Only against a staging environment that Phase 0 proved isolated from production: `zap-baseline.py -t <url>` (passive) or `nuclei -u <url>` with conservative templates. Never against production without written authorization.

## Mobile

Build the production bundle (e.g. `npx expo export` — the project's own CLI) and search it for keys, staging URLs and tokens (`grep`/`strings`); MobSF when available.

## AI features

Adversarial testing tools (promptfoo, garak, PyRIT, DeepTeam) are covered in `ai-agent-security.md`. They call paid model APIs: run them only in the M8 adversarial module, against staging, with a spend cap.

## Cross-check

Tools and manual reading cross-check each other: discard false positives with a written reason; a finding only manual reading found should become, when possible, a semgrep rule or a test so it turns into a deterministic check.
