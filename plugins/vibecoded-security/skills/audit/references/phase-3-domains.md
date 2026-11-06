# Phase 3 — Manual audit by domain → `security-audit/03-findings.md`

Reference frameworks (use the current edition of each): **OWASP Top 10:2025**, **OWASP ASVS 5.0**, **CWE Top 25**, **OWASP API Security Top 10**, **OWASP Cheat Sheet Series**, **NIST SSDF (SP 800-218) and SP 800-218A**, **OWASP Top 10 for LLM Applications 2026**, **OWASP Top 10 for Agentic Applications (ASI)** and **OWASP MCP Top 10**. Every finding maps to at least one ID (`A01:2025`, `CWE-862`, `LLM01:2026`, `ASI02`, `MCP07`…).

For every domain: verify, cite evidence and record the method in `coverage.md`; if it does not apply, write "N/A — reason". Start from the tool results and the public surface; then authenticated, admin and internal. Domains outside the approved plan are marked `fora do plano`, not silently skipped.

Delegate wide sweeps to the `security-sweeper` subagent (e.g. "list every route handler and whether it calls the auth guard"), then read the risky paths yourself.

## 3.1 Access control — A01:2025, CWE-862/863/639/918
- Every endpoint, server action, RPC and database function checks **authentication AND authorization** (role + resource ownership + tenant), as defined in `authz-matrix.md`.
- Client-supplied resource IDs are checked against the user/tenant (IDOR, CWE-639).
- Authorization based on data the user controls: role in the request body, unverified claims, Supabase `user_metadata` (editable by the user — authorization must use `app_metadata` or a dedicated table).
- Next.js: every Server Action and Route Handler is a public endpoint and must authenticate and authorize by itself, even if only called from a protected page. Middleware is not an authorization boundary (CVE-2025-29927 let attackers skip middleware with the `x-middleware-subrequest` header; confirm version ≥ 12.3.5 / 13.5.9 / 14.2.25 / 15.2.3).
- Too much data leaving the server: whole objects passed as props to client components, responses with internal fields.
- List, export, report and search endpoints filter by tenant on the server.
- Admin, debug, seed, migration and "reset" routes are protected or removed.
- Authorization centralized (middleware/policy) or repeated by hand? List **every** handler without a check.
- SSRF: any user- or integration-supplied URL the server fetches? Host allowlist, internal IP and metadata endpoint blocking?
- HTTP methods: what is protected on `POST` is also protected on `PUT/PATCH/DELETE/GET`.

## 3.2 Authentication and session — A07:2025, CWE-287/306/798
- Sign-in, sign-up, password recovery, email change, MFA, logout, revocation.
- Password hashing (bcrypt/argon2/scrypt with adequate cost), user enumeration, brute force and credential stuffing (rate limit + progressive lockout).
- Tokens: algorithm (`none`? `HS256` with a weak secret?), expiry, refresh, revocation, client storage (httpOnly cookie vs localStorage vs AsyncStorage).
- Cookies: `Secure`, `HttpOnly`, `SameSite`, domain scope in white-label/multi-domain setups.
- OAuth/OIDC: `state`, `nonce`, `redirect_uri` validation, `aud` and `iss`.
- Long sessions and shared devices: safe expiry/renewal that does not kick out legitimate use.
- Service accounts and integration API keys: least scope, rotation, never shared across environments.

## 3.3 Input validation and injection — A05:2025, CWE-79/89/78/77/22/434/94/1333
- SQL/NoSQL: concatenation, `raw`, `$queryRaw`, `rpc` with built strings, dynamic filters taken straight from the client.
- OS commands: `exec`, `spawn` with a shell, `child_process` with external input.
- XSS: `dangerouslySetInnerHTML`, `innerHTML`, user markdown/HTML, email templates, generated PDFs, **LLM output rendered as HTML/markdown**.
- Uploads and path traversal: sanitized names, extension **and** content validated, size limited, stored outside the webroot, served with correct `Content-Type` and `Content-Disposition`.
- Server-side schema validation (zod/yup/joi/pydantic) on **all** inputs, webhooks and headers included. Client-only validation does not count.
- Deserialization of external data (`eval`, `Function`, `vm`, YAML/XML with entities).
- ReDoS in regexes applied to user input.
- Mass assignment: request objects passed straight to `insert/update` without a field allowlist.

## 3.4 Cryptography and secrets — A04:2025, CWE-798/312/327/330
- Secrets hardcoded, in committed `.env`, in git history, logs, error messages, comments, infra configs, Docker images, client bundles.
- A privileged key in a public-prefixed variable (`NEXT_PUBLIC_`, `EXPO_PUBLIC_`, `VITE_`, `REACT_APP_`) is an exposed secret, even if "only used on the server".
- Privileged keys (service role, admin, LLM provider keys) only on the server — never in clients, public edge functions or exposed automations.
- Sensitive data at rest: passwords, third-party tokens, documents, health/biometric data.
- TLS on every connection, database, queues and internal services included. No `rejectUnauthorized: false`, no `verify=False`.
- Algorithms: no MD5/SHA1 for passwords, no ECB, no fixed key/IV, no `Math.random` for tokens.
- Rotation: is there a process? Which secrets were never rotated?

