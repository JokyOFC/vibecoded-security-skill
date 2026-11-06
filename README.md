# vibecoded-security

Plugin para o **Claude Code** que audita a segurança de sistemas feitos com IA (*vibe coding*), cobrindo:
- web, API, banco, mobile, infraestrutura e automações;
- **chatbots e agentes de IA**.

Ele começa perguntando **o que você quer fazer** e mostrando **quanto trabalho e custo** cada etapa vai dar, de acordo com o seu plano do Claude e o seu prazo. Toda correção passa por uma análise de compatibilidade antes de ser aplicada, para **não bloquear nenhum processo legítimo** do sistema.

> *English summary:* a Claude Code plugin that runs an interactive, cost-aware security audit of AI-generated codebases (including LLM chatbots and agents), gates every fix through a compatibility analysis so legitimate processes never break, and injects security guardrails into CLAUDE.md/AGENTS.md. Prompts are written in English; the plugin talks to the user and writes reports in Brazilian Portuguese.

## O que vem no plugin

| Comando | O que faz |
|---|---|
| `/vibecoded-security:scope` | Mede o projeto e entrevista você (plano do Claude, prazo, horas disponíveis, motivo). Estima tempo do agente, seu tempo e custo por módulo, checa se cabe no prazo e recomenda um pacote. Não audita nada: só gera o `PLAN.md` |
| `/vibecoded-security:audit [audit\|fix\|resume] [escopo]` | Auditoria completa: escopo → reconhecimento e mapa de processos → ameaças → ferramentas → auditoria manual (17 domínios + IA) → compatibilidade → correções → verificação independente → relatório |
| `/vibecoded-security:ai-review [design\|review]` | Segurança de chatbots, agentes, RAG, MCP e automações com IA, tanto ao construir quanto ao revisar. Também é carregada automaticamente quando você trabalha numa feature de IA |
| `/vibecoded-security:guardrails [install\|update\|remove]` | Injeta regras de segurança no `CLAUDE.md`/`AGENTS.md`, regras por caminho em `.claude/rules/`, Cursor, Copilot e um hook opcional que só avisa (nunca bloqueia) |

Também vem com dois subagentes:
- `security-sweeper`: varreduras amplas num modelo mais barato;
- `security-verifier`: revisor independente que tenta burlar as correções e confere se os processos continuam funcionando.

## Instalação

Pelo marketplace (recomendado):

```bash
claude plugin marketplace add JokyOFC/vibecoded-security-skill
claude plugin install vibecoded-security@vibecoded-security-skill
```

Dentro de uma sessão, o equivalente é `/plugin marketplace add JokyOFC/vibecoded-security-skill`.

Para testar sem instalar:

```bash
git clone https://github.com/JokyOFC/vibecoded-security-skill
claude --plugin-dir ./vibecoded-security-skill/plugins/vibecoded-security
```

Sem plugin (avulso): copie a pasta `plugins/vibecoded-security/skills/` inteira para `.claude/skills/` do projeto (as skills se referenciam entre si, então mantenha as quatro juntas) e `plugins/vibecoded-security/agents/` para `.claude/agents/`. Os comandos ficam sem prefixo (`/audit`, `/scope`…).

## Como usar

1. `/vibecoded-security:scope` para saber quanto custa e quanto tempo leva, sem compromisso.
2. `/vibecoded-security:audit`. Ele retoma o `PLAN.md` aprovado ou faz o escopo primeiro.
3. `/vibecoded-security:guardrails` para que o código novo gerado por IA não reintroduza os mesmos problemas.

Tudo que a auditoria produz fica em `security-audit/`, que é adicionado ao `.gitignore`: os relatórios podem conter vulnerabilidades ainda não corrigidas.

## Escopo, custo e prazo

A primeira etapa sempre roda e é barata (cerca de 15 minutos de agente).

1. Um script mede o projeto:
   - linhas de código e pontos de entrada;
   - objetos de banco e workflows n8n;
   - integrações de IA, app mobile e infraestrutura própria.
