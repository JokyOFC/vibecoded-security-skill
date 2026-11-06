# Phase S — Scoping, effort/cost estimate and recommendation

Goal: before any audit work, let the user choose **which phases run**, knowing **how much work and cost each one takes**, judged against **their Claude plan, their deadline and the hours they can spend**, and get a clear **recommendation** for the project. Output: `security-audit/PLAN.md`, approved by the user.

This phase must stay cheap: no deep code reading. Target ≤ 15 minutes of agent time.

All text shown to the user is in pt-BR. The question texts below are the ones to use.

---

## Step 1 — Measure the project (read-only)

Run:

```bash
bash <AUDIT_DIR>/scripts/sizing.sh . > security-audit/00-sizing.md
```

It reports code size per language, test size, entry-point counts (route handlers, server actions, API routes, edge functions, framework routes), database objects in migrations, automations (n8n workflows, webhook nodes, AI nodes), mobile apps, infra files, AI/LLM integrations, and ends with machine-readable lines:

```
SIZE_CLASS=S
AI_DETECTED=yes
MOBILE_DETECTED=no
SUPABASE_DETECTED=yes
SELF_HOSTED_INFRA=yes
AUTOMATIONS_DETECTED=yes
TEST_RATIO=low
```

Size classes (the script takes the larger of the two dimensions):

| Class | App code (LOC, excluding tests/SQL/config) | Entry points |
|---|---|---|
| XS | < 5k | < 15 |
| S | 5k–20k | 15–50 |
| M | 20k–80k | 50–150 |
| L | 80k–250k | 150–400 |
| XL | > 250k | > 400 → must be split into scopes of size L or smaller |

Glance at the top-level layout (one `ls`, the manifests) to correct obvious misreadings — e.g. a vendored SDK inflating LOC, or a monorepo where only one app is in scope. Note corrections in `00-sizing.md`.

## Step 2 — Interview, round 1 (context)

Ask these four questions in one call to the question tool (fallback: plain text, same options). Skip a question only if the user already answered it in this conversation.

1. **header** `Plano` — "Qual plano do Claude você vai usar nesta auditoria?"
   - `Pro`
   - `Max 5x`
   - `Max 20x`
   - `API, Team ou Enterprise` — description: "Pago por uso ou cota da organização"
2. **header** `Prazo` — "Em quanto tempo a auditoria e as correções precisam estar prontas?"
   - `Até 1 semana`
   - `2 a 4 semanas`
   - `1 a 3 meses`
   - `Sem prazo fixo`
3. **header** `Seu tempo` — "Quantas horas por semana você (ou o time) consegue dedicar para revisar, decidir e fazer deploy?"
   - `Até 2 h`
   - `2 a 5 h`
   - `5 a 10 h`
   - `Mais de 10 h`
4. **header** `Motivo` — "Qual o principal motivo da auditoria agora?"
   - `Vou lançar ou vender` — "Antes de abrir para clientes ou fechar contrato"
   - `Cliente ou LGPD exigiu` — "Due diligence, questionário de segurança, compliance"
   - `Suspeito de incidente` — "Algo estranho aconteceu ou um segredo vazou"
   - `Prevenção contínua` — "Higiene de segurança, sem urgência específica"

**If the answer is "Suspeito de incidente":** do not continue with a normal audit plan. Follow rule 9: propose the **Incident triage** package (below) first, explain why in two sentences, and only plan the full audit after triage.

## Step 3 — Estimate

### Modules

Base effort is for size class **S**. Multiply by the size factor: XS ×0.5 · S ×1 · M ×2 · L ×3.5 · XL → split into scopes and estimate each.

"Agent time" = time the agent is actively working (not waiting for answers). "Your time" = human time to answer questions, provide access, review, decide and deploy. "Consumption" is relative token usage per hour of agent time: low (mostly scripts and tools), medium, high (heavy code reading).

| ID | Module (pt-BR label) | Phases | Agent time (S) | Your time (S) | Consumption | Applies when / prerequisite |
|---|---|---|---|---|---|---|
| M0 | Escopo e estimativa | S | 0.25 h | 0.25 h | low | always |
| M1 | Reconhecimento, processos e baseline | 0 | 1.5 h | 1–2 h (confirm processes and roles, export logs) | medium | required before any fix |
| M2 | Modelagem de ameaças | 1 | 0.5 h | 0.5 h | low | recommended from size M |
| M3 | Ferramentas automáticas | 2 | 0.75 h | 0.5 h (installs, read-only DB access) | low | always recommended |
| M4 | Auditoria manual do núcleo (3.1–3.12, 3.17, 3.18) | 3 | 3 h | 0.5 h | high | core of every package |
| M5 | Mobile (3.13) | 3 | 0.75 h | 0.25 h | medium | `MOBILE_DETECTED=yes` |
| M6 | Infra, VPS, automações e CI (3.14 + server checks) | 2–3 | 1 h | 1 h (SSH read-only, panel screenshots) | medium | `SELF_HOSTED_INFRA` or `AUTOMATIONS_DETECTED` |
| M7 | Dados pessoais e LGPD (3.15) | 3 | 0.5 h | 1 h | low | personal data handled |
| M8 | Chatbots e agentes de IA (3.16 + AI module) | 1–3 | 1.5 h (+1 h adversarial test run) | 0.5–1 h | high | `AI_DETECTED=yes` |
| M9 | Análise de compatibilidade (Phase 4) | 4 | 10 min per finding | 5 min per finding | medium | before any fix |
| M10 | Correções (`fix` mode) | 5 | AUTO 20–30 min each · GUARDED 60–90 min each | review/merge/deploy 15–60 min each | high | after M1 + M9 |
| M11 | Verificação independente e relatório | 6 | 1 h | 0.5–1 h | medium | every package |
| M12 | Guardrails no projeto (CLAUDE.md, AGENTS.md, regras, hook) | — | 0.1 h | 0.1 h | low | recommended always |