## 3.5 Configuration and hardening — A02:2025, CWE-16/209/489
- Debug mode, stack traces, verbose error pages, source maps in production.
- Headers: `Content-Security-Policy`, `Strict-Transport-Security`, `X-Content-Type-Options`, `frame-ancestors`/`X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy`.
- CORS: explicit origins (never `*` with credentials), minimal methods and headers, white-label domains and mobile apps considered.
- Framework defaults: listable directories, sample routes, default users, exposed admin ports.
- Real environment separation: different credentials, databases and buckets; staging does not point at production.
- File and process permissions on the server (`.env` readable by others? service running as root?).
- Firewall, SSH (keys only, no root), admin panels behind IP allowlist/VPN/MFA, proxy/runtime/OS versions, fail2ban or equivalent, tested backups.

## 3.6 Supply chain — A03:2025, CWE-1104/829/506
- No critical/high vulnerability in direct or transitive dependencies (Phase 2).
- Lockfile committed and respected in CI (`npm ci`, not `npm install`).
- Every dependency exists, is the official one and is maintained — watch "AI-suggested" packages one typo away from a popular name.
- Third-party `postinstall` scripts, binaries downloaded at build time, `curl | sh` in pipelines and Dockerfiles.
- CI: actions pinned by SHA or version, minimal `GITHUB_TOKEN` permissions, secrets not exposed to fork PRs.
- Base images, runtimes and OS up to date.
- AI development tooling: tokens in `.mcp.json` or MCP configs, broad permissions in `.claude/settings*.json` or equivalents, MCP servers of unknown origin, hidden instructions in rules files (Unicode sweep from Phase 2) — OWASP MCP Top 10 (MCP01, MCP04, MCP09).

## 3.7 Software and data integrity — A08:2025, CWE-345/502/494
- Incoming webhooks: HMAC signature verified with constant-time comparison, timestamp/anti-replay, idempotency by event ID.
- Providers that do not sign webhooks: long secret in path or header, source IP allowlist, schema validation and idempotency as compensating controls.
- Integration data treated as untrusted (validated, never executed).
- Auto-updates, downloads and build artifacts verified.
- Multi-step operations are atomic; aborting halfway cannot leave inconsistent state.
- Migrations reversible, reviewed, not auto-run with broad privileges in production.

## 3.8 Logging, monitoring and alerting — A09:2025, CWE-778/532/117
- Logged events: sign-in success/failure, permission changes, access denied, service-key use, admin actions, sensitive-data changes, AI tool calls.
- Logs **without** passwords, tokens, unnecessary personal data or full request bodies (and without full LLM conversations unless there is a retention policy).
- Log injection (newlines, control characters) neutralized.
- Correlation (request ID, user, tenant), defined retention, tamper protection.
- Alerts for attack patterns: 401/403 spikes, webhook signature failures, mass 500s, AI cost spikes.

## 3.9 Exception handling — A10:2025, CWE-755/754/209
- Errors leak internals (stack, query, path, version)?
- Authorization/validation failures fail open or fail closed?
- Empty `try/catch`, swallowed errors, `catch (e) { return [] }` hiding a security failure.
- Timeouts, retries and circuit breakers on external calls — can a slow integration take the system down?
- Race conditions on balance, stock, coupons, usage limits, approvals.

## 3.10 Secure design and business logic — A06:2025, ASVS "Validation and Business Logic"
- Can steps of multi-step flows be skipped, repeated or reordered?
- Price, discount, limits and permissions computed on the server or trusted from the client?
- Business limits (quantity, frequency, value) enforced on the server?
- Dangerous actions (bulk export, deletion, plan change) with confirmation, audit trail and, where appropriate, dual approval?
- Abuse of legitimate features: enumeration through "forgot password", list scraping, bulk email/SMS/WhatsApp through a form or chatbot.

## 3.11 APIs and webhooks — OWASP API Security Top 10
- BOLA/BFLA (API1/API5) also on internal and service-to-service APIs.
- Rate limits and quotas per user/tenant/IP/key (CWE-770), calibrated from the baseline.
- Mandatory pagination; no endpoint returns a whole table.
- Excessive data exposure: `select *`, whole-entity serialization, internal fields.
- Versioning: do contract changes break old mobile versions?
- **Outgoing** webhooks: destination URL validated, per-destination secret, retries with backoff, no extra data.

