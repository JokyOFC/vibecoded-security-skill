# Phase 4 — Compatibility analysis (no fix skips this phase) → `security-audit/04-compat.md`

This is the phase that keeps the audit from becoming an incident. For **every** finding, before proposing or applying a fix, fill the sections below.

## 4.1 Operational impact of the fix
- **Affected processes**: the `P-xx` IDs whose path goes through the changed code/config. If unsure, trace the path — never guess "none".
- **Change type**:
  - `TRANSPARENTE` — observable behavior identical for every actor (parameterize a query, remove a secret from a log, patch a dependency without breaking changes).
  - `COMPORTAMENTAL` — responses, formats, limits or timing change, but flows keep working (stricter validation, a new header, a rate limit).
  - `BLOQUEANTE` — some actor or flow stops working as it does today (endpoint starts requiring auth, a field becomes mandatory, an old app version stops working).
- **Regression risk**: low / medium / high, with a reason.
- **Calibration**: every new limit, allowlist or format comes from the baseline (Phase 0.3) — e.g. a rate limit of at least 3–5× the observed p99 for that limiting key; origin allowlist = observed origins + registered tenant domains; upload formats = observed formats. A value without data behind it ships only as REPORT-ONLY.

## 4.2 Legitimate cases this fix may block
Check explicitly against this list — these are the most common hardening mistakes:
- Rate limit / anti-abuse × bulk imports, webhook bursts, syncs, cron, many users behind the same NAT.
- Requiring authentication × webhooks, OAuth callbacks, healthchecks, status pages, public tenant pages, signed links.
- Requiring webhook signatures × a provider that does not sign, or signs differently — read the provider's documentation first.
- Restricted CORS × white-label domains, tenant subdomains, mobile apps, preview environments.
- Strict CSP × third-party scripts (analytics, chat, payments), inline styles, legitimate iframes and widgets.
- Strict input validation × Brazilian formats (CPF/CNPJ with and without mask, phone with DDD/DDI, CEP, accents, apostrophes, compound names), legacy data already in the database, optional fields the old UI does not send.
- Upload validation × real formats in use (HEIC/HEIF, scanned PDFs, old spreadsheets), real sizes, names with spaces and accents.
- Enabling RLS × a table without policies yet: RLS on with no policy denies everything through the API. Create the policies in the same migration and test with every role first.
- RLS / database authorization × jobs using the service key, external automations, realtime, views and RPCs used by reports, migrations.
- Closing an apparent leak × a legitimate role not yet modeled (multi-unit manager, support, consolidated reports) — confirm in the authz matrix.
- Session/token expiry × shared devices, panels, kiosks, apps open for days, clients without refresh.
- API contract changes × old mobile versions in the field, integrations consuming the API, internal scripts.
- Secret rotation × integrations holding the old key, environments reading from elsewhere, workers that do not restart by themselves.
- Security headers × iframe embeds, PDFs served inline, downloads, redirects.
- Dependency upgrades × breaking changes, parsing/serialization behavior changes, peer dependencies.
- Removing an "unused" route × real use by cron, an integration, an old app or a hidden screen. Prove it is unused (baseline logs, search across all repositories) before removing.
- Fail-closed × a flow that today depends on fail-open, including when a third party is down — the degraded behavior is a business rule (HUMAN).
- AI controls × the cases in `ai-agent-security.md` Step 8 (guardrail false positives in pt-BR, latency, approval fatigue, quotas, prompt changes).

## 4.3 Rollout strategy
Choose the **least invasive one that still fixes**:
1. `DIRETO` — only for TRANSPARENTE changes with low risk.
2. `REPORT-ONLY / SHADOW` — the control logs what it would block, without blocking (CSP `Report-Only`, validation that logs and continues, rate limit in counting mode, guardrail in log-only mode, RLS policy tested on a copy). The window covers at least one full cycle of every affected process, including weekly/monthly jobs, month-end and peak hours. Review the logs; only then enforce.
3. `FEATURE FLAG` — control behind a flag, off by default; progressive activation per tenant/environment.
4. `ALLOWLIST PRIMEIRO` — origins, hosts, IPs and formats: start by allowing everything observed as legitimate, then restrict.
5. `JANELA + ROLLBACK` — for an approved BLOQUEANTE change: advance notice, a window, a tested rollback.

Every GUARDED control has a **kill switch** (environment variable or flag) that disables it without a deploy.

## 4.4 Documented exceptions
When a control needs an exception (e.g. a public webhook endpoint), record: reason, minimal scope, **compensating control** (HMAC signature, IP allowlist, idempotency, dedicated rate limit, monitoring) and review date. An exception without a compensating control is a finding.

## 4.5 Non-regression tests
For every affected `P-xx`, define **how to prove it still works** and run it **before** (baseline) and **after** the change.
- Project without tests (common in vibe coding): first write **characterization tests** for the affected processes — they capture current behavior, including what looks odd — and only then change anything. If a process cannot be tested automatically (a real external integration), write a reproducible manual script and treat the fix as GUARDED at most.
- RLS: test on a local database or copy, never production, inside a transaction that rolls back, impersonating each role from the matrix:
  ```sql
  begin;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"<user-uuid>","role":"authenticated"}';
  select ...;   -- what this role should (and should not) see
  rollback;
  ```
- AI features: the golden set of legitimate conversations plus the adversarial cases for the finding.
- Order: exploit test (demonstrates the flaw) + process tests (green) → fix → exploit blocked + processes still green.

## 4.6 Decision class
- `AUTO` — TRANSPARENTE, low risk, non-regression tests exist and pass. May be applied in `fix` mode.
- `GUARDED` — COMPORTAMENTAL or medium risk. In `fix` mode, implemented switched off or report-only, with a kill switch; activation is a human decision.
- `HUMAN` — BLOQUEANTE, high risk, business exception, cost, third parties, or a business-rule change. Never applied automatically; present options with pros and cons and your recommendation.
