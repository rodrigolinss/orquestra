# Orquestra — análise estratégica de inovação

Análise da versão em `agent/inovacao` (README.md, SPEC.md, `bin/nvo`, `bin/guard.sh`,
`bin/harnesses.conf`, `app/main.swift`, `install.sh`). Nenhum arquivo além deste relatório
foi alterado.

> **Ressalva sobre o ecossistema:** a comparação abaixo vem de conhecimento prévio das
> ferramentas, sem acesso à rede nesta sessão. Serve como mapa de posicionamento; antes de
> virar material público, vale reconferir cada projeto — esse espaço muda rápido.

---

## 1. O que o Orquestra já é

Três decisões estruturais que o diferenciam e que **nenhuma proposta aqui deve quebrar**:

| Decisão | Onde vive no código | Por que importa |
|---|---|---|
| Isolamento no sistema de arquivos | `cmd_new` → `git worktree add` + `assert_wt_inside` | Não depende de prompt. Um agente confuso não alcança a main. |
| Barreira determinística | `guard.sh` como hook `PreToolUse` | Bloqueia antes de executar, independente do humor do modelo. |
| Integrar é decisão humana digitada | `cmd_done` exige `confirm == name` | Sem merge de um clique, nem na CLI nem no app. |

E três escolhas de engenharia que dão vantagem competitiva silenciosa:

- **Estado = sistema de arquivos.** Sem daemon, sem banco. Mata o tmux e nada se perde.
- **Harness plugável** (`bin/harnesses.conf`): Claude, Codex, Gemini, DeepSeek via Aider — e
  qualquer CLI que aceite prompt como último argumento, sem recompilar nada. Quase todo
  concorrente é casado com um único vendor.
- **Hierarquia com limites econômicos** (`max_depth`/`max_fanout`/`max_agents`, com a
  explicação do *porquê* dentro do `config_spec`). Delegação com freio, não delegação infinita.

## 2. Onde estão os buracos (leitura do código)

Estas lacunas são a matéria-prima das 10 propostas:

1. `guard.sh` só intercepta o tool **Bash**. `Write`/`Edit` não passam pelo hook — um agente
   pode escrever fora do worktree por caminho absoluto sem tocar num comando de shell.
   E a blocklist é regex: `eval $(echo cm0gLXJm | base64 -d)` passa reto.
2. `nvo done` **não roda teste nenhum**. "Aprovar" é ler um diff que pode ter 2 mil linhas.
3. Conflito de merge só aparece na hora do `done`, depois de o trabalho estar pronto.
4. Status é `grep` nos últimos 4000 bytes das notas (`agent_status`). Protocolo frouxo: o
   agente que escreve "não estou BLOQUEADO" fica marcado como bloqueado.
5. `nvo usage` mede, mas não impõe: sem teto, sem alerta, sem auto-pausa.
6. Não existe `nvo resume`. Depois de `nvo stop` ou de um reboot, os worktrees continuam lá
   mas os agentes não voltam a rodar.
7. Toda tarefa começa de prompt em branco. Não há receitas nem histórico reaproveitável.
8. GUI só no macOS. Linux e WSL2 — provavelmente a maioria dos devs — ficam na CLI.

## 3. Comparação com o ecossistema

| Categoria | Exemplos | Como se posicionam | Onde o Orquestra ganha | Onde perde |
|---|---|---|---|---|
| **Orquestradores locais por worktree** | Claude Squad, Crystal, Conductor, uzi | Mesma ideia central: N agentes, N worktrees, uma UI para acompanhar | Firewall determinístico, trava humana no merge, multi-harness, hierarquia com limite | UI mais madura neles; kanban, histórico de sessão |
| **Isolamento por container** | container-use (Dagger), devcontainers + agente | Isolam filesystem **e rede**; agente roda em sandbox real | Zero setup, zero Docker, arranca em segundos | Worktree não isola rede nem `postinstall` malicioso de dependência |
| **Board de tarefas para agentes** | Vibe Kanban e similares | Fila visual de tarefas, agente pega e executa | Supervisão ao vivo com terminal, notas e diff no mesmo card | Não há fila, backlog, nem "próxima tarefa" |
| **Nativo do harness** | Subagentes do Claude Code, Agent SDK | Subagentes dentro de um processo, sem isolamento de disco | Isolamento real por branch; funciona entre vendors diferentes | Integração mais profunda com o modelo (contexto compartilhado barato) |
| **Nuvem / assíncrono** | Devin, agentes de background do Cursor, Codex cloud | Rodam remoto, abrem PR sozinhos | Roda na sua máquina, com suas credenciais, custo previsível e auditável | Nada roda sem o laptop aberto; sem PR, sem equipe |
| **Par único** | Aider, Claude Code puro | Um agente, um repo | Paralelismo supervisionado | Simplicidade |

