# Receitas de tarefa

## O problema que isso resolve

Toda tarefa para um agente nasce de uma tela em branco. Quando quem escreve
não tem prática em pedir coisas para um agente, o texto sai vago — "melhora
os testes", "dá uma olhada nesse bug", "atualiza as dependências" — e um
pedido vago não economiza trabalho, ele só transfere a decisão para o
agente. O agente decide sozinho o escopo, os arquivos, quando parar. Às
vezes acerta. Quando erra, o erro custa crédito de verdade: um agente que
"atualiza dependências" pode reescrever meio projeto, um agente que
"investiga um bug" pode sair corrigindo antes de você entender o que
aconteceu, um agente que "revisa segurança" pode nunca dizer quando terminou
porque ninguém definiu o que é terminar.

Uma receita é um pedido pronto para colar em `nvo new <nome> "<tarefa>"`.
Ela já decidiu, de antemão, as perguntas que mais geram gasto errado:
o que o agente pode tocar, o que ele nunca deve tocar, se vale a pena pedir
plano antes de codar, qual modelo usar, e principalmente — o que é "pronto".

## Formato de cada receita

Cada arquivo `.md` nesta pasta segue a mesma estrutura, nesta ordem:

1. **Para que serve** — em que situação usar esta receita, e em que
   situação ela é o pedido errado.
2. **Texto da tarefa** — o texto pronto para colar como `"<tarefa>"` no
   `nvo new`, com espaços marcados `[PREENCHER: ...]` para os detalhes que
   só quem pede sabe (nome do módulo, branch, arquivo).
3. **Modelo sugerido e por quê** — sonnet, opus ou haiku, com a razão
   (custo, complexidade de raciocínio, quantidade de arquivos).
4. **Convém pedir plano antes?** — se a tarefa tem uma decisão de design
   que vale confirmar antes de gastar crédito codando, a receita diz para
   pedir `EnterPlanMode` / plano primeiro; se é mecânica, diz para ir direto.
5. **Arquivos que o agente deve e não deve tocar** — a lista concreta.
   Isso é o que evita o agente "passear" pelo repo mexendo em coisa que
   não foi pedida.
6. **Critério de pronto** — a frase que você usa para saber, olhando o
   resultado, se o agente cumpriu ou não. Sem isso, "terminei" vira uma
   afirmação do agente, não um fato que você pode conferir.

## Como usar

1. Escolha a receita que corresponde ao que você quer.
2. Copie o texto da seção "Texto da tarefa" e preencha os campos marcados
   `[PREENCHER: ...]`. Não deixe nenhum colchete no texto final — cada um
   que sobra é uma decisão que voltou a ser vaga.
3. Rode:
   ```
   nvo new <nome-do-agente> "<texto preenchido>" claude <modelo-sugerido>
   ```
4. Se a receita disser "peça plano antes", adicione ao final do texto:
   `Antes de mexer em qualquer arquivo, entre em modo de planejamento e
   me mostre o plano.` — e só solte o agente para codar depois de aprovar.
5. Ao final, confira o resultado contra o "critério de pronto" da receita
   antes de rodar `nvo done`. Se não bateu, é mais barato pedir o ajuste
   específico com `nvo send <nome> "..."` do que aprovar por inércia.

## As receitas

- `cobrir-modulo-com-testes.md` — escrever testes para um módulo que hoje
  não tem, sem tocar no código de produção.
- `atualizar-dependencias.md` — subir versões provando, com evidência, que
  nada quebrou.
- `investigar-bug-sem-corrigir.md` — diagnosticar uma causa raiz e escrever
  o relatório, sem tocar em código.
- `revisar-seguranca-de-branch.md` — auditoria de segurança de uma branch
  antes de integrar, sem corrigir automaticamente.
- `documentar-a-partir-do-codigo.md` — gerar documentação fiel ao código
  atual, sem inventar comportamento.
- `limpar-codigo-morto.md` — remover código comprovadamente não usado, sem
  refatorar o que ainda está vivo.

Se nenhuma receita cobrir o que você precisa, escreva o pedido do zero —
mas use estas seis como modelo de nível de detalhe. Um pedido bom tem
sempre estas mesmas peças: escopo, arquivos-limite e critério de pronto.
