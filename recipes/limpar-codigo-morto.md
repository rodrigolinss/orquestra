# Limpar código morto

## Para que serve

Para remover código comprovadamente não usado — uma função que nada mais
chama, um arquivo que ficou órfão depois de uma refatoração anterior, um
bloco `if` que nunca é alcançável, um comando do `nvo` que foi substituído
e ficou esquecido. Não use esta receita para "limpar" ou "simplificar" o
código de forma geral — isso é refatoração, tem julgamento de gosto
envolvido e merece uma tarefa própria, com critério diferente. Esta
receita é estritamente sobre remover o que está **provadamente morto**:
sem chamador, sem referência, sem uso.

Se você não tem certeza se algo é realmente morto ou só raramente usado,
não use esta receita — peça primeiro uma investigação ("liste candidatos
a código morto e para cada um diga como você verificou que não é usado,
não remova nada"), e só depois rode a remoção.

## Texto da tarefa

```
Remova o código morto em [PREENCHER: escopo — um arquivo específico, ex:
bin/nvo, ou o projeto inteiro se for uma varredura ampla].

Para cada trecho candidato a remoção, prove antes que ele não é usado:
procure todas as referências no projeto inteiro (grep pelo nome da
função/variável/arquivo), não só no arquivo onde ele está. Considere
também chamadas indiretas (ex.: um comando do nvo invocado só pelo nome
em uma string, um script chamado só pelo install.sh).

Se restar qualquer dúvida sobre se algo é usado (ex.: pode ser chamado
externamente, por outro projeto, ou só em um caminho de código raro),
não remova — liste como "candidato incerto" nas notas e siga para o
próximo.

Remova apenas o que você confirmou sem uso. Depois de remover, rode a
suíte de testes/build do projeto ([PREENCHER: comando, ex:
bin/guard-test.sh, app/build.sh]) e cole a saída nas notas — a remoção só
fica se o projeto continuar funcionando.

Não aproveite para renomear, reorganizar ou "melhorar" nada que não seja
a remoção em si.
```

## Modelo sugerido e por quê

**Sonnet.** Buscar referências e decidir "usado vs. não usado" é um
raciocínio direto, mecânico o bastante para não precisar de opus, mas que
exige mais contexto que uma tarefa de haiku (que erraria fácil ao não
checar todos os pontos de chamada). Para um projeto pequeno e um escopo
bem definido (um arquivo só), haiku pode bastar — mas o risco de haiku
deixar passar uma chamada indireta é maior, então sonnet é o padrão mais
seguro.

## Convém pedir plano antes?

Não, desde que o texto da tarefa já exija prova de não-uso antes de cada
remoção — o próprio processo já é a proteção. Peça plano antes apenas se
o escopo for "o projeto inteiro" (não um arquivo específico): nesse caso
vale pedir primeiro a lista de candidatos, para você aprovar quais de fato
remover, antes do agente editar em massa.

## Arquivos que o agente deve e não deve tocar

- **Pode editar:** apenas os arquivos onde código morto foi confirmado e
  removido, dentro do escopo definido no texto da tarefa.
- **Não deve tocar:** qualquer arquivo fora do escopo pedido, e nenhum
  código que ainda tenha uso confirmado ou incerto — mesmo que pareça
  "feio" ou redundante.

## Critério de pronto

- Cada remoção tem, nas notas, a prova de que não havia referência (o
  comando de busca usado e o resultado).
- Candidatos incertos foram listados separadamente, não removidos.
- A suíte de testes/build roda com sucesso depois da remoção — saída
  colada nas notas.
- `git diff` mostra só remoções (e ajustes mínimos de sintaxe
  decorrentes, como fechar um bloco), nenhuma renomeação ou reorganização
  não pedida.