**Tese de posicionamento.** O mercado está indo para *"agente autônomo que abre PR sozinho"*.
O Orquestra é a aposta oposta e defensável: **paralelismo com humano no laço e barreira que não
depende do modelo**. O diferencial a martelar não é "rodo 6 agentes" — é
**"rodo 6 agentes e nenhum deles consegue estragar seu repositório"**. Isso é o que a
concorrência não tem, e é o que sobrevive quando os modelos ficarem melhores (autonomia vira
commodity; confiança, não).

O segundo diferencial subaproveitado é o **multi-harness**. Times mistos (builder no Sonnet,
revisor no Codex, docs no Gemini Flash) são hoje uma linha de config e ninguém no README
explica que isso também é uma estratégia de custo e de segunda opinião. Vale virar narrativa.

---

## 4. Top 10 propostas, priorizadas

Ordem = valor entregue por unidade de esforço, considerando que reforçar a tese de confiança
vale mais que somar features.

### 1. Portão de verificação antes do merge (`nvo check`)

- **Problema:** aprovar hoje é ler diff. O humano não tem evidência de que o código roda —
  e é exatamente essa insegurança que faz alguém desistir de usar agentes em paralelo.
- **Proposta:** um `verify=` opcional no `config.conf` (ou detectado: `npm test`, `pytest`,
  `make test`). `nvo check <nome>` roda o comando dentro do worktree do agente e grava o
  resultado no `.meta`. `nvo done` e o card do app mostram **verde/vermelho antes do diff**;
  vermelho não bloqueia (continua sendo decisão humana), mas aparece.
- **Esforço:** M — uma função em `bash`, um campo no `.meta`, um selo no `AgentNode`.
- **Impacto:** Alto. Transforma "eu acho que está bom" em "os testes passam". É o passo que
  torna a aprovação defensável.

### 2. Tradutor de diff: revisão em linguagem natural

- **Problema:** para quem não lê diff com fluência, `nvo done` é um muro. É o maior obstáculo
  de adoção fora do público dev experiente.
- **Proposta:** `nvo explain <nome>` roda um agente barato (Haiku/Flash) sobre o diff e produz
  6–10 linhas: o que mudou, em que arquivos, qual o risco, o que testar manualmente, e o que o
  agente prometeu nas notas mas **não** entregou no código. Vira a primeira aba do `DoneSheet`,
  com o diff cru atrás dela.
- **Esforço:** P — um prompt, uma chamada de harness, uma aba no sheet.
- **Impacto:** Alto. Abre o produto para product managers, designers e devs juniores sem
  afrouxar nenhuma regra de segurança: quem decide continua digitando o nome.

### 3. Guard 2.0 — cobrir escrita e fechar o escape de regex

- **Problema:** o firewall é a promessa central do produto e hoje ele tem dois furos reais:
  não cobre os tools de escrita (`Write`/`Edit`), e blocklist por regex é contornável por
  qualquer indireção de shell.
- **Proposta:** (a) registrar o hook também para os matchers de escrita, validando que o
  caminho de destino cai dentro do worktree do agente; (b) inverter a lógica no que der —
  allowlist de comandos comuns em vez de lista de proibições; (c) log append-only de tudo que
  foi bloqueado, em `~/orquestra/agents/<proj>/<agente>.guard.log`, visível no app.
- **Esforço:** M/G — o (a) é pequeno e urgente; (b) é redesenho e exige cuidado para não virar
  fricção; (c) é pequeno.
- **Impacto:** Alto. É a diferença entre "temos um firewall" e "temos um firewall que aguenta
  auditoria". Se um único post mostrar um bypass trivial, a tese inteira do produto trinca.

### 4. Mapa de colisão entre agentes

- **Problema:** o README avisa "divida por fronteira de arquivo", mas nada verifica. Dois
  agentes no mesmo arquivo só se descobrem no `nvo done`, com o trabalho já feito — e o
  segundo merge vira conflito manual.
- **Proposta:** `nvo new` aceita `--files "src/pagamentos/**"` (o maestro já sabe declarar
  isso ao dividir a tarefa). Um `nvo collisions` compara `git diff --name-only` de todos os
  worktrees vivos e alerta sobreposição real, no `nvo ls` e como faixa no canvas do app.
  Aviso, não bloqueio — o humano decide.
