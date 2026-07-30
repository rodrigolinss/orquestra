# Revisar segurança de uma branch antes de integrar

## Para que serve

Para quando uma branch de agente (ex.: `agent/nome`) está prestes a passar
por `nvo done` e você quer uma revisão de segurança dedicada antes de
aprovar — em especial se a branch mexeu em algo sensível: o hook de
segurança (`bin/guard.sh`), o `install.sh` (que roda com privilégios do
usuário), qualquer coisa que monta comando de shell a partir de entrada
externa, ou o app nativo lidando com dados do usuário. Não é uma receita
para "revisar o código" de forma geral — isso é uma tarefa diferente,
mais próxima de code review de qualidade. Esta é estritamente sobre
segurança: coisas que podem vazar dado, escalar privilégio, ou furar o
isolamento entre agentes que é a promessa central do projeto (ver
`SPEC.md`, seção "Regras de segurança").

## Texto da tarefa

```
Revise a segurança do diff da branch [PREENCHER: nome da branch, ex:
agent/nova-feature] contra [PREENCHER: branch base, normalmente main]
sem corrigir nada — apenas relate.

Rode `git diff [PREENCHER: base]...[PREENCHER: branch]` para ver o escopo
completo antes de começar. Não confie em resumo de commit, leia o diff.

Preste atenção especial a: comandos de shell montados por concatenação de
string (risco de injeção), qualquer bypass ou enfraquecimento das
verificações em bin/guard.sh, novos caminhos que escapam de
~/orquestra/worktrees ou de dentro do repo, uso de --dangerously-skip-permissions
ou equivalente, credenciais ou segredos hardcoded, e qualquer mudança em
.claude/settings.json ou install.sh que amplie permissão.

Para cada achado, registre nas notas: o arquivo e a linha, o que
especificamente pode dar errado (não "isso parece inseguro" — descreva o
cenário concreto de abuso), e a severidade (bloqueia integração / vale
corrigir mas não bloqueia / observação).

Se não encontrar nada, diga isso explicitamente nas notas — "revisado,
nenhum achado" é uma resposta válida e diferente de não ter revisado.

Não corrija nenhum achado. Não edite nenhum arquivo do projeto.
```

## Modelo sugerido e por quê

**Opus.** Segurança é exatamente o tipo de revisão onde um raciocínio mais
cuidadoso paga o custo extra — um falso negativo aqui (um bypass de
segurança que passa despercebido) custa muito mais do que a diferença de
preço entre opus e sonnet. Use sonnet apenas se a branch for pequena e
não tocar em nenhum dos pontos sensíveis listados acima.

## Convém pedir plano antes?

Não. Não há decisão de design nessa tarefa, só leitura e julgamento. Pedir
plano antes só atrasaria sem ganho — o controle vem de proibir a correção
e exigir achados com severidade, não de aprovar um plano prévio.

## Arquivos que o agente deve e não deve tocar

- **Pode tocar:** nenhum arquivo do projeto. Apenas leitura (`git diff`,
  `git log`, abrir arquivos) e escrita nas próprias notas.
- **Não deve tocar:** qualquer arquivo do repositório, incluindo o próprio
  `bin/guard.sh` — mesmo que o agente identifique uma correção óbvia, ela
  fica para depois, revisada por um humano ou por uma tarefa de correção
  separada.

## Critério de pronto

- As notas cobrem o diff inteiro da branch revisada, não uma amostra.
- Cada achado tem arquivo, linha, cenário concreto de abuso e severidade.
- Se não há achados, isso está dito explicitamente.
- `git diff` do worktree do próprio agente de revisão está vazio.
- Você, lendo as notas, consegue decidir sozinho se aprova o `nvo done`
  da branch revisada ou pede correção antes.