Adjustments:
- `TEST_RATIO=low` (few or no tests): +30% on M9 and M10, because characterization tests must be written before changing anything (Phase 4.5).
- No logs available: M1 is shorter, but every rate-limit/CORS/upload control becomes report-only first (longer calendar time, same agent time).
- Many services or a monorepo: +20% on M1 and M4 per extra service beyond two.
- M9/M10 depend on the number of findings, unknown before the audit. Estimate them with a range: vibe-coded projects of size S typically yield 10–30 findings, with roughly a third fixable as AUTO. State that this range is an assumption and re-estimate after Phase 3.

### Packages

Offer three packages plus custom. Build them from the modules that apply to this project (drop modules whose detection is "no").

| Package | Modules | Mode |
|---|---|---|
| **Essencial** | M0, M1 (light: processes + surface + authz matrix), M3, M4 focused on 3.1, 3.2, 3.4, 3.12, 3.17, M8 if AI is public-facing, M11 (short report), M12 | `audit` |
| **Recomendado** | Essencial + full M1, M2, full M4, M5/M6/M8 when detected, M9, M10 (AUTO only), M11, M12 | `fix` (AUTO) |
| **Completo** | Recomendado + M7, AI adversarial test run, GUARDED fixes prepared behind flags, security test suite in CI | `fix` (AUTO + GUARDED prepared) |
| **Triagem de incidente** | env targets, secrets scan with full history, active-compromise checks (server users, keys, cron, processes, recent auth/admin events), immediate rotation list | `audit`, then escalate |

### Cost

**Agent cost depends on the plan:**

- **API (pay per use)**: the honest number comes from measurement. Anthropic reports that Claude Code costs on average about US$ 13 per developer per active day, below US$ 30 for 90% of users. An audit is heavier than average coding, so give the first estimate as a range: `active days ≈ agent hours ÷ 4` → `cost ≈ active days × US$ 13–30`, and say it is preliminary. Calibrate after M0 and after Phase 0 (see Calibration). For headless runs, suggest `--max-budget-usd`.
- **Pro / Max / Team / Enterprise (subscription)**: usage is included but limited by rolling 5-hour and weekly windows. Translate agent time into "how many sessions / days", not money. Initial fit before calibration (heuristic, say so):

| Plan | Comfortable before calibration | How to make it fit |
|---|---|---|
| Pro | Essencial for XS–S | Split across days; sweeps on cheaper-model subagents; usage credits are an optional paid extra |
| Max 5x | Recomendado up to M | Split L by scope |
| Max 20x | Completo up to M; Recomendado for L | Split L/XL by scope |
| API, Team, Enterprise | Any, bounded by budget/seat | Set a spend limit; split XL |

**Tools cost:** every tool in Phase 2 has a free open-source option (gitleaks, semgrep CE, osv-scanner, npm audit, trivy, ZAP, nuclei, promptfoo/garak for AI). Paid platforms are optional and never required.

**Human cost:** usually the real bottleneck. Sum "your time" across chosen modules.

### Calendar fit

```
weeks_needed = max( human_hours_total / human_hours_per_week ,
                    agent_days_needed / agent_days_per_week )
```

- `agent_days_per_week`: API/Max 20x ≈ 5; Max 5x ≈ 4; Pro ≈ 2–3 for heavy modules (window limits). Heuristic until calibrated.
- Add report-only observation windows when fixes include GUARDED controls: at least one full cycle of the affected processes (often 1–4 weeks; monthly jobs force a month). They add calendar time, not effort.
- Compare with the deadline. If it does not fit, propose in this order: (1) narrow the scope to the highest-risk parts (public endpoints, tenant isolation, secrets, public AI features); (2) move M2, M7, M5 and GUARDED fixes to a second round; (3) audit now and fix in a later window; (4) extend the deadline. Never cut M0, the processes list (M1 light) or M3 secrets/dependencies.

Priority order when cutting (most risk reduced per hour first): M3 → M4 (authz, tenant isolation, secrets, database) → M8 if the AI feature is public or can act → M1 → M9/M10 (AUTO) → M6 → M5 → M2 → M7 → GUARDED fixes.