- **Esforço:** M.
- **Impacto:** Alto. Ataca o principal custo escondido do paralelismo, que é retrabalho por
  conflito. É também a feature que justifica subir de 2 para 5 agentes com tranquilidade.

### 5. Orçamento de tokens com teto e auto-pausa

- **Problema:** `nvo usage` mostra o buraco depois que ele existe. Um agente em loop consome a
  janela de 5h do time inteiro e ninguém percebe até o app ficar vermelho.
- **Proposta:** teto por sessão e por agente no `config.conf`. Ao cruzar 80%, notificação
  nativa; ao cruzar 100%, o agente recebe automaticamente um `send` do tipo *"pare, registre
  onde parou nas notas e aguarde"* — pausa cooperativa, sem matar o processo. Barra de consumo
  por card, não só o total na faixa de status.
- **Esforço:** M — o medidor (`nvo-usage.py`) já existe; falta atribuição por agente e o gatilho.
- **Impacto:** Alto. Custo é a objeção número um a rodar times de agentes; ser a ferramenta que
  *impõe* o orçamento, e não só o exibe, é diferencial vendável.

### 6. Protocolo de notas v2 — bloco de status estruturado

- **Problema:** `agent_status` faz `grep` nos últimos 4000 bytes do markdown. Falsos positivos
  são inevitáveis, e nada além de quatro estados pode ser extraído das notas.
- **Proposta:** o agente passa a escrever, além do texto livre, um bloco delimitado no fim da
  nota (`<!--nvo status=trabalhando etapa=2/5 arquivos=3 proximo="testes" -->`). O parser lê o
  bloco quando existe e cai no `grep` atual quando não existe — compatível para trás. Habilita
  barra de progresso real, ETA grosseiro e métricas por agente.
- **Esforço:** P — mudança no prompt inicial e uma função de parsing.
- **Impacto:** Médio-alto. Baixo custo e destrava várias features de UI e de métrica que hoje
  não têm dado confiável de onde partir.

### 7. Receitas de tarefa (`nvo run <receita>`)

- **Problema:** toda tarefa nasce de um prompt em branco, e o README admite que tarefa vaga
  gasta token errado. Quem não é dev sênior não sabe escrever "critério de pronto".
- **Proposta:** uma pasta `recipes/` com tarefas parametrizadas e já bem escritas — *cobrir
  módulo X com testes*, *atualizar dependências e provar que nada quebrou*, *investigar este
  bug e escrever o diagnóstico sem corrigir*, *revisar segurança desta branch*. Cada receita
  traz modelo sugerido, `--plan` ou não, `--files` e critério de pronto. No app, viram cartões
  no diálogo de novo agente.
- **Esforço:** P/M — o mecanismo é pequeno; escrever boas receitas é o trabalho real.
- **Impacto:** Alto. É o caminho mais barato de "instalei" para "tirei valor", e as receitas
  são conteúdo de marketing e ponto de contribuição da comunidade ao mesmo tempo.

### 8. `nvo resume` — sobreviver ao reboot

- **Problema:** `nvo stop` preserva worktrees, branches e notas, mas religar é manual, agente
  por agente, e o contexto que o agente tinha na cabeça se perde. Um reboot do Mac hoje custa
  a sessão inteira.
