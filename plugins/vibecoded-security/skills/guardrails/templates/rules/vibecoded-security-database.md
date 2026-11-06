---
paths:
  - "supabase/**"
  - "**/migrations/**"
  - "**/*.sql"
  - "prisma/**"
  - "drizzle/**"
  - "**/schema.{ts,prisma}"
---
<!-- Managed by vibecoded-security. Re-run /vibecoded-security:guardrails to update; local edits are overwritten. -->

# Database security rules

- Every new table in an exposed schema gets `enable row level security` **and** its policies in the same migration. RLS without policies denies everything through the API — never ship one without the other.
- Policies are scoped: `auth.uid()` for user data, the session's tenant for tenant data. Never `using (true)` or `with check (true)` on tables with private data.
- `UPDATE` policies have both `using` and `with check`, so a row cannot be moved to another user or tenant.
- Authorization never reads `user_metadata` / `raw_user_meta_data` (users can edit it). Use `app_metadata` or a dedicated table.
- Views are created `with (security_invoker = true)`. Materialized views ignore RLS: keep them out of exposed schemas.
- `security definer` functions: `set search_path = ''`, schema-qualified names, explicit permission checks inside, and `revoke execute ... from anon` unless anonymous access is intended.
- Storage: per-user/tenant folder policies; public buckets only for truly public content; signed URLs with expiry.
- Every migration is reversible (write the down/rollback) and is never applied to production by the agent.
- Test new policies impersonating each role inside a transaction that rolls back, on a local database:
  `begin; set local role authenticated; set local request.jwt.claims = '{"sub":"<uuid>","role":"authenticated"}'; select ...; rollback;`
