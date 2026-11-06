---
paths:
  - "**/app/**/route.{ts,js,tsx,jsx,mjs}"
  - "**/app/**/actions.{ts,js}"
  - "**/actions/**/*.{ts,js}"
  - "**/pages/api/**"
  - "**/api/**/*.{ts,js,mjs,py}"
  - "**/server/**/*.{ts,js,mjs}"
  - "**/routes/**/*.{ts,js,mjs,py}"
  - "**/controllers/**/*.{ts,js}"
  - "**/middleware.{ts,js}"
  - "supabase/functions/**"
  - "**/webhooks/**"
---
<!-- Managed by vibecoded-security. Re-run /vibecoded-security:guardrails to update; local edits are overwritten. -->

# API, server action and webhook security rules

- Each handler authenticates and authorizes by itself: session → user → role → ownership → tenant. In Next.js, every `"use server"` export and route handler is a public endpoint; middleware is not an authorization boundary.
- Load resources by `id` **and** owner/tenant in the same query; return 404 for resources of other tenants.
- Validate the body, query and headers with a schema; accept only allowlisted fields (no mass assignment). Return only the fields the client needs — no `select *`, no whole entities.
- Webhooks: verify the provider signature with a constant-time comparison, reject stale timestamps, deduplicate by event ID, and respond fast (queue heavy work). Providers that do not sign: long secret in path/header + IP allowlist + schema validation.
- Rate limits and quotas per user/tenant/key, calibrated from real traffic (p99 × margin), shipped first in counting/report-only mode. Remember shared NATs, batch imports and webhook bursts.
- Errors: generic messages to clients, details only in server logs (without secrets or tokens); fail closed on authorization errors.
- Outbound requests to user- or integration-supplied URLs go through a host allowlist that blocks internal IPs and metadata endpoints (SSRF).
- Changing a response contract? Keep old mobile app versions and external integrations working (version the endpoint or keep backward compatibility).