- **Proposta:** `nvo resume [<nome>]` recria as janelas tmux e relança cada harness com um
  prompt de retomada montado a partir de `.meta.prompt` + a nota atual ("você já fez isto,
  continue daqui"). No app, um botão "religar equipe" quando a sessão está fria.
- **Esforço:** M.
- **Impacto:** Médio-alto. Menos uma feature nova do que a remoção de um motivo recorrente de
  abandono — e reforça a promessa "o estado é o sistema de arquivos".

### 9. Fila de integração com preflight de rebase

- **Problema:** `cmd_done` exige o repo principal limpo e na branch base, e dois agentes
  concluídos precisam ser mergeados em série na mão. O segundo quase sempre pega conflito
  porque a base andou.
- **Proposta:** `nvo done` faz um merge de ensaio (`git merge --no-commit --no-ff` em worktree
  descartável) e informa **antes da confirmação** se vai conflitar e em quais arquivos. Se
  conflitar, oferece devolver ao próprio agente: *"rebase na base atual e resolva"*, com um
  `send` pronto. Uma `nvo queue` mostra a ordem sugerida de integração.
- **Esforço:** M.
- **Impacto:** Médio. Não expande o público, mas remove o atrito no exato momento em que o
  usuário está colhendo o resultado — que é o momento em que ele decide se a ferramenta valeu.

### 10. Interface multiplataforma (Tauri/web) + supervisão remota — **aposta grande**

- **Problema:** o canvas do app é o principal encanto do produto e ele é exclusivo do macOS.
  Linux e WSL2, que provavelmente concentram a maioria dos usuários potenciais, veem só a CLI.
  E hoje é preciso estar na frente da máquina para supervisionar.
- **Proposta:** reescrever a camada visual como servidor local (`nvo serve`) + front web, com
  o app nativo virando um invólucro. Isso entrega de uma vez: Linux e Windows, acesso pelo
  navegador do celular na mesma rede (aprovar plano e responder BLOQUEADO longe da mesa) e um
  ponto único de evolução de UI. Regras de segurança inalteradas — a confirmação digitada
  continua obrigatória, e o servidor não escuta fora do localhost sem opt-in explícito.
- **Esforço:** G — reescrita de 2.700 linhas de SwiftUI e uma nova superfície de ataque a
  tratar com cuidado.
- **Impacto:** Alto no longo prazo, zero no curto. Multiplica o público endereçável, mas só
  depois que 1–7 estiverem prontos. Fazer isto antes seria construir uma vitrine melhor para
  um produto que ainda não fechou seus buracos.

---

## 5. Corte: quick wins vs apostas grandes

**Quick wins (P) — cabem numa semana somados, e mudam a percepção do produto:**
`#2 tradutor de diff`, `#6 notas v2`, `#7 receitas`, `#3a` (registrar o hook nos tools de
escrita — pequeno e é o furo mais constrangedor do código hoje).

**Núcleo (M) — o trimestre:** `#1 portão de verificação`, `#4 mapa de colisão`,
`#5 orçamento`, `#8 resume`, `#9 fila de integração`.

**Apostas grandes (G):** `#10 UI multiplataforma` e o restante do `#3` (allowlist).
Uma terceira aposta, fora do top 10 por não ser madura: **isolamento por container opcional**
(`nvo new --sandbox`), que é a única resposta real ao vetor "dependência maliciosa roda
`postinstall`" — hoje o worktree não protege contra isso.

**Sequência sugerida:** #2 → #3a → #6 → #7 → #1 → #4 → #5 → #8 → #9 → #10.
A lógica: primeiro barateia entender e aprovar (2, 6, 7), depois fecha a promessa de segurança
(3a, 1), depois torna o paralelismo de verdade confortável (4, 5), depois a robustez
operacional (8, 9), e só então expande a superfície (10).

## 6. Usuários menos técnicos — o que realmente destrava

O Orquestra já acertou o mais difícil: a linguagem natural para o maestro e o app que mostra
tudo num canvas. O que falta é sempre no **momento da decisão**:

1. **Aprovar sem ler diff** (`#2`). Hoje o produto pede uma habilidade que o público-alvo
   ampliado não tem. Resolver isso é o item de maior alavancagem de adoção da lista inteira.
2. **Não precisar escrever a tarefa do zero** (`#7`). "Escolha uma receita" é uma porta de
   entrada; "descreva o que você quer, com critério de pronto" é um teste.
3. **Saber o que está acontecendo sem ler terminal** (`#6`, `#5`). Progresso e custo em barra,
   não em scrollback.
4. **Errar sem medo** — já existe (`nvo kill` preserva a branch), mas não está dito com essas
   palavras em lugar nenhum da interface. É documentação, custo zero: *"descartar é seguro,
   nada se perde"* escrito no próprio `KillSheet`.

Um princípio a manter em todas: **facilitar nunca pode virar automatizar a decisão**. A trava
digitada do `nvo done` é o produto. Explicar melhor o que está sendo aprovado é ajudar;
aprovar por alguém seria virar mais um dos concorrentes.

## 7. O que ficou de fora, e por quê

- **Abrir PR no GitHub.** Óbvio e pedido, mas conflita de frente com o `git push` bloqueado no
  guard e com a tese "integrar é local e humano". Merece decisão de produto antes de virar
  proposta — não é um item de backlog, é uma bifurcação de identidade.
- **Replay / post-mortem de sessão.** Valioso para vender ("veja tudo que os agentes fizeram
  ontem"), mas depende do `#6` para ter dado estruturado. Fica para depois dele.
- **Marketplace de harnesses.** O `harnesses.conf` já é extensível; um marketplace seria
  cerimônia antes de existir demanda.
- **Métricas agregadas / telemetria.** Contraria a promessa de privacidade explícita do README.
  Só faria sentido 100% local, e aí é o `#6` com outro nome.
