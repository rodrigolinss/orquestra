# Cobrir um módulo com testes

## Para que serve

Para quando existe um módulo, script ou arquivo que faz algo importante e
não tem nenhum teste (ou tem pouco) — por exemplo `bin/guard.sh` antes de
existir o `bin/guard-test.sh`, ou uma função nova em `bin/nvo` que ninguém
testou além de rodar na mão. Não use esta receita para "melhorar a
qualidade geral dos testes do projeto": isso é vago, sem alvo, sem fim.
Escolha **um módulo, um arquivo**, por vez.

Se o módulo já tem teste e o pedido é consertar um teste que quebrou, esta
não é a receita certa — é mais perto de "investigar um bug".

## Texto da tarefa

```
Escreva testes para [PREENCHER: caminho do arquivo/módulo, ex: bin/guard.sh].
Leia o arquivo inteiro antes de escrever qualquer teste — não escreva teste
para comportamento que você supõe, só para o que o código realmente faz.

Cubra pelo menos: os casos de uso normais (o caminho feliz), os casos de
borda óbvios (entrada vazia, argumento ausente, caminho inexistente) e os
casos que a lógica atual trata explicitamente como erro.

Não altere o código de produção em [PREENCHER: caminho do arquivo/módulo]
para "facilitar" o teste. Se o código for difícil de testar como está,
pare e me diga o motivo em vez de refatorar por conta própria.

Rode os testes que você escreveu e cole a saída (passando) nas notas antes
de terminar. Se algum teste falhar por um bug real no módulo (não no
teste), não corrija o bug — descreva o que encontrou nas notas e pare
esse teste específico como "encontrado, não corrigido".

Arquivos que você pode tocar: [PREENCHER: caminho do novo arquivo de teste,
ex: bin/guard-test.sh, ou tests/nome_do_modulo_test.sh].
Não toque em nenhum outro arquivo.
```

## Modelo sugerido e por quê

**Sonnet.** Ler um arquivo e derivar casos de teste dele é raciocínio
médio — não é digitação mecânica (não é haiku) nem exige a profundidade de
arquitetura que justificaria opus. Se o módulo for muito grande (milhares
de linhas, múltiplas responsabilidades), considere opus só pela quantidade
de contexto a segurar de uma vez, não pela dificuldade do raciocínio.

## Convém pedir plano antes?

Não, na maioria dos casos. Escrever testes é uma tarefa cujo resultado dá
para julgar direto pelo diff final — não há uma decisão de arquitetura
irreversível no meio do caminho. Peça plano antes só se o módulo não tiver
nenhuma infraestrutura de teste ainda (nenhum framework, nenhum test
runner configurado) — nesse caso a escolha de framework é uma decisão que
vale confirmar antes do agente escrever 200 linhas em cima dela.

## Arquivos que o agente deve e não deve tocar

- **Pode criar/editar:** o arquivo de teste novo (ex.:
  `bin/guard-test.sh`, ou um arquivo dedicado ao módulo em questão).
- **Não deve tocar:** o próprio módulo sob teste, qualquer outro módulo do
  projeto, configuração do projeto (`.claude/settings.json`,
  `config.conf`), documentação.

## Critério de pronto

- Existe um arquivo de teste novo, executável, cobrindo caminho feliz +
  pelo menos duas bordas.
- Rodar o arquivo de teste localmente termina com todos os casos passando
  (ou com falhas explicadas nas notas como bug real encontrado, não
  escondidas).
- O módulo de produção não mudou uma linha — `git diff` no arquivo
  original está vazio.
- As notas do agente incluem a saída do teste rodando, não só a afirmação
  de que "os testes passam".