## 3.12 Database
- Results of `rls-audit.sql`: every table without RLS; every table with RLS and no policy; every policy reviewed. Red flags: `true` in `qual`/`with_check`; no `auth.uid()` or tenant filter; use of `user_metadata`; `SELECT` restricted but `INSERT/UPDATE/DELETE` open; `UPDATE` without `with_check` (lets a row move to another tenant).
- Views without `security_invoker = true` and exposed materialized views.
- `SECURITY DEFINER` in an exposed schema is callable through the API with the creator's privileges: must pin `search_path` and check permission inside.
- Service key / secret key: server only, in specific and justified paths.
- Storage: per-folder/per-tenant policies, public buckets only for truly public content, signed URLs with expiry.
- Realtime: `postgres_changes` follows RLS; broadcast/presence channels must be private and authorized per tenant/user.
- Edge Functions with `verify_jwt = false` need their own authentication (e.g. webhook signature).
- Application database user is not a superuser; TLS connections; encrypted, tested backups.
- Sensitive data masked or encrypted per column where appropriate.
- Vector stores (pgvector etc.): tenant filter enforced in the query or by RLS, never by the LLM.

## 3.13 Mobile (iOS / Android / Expo / React Native)
- Everything in the app is public: `EXPO_PUBLIC_*`, `extra` in `app.config`, `google-services`, third-party keys.
- Tokens in Keychain/Keystore (SecureStore), never in AsyncStorage/SharedPreferences as plain text.
- Transport: ATS and `cleartextTraffic` without broad exceptions; pinning for critical endpoints when the risk justifies it.
- Deep links / universal links: validated parameters, no access to protected screens without auth.
- `console.log` with user data, dev flags or staging endpoints in the production build.
- OTA updates (EAS Update, CodePush): code signing, correct channel, no downgrade.
- Health/biometric data (HealthKit, Health Connect, wearables): consent, minimization, send only what is needed.

## 3.14 Infra, deploy, automations and CI/CD — NIST SSDF
- Deploy reproducible from git; who can trigger it; production approval.
- CI secrets only through the secret store, never in build logs (watch `set -x`).
- PM2/systemd/Docker with a dedicated non-root user, restart policy and resource limits.
- Reverse proxy: current TLS, HSTS, body size limits, timeouts, unnecessary methods blocked.
- Automations (n8n and similar): version current against the project's advisories (in 2026 n8n had a critical unauthenticated RCE through public webhooks and forms — CVE-2026-21858, fixed in 1.121.0); webhooks and forms authenticated; code/command execution nodes disabled when unused; editor not publicly exposed without strong auth; credential encryption key set and outside the repo; AI agent nodes reviewed with the AI module.
- Availability and integrity monitoring; a minimal incident response plan (who does what, how to rotate everything).

## 3.15 Personal data and LGPD
- Inventory of personal and sensitive data (health, biometrics, minors): where it enters, where it lives, where it goes, for how long.
- Legal basis and consent recorded where needed; purpose respected.
- Minimization: fields collected and transmitted beyond what is needed.
- Data subject rights: export and delete a user's data without breaking referential integrity.
- Sharing with third parties (integrations, analytics, **AI providers**): what leaves, under which legal basis, with which retention on the third party's side (international transfer when the provider is abroad).
- Automated decisions that affect people (e.g. AI scoring, churn or credit decisions): LGPD art. 20 gives the data subject the right to request review.
- Incident register and DPO (encarregado) contact where applicable to the company's size.

## 3.16 AI components → `ai-agent-security.md`
Apply the AI module when `AI_DETECTED=yes` or any LLM, agent, RAG, MCP or AI automation node exists — including ones found during the audit. It has its own inventory, Rule of Two analysis, checklist mapped to LLM01–LLM10:2026, ASI01–ASI10 and MCP01–MCP10, and test methodology. Its findings go into `03-findings.md` like any other.

## 3.17 Directed sweep for vibe-coded patterns
Review every hit of `vibe-patterns.sh` (Phase 2) and, in addition:
- `return true`, `allow = true`, `isAdmin = true` in server code.
- Handlers without a call to the auth middleware/guard — all of them, cross-checked against `00-surface.md`.
- `select('*')` or whole-object serialization in responses.
- Credentials, production URLs and tenant IDs hardcoded in code or tests.
- Duplicate routes/handlers with different protection.

## 3.18 Closing: finding validation
- Deduplicate: one root cause in N places is one finding with N locations.
- Try to refute each finding (rule 1).
- For each `CONFIRMADO`, write the proof as a **local** test that demonstrates the flaw on the current code (e.g. an authenticated request as tenant B reading tenant A's resource returns 200). That test becomes the fix's regression test.
- Assign severity (Annex A in `phase-6-report.md`) and fill the finding template (Annex B).
- Size each finding's fix effort (XS/S/M/L/XL, see `phase-5-remediation.md`) — it feeds the remediation estimate.
