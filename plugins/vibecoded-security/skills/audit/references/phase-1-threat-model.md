# Phase 1 — Threat model → `security-audit/01-threat-model.md`

1. **Data-flow diagram** (Mermaid) with explicit **trust boundaries**: browser ↔ API, API ↔ database, API ↔ third parties, third parties → webhooks, worker ↔ database, mobile ↔ API, automations ↔ everything, CI → production, user ↔ LLM ↔ tools/data.
2. **STRIDE** for every component that crosses a boundary (Spoofing, Tampering, Repudiation, Information disclosure, Denial of service, Elevation of privilege). One row per plausible threat, with the affected asset.
3. **Cross-tenant access** is threat number one in any multi-tenant system. Model it explicitly for every data path.
4. **Business abuse cases**: for each critical process, describe how a legitimate but malicious user would abuse it (customer reading another customer's data, operator of one tenant acting in another, repeating a step with a changed value, undue cancellation or refund, mass export, enumeration through "forgot password").
5. **AI components**: add the threats from `ai-agent-security.md` (lethal trifecta / Rule of Two analysis per agent flow, prompt injection paths, tool misuse, denial of wallet). Use MITRE ATLAS technique names when describing adversary behavior against AI features.
6. **Prioritize** by exposure (public > authenticated > internal) × impact (personal data, money, operations).

Keep it proportional: for size XS–S, a single diagram and a table of the top 15–25 threats is enough. The threat list drives the order of Phase 3, not its coverage — every domain is still covered.
