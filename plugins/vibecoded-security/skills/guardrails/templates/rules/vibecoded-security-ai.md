---
paths:
  - "**/{ai,llm,agents,agent,chat,chatbot,bot,rag,mcp,prompts,assistant}/**"
  - "**/*{llm,agent,chatbot,prompt,rag,mcp,embedding,assistant}*.{ts,tsx,js,mjs,py}"
  - "**/.mcp.json"
  - "**/*workflow*.json"
---
<!-- Managed by vibecoded-security. Re-run /vibecoded-security:guardrails to update; local edits are overwritten. -->

# AI chatbot and agent security rules

Assume the model will be prompt-injected. The system must stay safe even when the model does exactly what an attacker wrote.

- Provider keys live only on the server. Never `dangerouslyAllowBrowser`, never an LLM key in a public-prefixed env var.
- Chat endpoints require authentication or strict anonymous quotas; set `max_tokens`, iteration limits, timeouts and per-user/tenant spend caps with a friendly degradation message (denial of wallet).
- System prompts and tool schemas will leak: no secrets, internal URLs or other users' data in them.
- Untrusted content (user messages, uploaded files, web pages, emails, RAG chunks, tool results) is passed as clearly delimited data, never merged into instructions.
- Retrieval is scoped by the session's user/tenant in the query or index (RLS, metadata filter enforced server-side) — never by the prompt and never by a value the model chooses.
- Tools are narrow verbs (`get_my_invoices`, not `run_sql`), validate arguments with a schema, take identity and tenant from the session in code, and authorize every call. No generic SQL, HTTP or shell tools; text-to-SQL never runs with privileged credentials.
- Rule of Two: no flow combines untrusted input + private data + the ability to act or send externally. Split the flow, remove a capability, or add a human confirmation triggered by code for consequential actions (money, messages, deletion, permission changes).
- Model output is untrusted: render as text or sanitized markdown (no raw HTML, no remote images), validate structured output before use, never `eval` it or build SQL/shell from it.
- Log every model and tool call with actor, tenant, tool, redacted arguments, tokens and cost; keep a kill switch per feature.
- Personal data sent to providers is minimized and covered by a legal basis (LGPD); users know they are talking to an AI.
- Changing prompts, models or guardrails: run the golden set of legitimate conversations (in Portuguese too) and the adversarial tests in `tests/security/ai/` before and after.
