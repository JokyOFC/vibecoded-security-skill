# Phase 6 — Verification and report → `security-audit/REPORT.md`

## Verification
1. Run the full test suite and the non-regression tests of **every** affected `P-xx`; compare with the baseline.
2. Re-run the Phase 2 tools: fixed findings are gone and no new ones appeared.
3. **Independent review**: delegate to the `security-verifier` subagent (plugin id `vibecoded-security:security-verifier`), which has not seen your reasoning. Give it only: the list of applied fixes with file paths, the process verification scripts, and `authz-matrix.md`. It tries to (a) bypass each fix and (b) run each affected process's verification. Attach its result verbatim.
4. Confirm `coverage.md` has no empty cell.

## Report (pt-BR)

```markdown
# Relatório de segurança — <projeto> — <data>

## Sumário executivo
5–10 linhas: postura geral, os 3–5 riscos mais graves, o que foi corrigido, o que depende de decisão.

## Ações desta semana
Até 5 itens com a maior redução de risco e o menor risco de regressão.

## Rotação de segredos
O que rotacionar, em que ordem, e quais processos dependem de cada segredo (para a rotação não derrubar integrações).

## Escopo, método e cobertura
Pacote executado, módulos fora do plano, matriz de cobertura (link), lacunas e por quê.

## Esforço: estimado × real
Tabela de calibração por fase; consumo informado; o que isso significa para a próxima auditoria.

## Mapa de processos, baseline e superfície (resumo)
## Modelo de ameaças (resumo)
## IA: inventário e análise Rule of Two (se aplicável)

## Achados
| ID | Severidade | Categoria | Status | Classe | Situação |
(detalhe de cada achado no formato do Anexo B)

## Matriz de compatibilidade
| Achado | Processos afetados | Estratégia | Teste |

## Decisões pendentes
Opções, prós e contras, recomendação.

## Exceções e controles compensatórios
## Roadmap (link para ROADMAP.md)
## Recomendações para o projeto
## Próximos passos
```

Do not declare the system "seguro". State what was verified, at what depth, and what remains.

If the user's motive was a client or LGPD request, also produce `REPORT-executivo.md`: scope, method, frameworks used, posture summary and remediation status, **without** exploitable details (no paths, payloads or unfixed vulnerability specifics).

## Annex A — Severity scale

| Nível | Critério |
|---|---|
| **Crítico** | Trivial exploitation by an unauthenticated actor or another tenant; leads to third-party data access, remote execution, account/admin takeover or direct financial loss. Exposed privileged secret. Public AI flow with the lethal trifecta. |
| **Alto** | Requires authentication or a specific condition, but grants undue access to data/functions, or allows easy denial of service (including denial of wallet on AI endpoints). |
| **Médio** | Requires chaining, user interaction or prior access; or exposes information that eases other attacks. |
| **Baixo** | Limited impact or very unlikely; defense in depth. |
| **Info** | Good practice not followed, no clear attack vector. |

## Annex B — Finding template (pt-BR field names)

```
### [SEV-NNN] Título curto e específico
- Severidade: Crítico | Alto | Médio | Baixo | Info
- Categoria: A0x:2025 / CWE-xxx / ASVS <capítulo> / LLMxx:2026 / ASIxx / MCPxx
- Status: CONFIRMADO | PROVÁVEL | SUSPEITO
- Localização: caminho/arquivo.ext:linha (todos os pontos)
- Evidência: trecho mínimo (segredos redigidos)
- Impacto: o que um atacante consegue, com qual pré-requisito
- Tentativa de refutação: outras camadas checadas e o resultado
- Reprodução: teste ou passos, sem efeitos destrutivos
- Correção proposta: descrição + diff ou pseudocódigo
- Tamanho da correção: XS | S | M | L | XL
- Processos afetados pela correção: P-xx, P-yy (ou "nenhum — rastreado em <onde>")
- Tipo de mudança: TRANSPARENTE | COMPORTAMENTAL | BLOQUEANTE
- Risco de regressão: baixo | médio | alto — motivo
- Casos legítimos em risco: itens da lista 4.2 verificados
- Calibração: de onde vieram limites/allowlists (baseline) ou "n/a"
- Estratégia de rollout: DIRETO | REPORT-ONLY | FEATURE FLAG | ALLOWLIST | JANELA+ROLLBACK
- Interruptor: nome da flag/variável (GUARDED) ou "n/a"
- Testes: exploit (antes/depois) e não regressão (baseline/pós)
- Rollback: como desfazer em menos de 5 minutos
- Classe: AUTO | GUARDED | HUMAN
- Situação: corrigido em <commit> | atrás de flag <nome> | pendente de decisão | backlog com risco aceito
```
