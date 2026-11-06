# Phase 5 — Remediation plan, timeline fit and execution

## 5.1 Size each fix

| Size | Agent time | Human time (review, decide, deploy) | Typical example |
|---|---|---|---|
| XS | ≤ 15 min | ≤ 15 min | remove a secret from a log, pin a dependency |
| S | ≤ 1 h | ≤ 30 min | add an authorization check to one handler with tests |
| M | ≤ 4 h | 1–2 h | RLS policies for a set of tables with role tests; webhook signature + idempotency |
| L | 1–2 days | 0.5–1 day | tenant isolation across a module; splitting an AI agent flow (Rule of Two) |
| XL | > 2 days | > 1 day | architectural change; becomes its own project, outside this audit |

Add the Phase 4 overheads: characterization tests when the project has none (+30%), report-only observation windows (calendar time only).

## 5.2 Prioritize

Order by severity (Annex A) × ease of exploitation × exposure × effort × regression risk. Exposed secrets, cross-tenant access, authentication bypass, injection on public endpoints and lethal-trifecta AI flows come first, always.

## 5.3 Fit into the timeline → `security-audit/ROADMAP.md` (pt-BR)

Using the deadline and weekly human hours from `PLAN.md`, and the actual effort ratio from calibration:

```markdown
# Roadmap de correções

Capacidade: <h humanas/semana> · Prazo: <data> · Fator de calibração: <real/estimado>

## Semana 1 — <foco>
| Achado | Severidade | Classe | Tamanho | Agente | Você | Entrega |

## Semana 2 — ...

## Janelas de observação (report-only)
| Controle | Início | Fim | Processos observados | Critério para ativar |

## Não cabe no prazo — backlog com risco aceito
| Achado | Severidade | Risco de esperar | Mitigação temporária | Precisa de aceite de: |
```

Present the roadmap as the second decision point: what gets fixed now, what goes behind flags, what stays in the backlog. Backlog items with severity Alto or Crítico require the user's explicit risk acceptance, recorded in `decisions.md`.

## 5.4 `audit` mode
Deliver the report (Phase 6) and the roadmap. Change no code, config or database.

## 5.5 `fix` mode
- One branch per domain: `security/<domain>` (e.g. `security/access-control`), following the project's git flow (Gitflow, commit conventions, PR template) if one exists.
- Atomic commits, with the finding ID in the message.
- Apply only `AUTO`. Implement `GUARDED` switched off / report-only, with a kill switch and activation instructions. For `HUMAN`, record options and your recommendation in `security-audit/decisions.md`.
- No push, merge, deploy or remote migration (rule 7). Migrations stay as versioned files, each with a rollback script.
- For each fix, a ready PR summary (pt-BR): findings fixed, affected processes, rollout strategy, tests added, rollback instructions.
- Add the security tests to the project (e.g. `tests/security/`), generated from the authorization matrix: anonymous access to each protected endpoint, access from another tenant, insufficient role, invalid webhook signature, injection at the fixed points, AI adversarial cases. They stay forever.
- Propose adding the Phase 2 tools to CI as a blocking step for high/critical severity.
- Never commit secrets, dumps or real data, not even in tests.
