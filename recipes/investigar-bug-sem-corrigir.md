# Investigar um bug e escrever o diagnóstico, sem corrigir

## Para que serve

Para quando algo está errado — um comando do `nvo` se comporta de forma
inesperada, o `guard.sh` deixa passar um comando que deveria bloquear, o
app trava numa tela específica — e você quer entender a causa raiz antes
de decidir o que fazer. É a receita certa quando o bug é sério ou pouco
entendido o bastante para que corrigir às cegas seja mais arriscado que
gastar um passo extra em diagnóstico.

Não use esta receita para bugs triviais e óbvios (typo, argumento na
ordem errada) — nesses casos peça direto a correção, separar diagnóstico
de correção só adiciona uma etapa sem ganho. Use quando a causa não é
óbvia, ou quando o bug afeta segurança/dados e você quer revisar o
diagnóstico antes de autorizar qualquer mudança.

## Texto da tarefa

```
Investigue o seguinte problema, sem corrigir nada:

[PREENCHER: descrição do sintoma observado — o que você esperava
acontecer, o que aconteceu de fato, e como reproduzir, ex: "ao rodar
`nvo new foo \"tarefa\" claude sonnet` duas vezes seguidas para o mesmo
nome, o segundo worktree fica num estado inconsistente"]

Reproduza o problema localmente antes de investigar o código — não
assuma que entendeu o sintoma só pela descrição acima. Se não conseguir
reproduzir, registre isso como achado e pare, não invente uma causa.

Depois de reproduzir, encontre a causa raiz — não pare no primeiro
sintoma. "A função X retorna vazio" não é causa raiz se a pergunta certa
é por que ela retorna vazio.

Escreva nas notas um diagnóstico com: o que reproduz o bug (passo a
passo), qual arquivo e linha contêm a causa raiz, por que o código atual
se comporta assim, e o que você recomendaria mudar (sem fazer a mudança).

Não edite nenhum arquivo do projeto. Esta tarefa termina com um
diagnóstico escrito, não com código corrigido.
```

## Modelo sugerido e por quê

**Sonnet**, e considere **opus** se o bug envolver múltiplos arquivos
interagindo (por exemplo, um problema de estado entre `bin/nvo` e o
hook em `.claude/settings.json`) ou se já houve uma tentativa anterior de
diagnóstico que não achou a causa — nesse caso o raciocínio mais profundo
do opus vale o custo extra porque evita uma segunda rodada perdida.

## Convém pedir plano antes?

Não. Investigação não tem uma decisão de design a confirmar no meio —
o valor está no processo de exploração em si. Pedir plano antes de
investigar só adicionaria uma etapa artificial. O controle aqui vem de
proibir a correção, não de aprovar um plano.

## Arquivos que o agente deve e não deve tocar

- **Pode tocar:** nenhum arquivo do projeto deve ser editado. O agente
  pode rodar comandos, ler arquivos e escrever exclusivamente nas
  próprias notas (`notes/<projeto>/<nome>.md`).
- **Não deve tocar:** qualquer arquivo de código, configuração ou
  documentação do projeto. Se o agente perceber que precisa de um
  arquivo temporário para reproduzir o bug (ex.: um repo de teste), ele
  deve usar um diretório fora do projeto (scratchpad), nunca criar
  arquivos dentro do worktree do projeto.

## Critério de pronto

- As notas descrevem passos de reprodução que você (ou outra pessoa)
  consegue seguir e chegar no mesmo sintoma.
- As notas apontam um arquivo e uma linha (ou uma sequência de chamadas)
  como causa raiz — não uma hipótese vaga tipo "provavelmente é
  concorrência".
- `git diff` do worktree do agente está vazio: nenhum arquivo de produção
  foi tocado.
- Existe uma recomendação de correção nas notas, mesmo que a correção em
  si fique para uma tarefa seguinte.