## Step 4 — Recommend

Recommend one package, adjusted to motive, plan and deadline, and say why in 2–4 sentences. Rules:

- **Vou lançar ou vender** → Recomendado; M8 is mandatory if an AI feature is reachable by customers; M12 always.
- **Cliente ou LGPD exigiu** → Recomendado + M7; the report gets a sanitized executive summary that can be shared without exploitable details.
- **Prevenção contínua** → Essencial + M12, and a re-audit cadence (before major releases, or quarterly).
- **Suspeito de incidente** → Triagem de incidente now; full audit after.
- If the recommended package does not fit plan + deadline, recommend the largest one that fits with ~30% margin and list what was moved to a second round, with the risk of leaving it.

Also always recommend, as project-level measures independent of the package (these go in a "Recomendações para o projeto" section):
- M12 guardrails, so new AI-written code stops reintroducing the same issues.
- CI gates: secrets scan, SAST and dependency audit blocking on high/critical.
- A permanent `tests/security/` suite generated from the authorization matrix.
- Secrets in a secret manager with a written rotation runbook.
- Staging isolated from production (separate database, keys, buckets).
- Restore test of backups.
- Alerts for 401/403 spikes, webhook signature failures, cost spikes on AI features.
- For AI features: spend caps per user/tenant, deterministic approval gates for consequential actions, conversation-log retention policy.

## Step 5 — Present and decide (round 2)

Show the user, in pt-BR and in this order:
1. One-paragraph reading of the project (size class, stack, what was detected, what is notable).
2. A table of the applicable modules: `Módulo | O que entrega | Tempo do agente | Seu tempo | Consumo`.
3. The three packages with totals: agent time, your time, estimated cost or plan fit, calendar weeks vs. deadline (fits / tight / doesn't fit).
4. The recommendation and why.
5. Assumptions and what will be recalibrated.

Then ask, in one call to the question tool:

1. **header** `Pacote` — "Qual pacote você quer executar?" options: list the recommended package first and append ` — sugerido` to its label (e.g. `Recomendado — sugerido`), then the other applicable packages. The user can pick "Other" to type a custom list of modules.
2. **header** `Ajustes` (multiSelect) — "Quer adicionar ou tirar algo do pacote?" up to four of the most relevant toggles for this project, e.g. `Incluir módulo de IA`, `Incluir LGPD`, `Sem correções (só auditar)`, `Instalar guardrails no fim`.
3. **header** `Acessos` (multiSelect) — "Quais acessos você consegue fornecer?" options: `Logs de produção`, `Banco somente leitura`, `Servidor (SSH leitura)`, `Staging isolado`. Missing access turns the dependent checks into documented gaps, not blockers.

## Step 6 — Write `PLAN.md`

`security-audit/PLAN.md`, in pt-BR:

```markdown
# Plano da auditoria de segurança

- Data: <AAAA-MM-DD> · Escopo: <all | lista> · Classe de tamanho: <XS–XL>
- Plano Claude: <...> · Prazo: <...> · Horas humanas/semana: <...> · Motivo: <...>
- Acessos disponíveis: <...> · Lacunas por falta de acesso: <...>

## Pacote escolhido: <nome> (modo <audit|fix>)
| Módulo | Incluído | Tempo do agente | Seu tempo | Observação |

## Estimativa
- Tempo total do agente: <x–y h> · Seu tempo: <x–y h>
- Custo estimado: <US$ faixa (API) | sessões/dias no plano X>
- Calendário: <N semanas> vs. prazo <...> → <cabe | apertado | não cabe>
- Premissas: <lista> · Recalibração prevista: após M0 e após a Fase 0

## Fica para uma segunda rodada
| Módulo | Risco de deixar para depois |

## Recomendações para o projeto
<lista do Step 4>

## Aprovação
- [ ] Aprovado pelo usuário em <data>
```

Mark it approved only after the user says so. Mirror the approved modules in the task list.

## Calibration (during the audit)

At the end of M0 and of every phase, append to `STATE.md`:

```
| Fase | Estimado (agente) | Real (agente) | Consumo informado | Desvio |
```

- Agent time: measure wall-clock time of active work in the phase.
- Consumption: ask the user to glance at `/usage` (API users see the session cost; subscribers see the plan usage bars) at the end of M0 and Phase 0 — one short question, not every phase.
- Re-estimate the remaining modules with the observed ratio. If the projection deviates more than 30% from the plan, or no longer fits the deadline or plan, stop at the phase boundary and ask the user how to proceed, showing the options from "Calendar fit".

## Remediation estimate (after Phase 3)

The cost of the fixes is only knowable after the findings exist. Phase 5 (`phase-5-remediation.md`) sizes each finding, sums effort and fits it into the remaining calendar in `ROADMAP.md`. Present that as the second decision point: what gets fixed now, what goes behind flags, and what stays in the backlog with explicitly accepted risk.