2. O projeto é classificado de **XS a XL**.
3. Você responde 4 perguntas: plano do Claude (Pro, Max 5x, Max 20x, API/Team/Enterprise), prazo, horas por semana disponíveis e motivo da auditoria.
4. Você recebe uma tabela por módulo com **tempo do agente**, **seu tempo** e **consumo**, mais três pacotes:
   - **Essencial**, **Recomendado** e **Completo**;
   - **Triagem de incidente**, quando há suspeita de vazamento.
5. Para cada pacote aparece o custo estimado: faixa em US$ para quem usa API, ou quanto ocupa das janelas de uso nos planos de assinatura.
6. Aparece também o cálculo de calendário contra o seu prazo e a recomendação justificada.
7. Durante a auditoria, as estimativas são **recalibradas** com o consumo real (`/usage`). Se o desvio passar de 30%, ele para e pergunta.
8. Depois dos achados, um `ROADMAP.md` encaixa as correções semana a semana no seu prazo. O que não couber vai para um backlog com **risco aceito explicitamente**.

## Como ele evita quebrar o sistema

- **Mapa de processos legítimos** antes de qualquer julgamento, incluindo os "invisíveis": webhooks em rajada, cron, realtime, apps antigos em campo, tablets e totens, domínios whitelabel.
- **Baseline de uso real** a partir dos logs: rate limit, CORS e validação são calibrados com dados, não no chute.
- **Fase de compatibilidade** obrigatória para cada achado:
  - classifica a mudança como transparente, comportamental ou bloqueante;
  - confere contra uma lista de 18 casos clássicos em que endurecimento quebra fluxo legítimo;
  - aplica o rollout menos invasivo (report-only, flag, allowlist);
  - exige teste de não regressão com baseline.
- **Classes de decisão**:
  - `AUTO` é aplicado sozinho;
  - `GUARDED` vai desligado e com interruptor;
  - `HUMAN` é sempre decisão sua.
- O agente nunca faz push, merge, deploy, migration remota ou rotação de segredo. Isso fica com você.

## Segurança de chatbots e agentes de IA

O módulo de IA aplica:
- **OWASP Top 10 for LLM Applications 2026**;
- **OWASP Top 10 for Agentic Applications**;
- **OWASP MCP Top 10**;
- **OWASP AI Testing Guide** e **Agent Control Standard**;
- **Agents Rule of Two** da Meta, que impede juntar entrada não confiável, dados privados e ações externas no mesmo fluxo;
- **padrões de design resistentes a prompt injection**: action-selector, plan-then-execute, dual LLM e outros;
- **MITRE ATLAS**, **NIST AI 600-1** e **LGPD**, incluindo dados enviados a provedores e o art. 20 sobre decisões automatizadas.

Também inclui uma metodologia de testes adversariais **em português e inglês** com promptfoo, garak, PyRIT ou DeepTeam, sempre em staging e com limite de gasto. A regra é que o teste só passa quando um controle determinístico bloqueia o impacto, não quando o modelo recusa.

## Requisitos

Os scripts incluídos rodam no bash do macOS (3.2) e no Linux, só com `git`, `grep`, `awk`, `sed` e `perl`. As ferramentas externas são opcionais e têm versão gratuita: gitleaks, semgrep, osv-scanner, trivy, ZAP e nuclei. Quando uma não está disponível, ela vira lacuna registrada no relatório.

## Estrutura

```
.claude-plugin/marketplace.json
plugins/vibecoded-security/
├── .claude-plugin/plugin.json
├── agents/                      security-sweeper, security-verifier
└── skills/
    ├── audit/                   SKILL.md + references/ (fases, IA, escopo) + scripts/
    ├── scope/                   só escopo e estimativa
    ├── ai-review/               chatbots, agentes, RAG, MCP
    └── guardrails/              scripts/inject.sh + templates/ (CLAUDE.md, rules, hook)
```

## Avisos

- Não substitui um pentest feito por pessoas. É uma auditoria assistida, com método e evidência.
- As estimativas de tempo e custo são heurísticas declaradas e são recalibradas durante a execução.
- Nunca declara o sistema "seguro": o relatório diz o que foi verificado, com que profundidade e o que falta.
