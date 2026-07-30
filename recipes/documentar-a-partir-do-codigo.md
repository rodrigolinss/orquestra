# Escrever documentação a partir do código

## Para que serve

Para gerar ou atualizar documentação (um `README.md`, um comentário de uso
no topo de um script, uma seção do `SPEC.md`) quando o código já existe e
funciona, mas a descrição dele está desatualizada, incompleta ou nunca foi
escrita. O ponto central desta receita é: a fonte da verdade é o código
que existe, não o que "deveria" existir. Não use esta receita para
documentar uma feature que ainda não foi implementada — isso é
especificação, não documentação, e o agente vai inventar comportamento
para preencher a lacuna.

## Texto da tarefa

```
Documente [PREENCHER: o quê — ex: "os comandos de bin/nvo que ainda não
aparecem no SPEC.md" ou "o comportamento do hook em bin/guard.sh"] em
[PREENCHER: arquivo de destino, ex: SPEC.md, README.md].

Leia o código-fonte inteiro de [PREENCHER: arquivo(s) relevantes] antes de
escrever qualquer frase. Toda afirmação sobre comportamento tem que vir do
que o código de fato faz — se não tiver certeza do que uma parte faz,
rode o comando/teste correspondente para confirmar, não escreva por
inferência.

Não documente comportamento que você acha que "deveria" existir, nem
suavize limitações reais do código (ex.: se um comando não valida um
argumento, diga isso, não finja que valida).

Siga o tom e o formato já usado no arquivo de destino (ex.: o SPEC.md usa
listas objetivas em português, sem markdown decorativo; o README.md usa
tabelas e emojis com moderação) — não troque o estilo do documento
existente.

Ao final, para cada trecho novo, cite o arquivo e a linha do código que
sustenta a afirmação, nas notas — não no documento em si.
```

## Modelo sugerido e por quê

**Sonnet.** Ler código e transcrever comportamento em prosa clara é uma
tarefa de raciocínio médio, bem dentro da faixa do sonnet. Suba para opus
apenas se a documentação exigir sintetizar comportamento espalhado por
muitos arquivos ao mesmo tempo (ex.: descrever o fluxo completo
maestro → agente → guard.sh → merge) — aí a dificuldade está em juntar as
peças corretamente, não só em ler.

## Convém pedir plano antes?

Não, normalmente. Documentação é um artefato fácil de revisar depois de
pronto — dá para ler o resultado e pedir ajuste pontual. A exceção: se o
pedido for reescrever a estrutura inteira de um documento grande (não só
adicionar uma seção), vale pedir primeiro um sumário/índice proposto antes
de escrever o texto todo, para não descobrir só no fim que a organização
não agradou.

## Arquivos que o agente deve e não deve tocar

- **Pode editar:** o(s) arquivo(s) de documentação indicados como destino
  (`README.md`, `SPEC.md`, ou um comentário de cabeçalho específico).
- **Não deve tocar:** nenhum arquivo de código-fonte. Se ao documentar o
  agente perceber uma inconsistência ou bug no código, ele deve registrar
  isso nas notas, não corrigir por conta própria.

## Critério de pronto

- Cada afirmação de comportamento no texto novo tem lastro citável em
  código (arquivo:linha), listado nas notas.
- Nenhum comportamento futuro ou desejado foi descrito como se já
  existisse.
- O estilo do documento de destino foi mantido (compare visualmente com o
  restante do arquivo).
- Nenhum arquivo de código foi alterado — `git diff` mostra só o(s)
  arquivo(s) de documentação.
