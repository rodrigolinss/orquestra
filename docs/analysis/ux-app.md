# Análise de UX — Orquestra.app (macOS)

Escopo: `app/main.swift` (SwiftUI, arquivo único, ~2724 linhas — não há mais
nenhum arquivo Swift no projeto). Foco: fricção de onboarding/instalação,
clareza do canvas de agentes, fluxo de aprovação de diffs, descoberta de
funcionalidades, feedback visual, acessibilidade e consistência. Análise
somente — nenhuma mudança de código foi feita.

Cada achado indica arquivo:linha e traz uma sugestão acionável. Impacto
Alto/Médio/Baixo é relativo ao efeito na experiência do usuário-alvo (alguém
que abre o app querendo orquestrar agentes de código, não necessariamente
fluente em git/terminal).

---

## Alto impacto

### 1. Instalação e primeiro boot dependem de sucesso silencioso do `xcrun swiftc`
`install.sh:82-89` compila o app com `xcrun swiftc` só se as Command Line Tools
estiverem presentes; se não estiverem, o instalador imprime um aviso no
terminal e segue em frente — mas quem vai *usar o app* pode nunca ter visto
esse aviso (rodou o instalador uma vez, fechou o terminal). O app não existe e
não há nenhuma tela, nem no Spotlight, explicando por quê.
**Sugestão:** o `nvo doctor` já roda ao final do instalador (`install.sh:106`)
— fazer esse diagnóstico também gravar um arquivo de status legível
(`~/orquestra/INSTALL_STATUS` ou similar) que um app minimalista de fallback,
ou uma futura tela de erro no primeiro launch, possa ler. Alternativa mais
barata: destacar em vermelho/negrito no final do install.sh quando o app não
foi compilado, em vez de uma linha de aviso no meio do log.

### 2. Zero feedback quando o `nvo` não está no PATH ou a sessão tmux está quebrada
O app assume que `NVO` (`main.swift:13`) e `TMUX` (`main.swift:36`) resolvem
corretamente via `toolPath()`. Se `nvo` não existir (instalação incompleta,
usuário moveu `~/orquestra`), `sh(NVO, ...)` falha e cada chamada
(`refreshHarnesses`, `refreshConfig`, `refresh`) simplesmente retorna cedo sem
popular nada (`main.swift:311-341`, `457-521`) — o painel fica vazio para
sempre, sem nenhuma mensagem. Do ponto de vista do usuário: "escolhi um
projeto e nada acontece".
**Sugestão:** se `refresh()` detectar `code != 0` de forma persistente (ex.
3 tentativas seguidas), popular `orch.lastError` com uma mensagem acionável
("não encontrei o `nvo` — reinstale com `bash ~/orquestra/install.sh`"). Hoje
o banner de erro (`main.swift:2518-2537`) só é usado por ações explícitas do
usuário (novo agente, done, kill, init) — nunca pelo polling de fundo.

### 3. `openTerminal()` falha silenciosamente sem permissão de Automação — mas só é comunicado em alguns caminhos
A função em si já devolve uma mensagem de erro completa e bem escrita
(`main.swift:72-84`, incluindo o caminho exato em Ajustes do Sistema). Ela é
usada corretamente para o merge/"ver ao vivo"/instalar harness — mas se a
autorização falhar na primeiríssima vez que o usuário tenta (fluxo mais comum:
clicar em "iniciar maestro" nunca chama `openTerminal`, mas "ver ao vivo" e
"instalar" chamam). Isso está OK. O problema real é que **essa é a única rota
de recuperação para instalar um harness que falta** (Ajustes → "instalar", ou
"novo agente" → botão "instalar" ao lado da CLI não instalada,
`main.swift:1712-1717`, `2116-2119`): se a automação nunca foi autorizada, o
usuário fica preso num ciclo de clicar "instalar" → erro de permissão →
autorizar em Ajustes do Sistema → **precisa lembrar sozinho de voltar e
clicar de novo**, porque não há nenhum retry automático nem link direto para
o painel de Privacidade.
**Sugestão:** ao detectar a falha de automação, oferecer um botão "abrir
Ajustes de Privacidade" que dispara
`x-apple.systempreferences:com.apple.preference.security?Privacy_Automation`,
e reexibir automaticamente o mesmo comando pendente (guardado em memória) com
um botão "tentar de novo" — hoje o comando de instalação alternativo aparece
só como texto selecionável dentro da mensagem de erro.

### 4. Card de agente concluído não se destaca visualmente na hierarquia da tela
`AgentStatus.concluido` usa a cor verde-nevoa (`main.swift:94`) só num pill de
texto pequeno (`main.swift:1286-1289`) e um ponto de 7px (`main.swift:1283`).
Num canvas com vários cards (o produto foi desenhado para múltiplos agentes em
paralelo — cabos, sub-agentes, drag-and-drop), não há nenhum destaque de
prioridade: uma borda pulsante, um badge maior, ou reordenação que traga
"concluído" para o topo da área visível. O usuário precisa varrer todos os
cards manualmente para achar quem terminou. A notificação do macOS
(`notifyMac`, `main.swift:507-513`) ajuda, mas só dispara na transição de
status — se o usuário estava fora do app nesse instante e a notificação
já sumiu do Centro de Notificações, não há nenhuma pista visual persistente
no canvas em si.
**Sugestão:** borda do card com leve glow/pulso quando `status == .concluido`
e nenhuma ação ainda foi tomada; opcionalmente uma barra de resumo fixa no
topo ("3 agentes aguardando revisão") como atalho de navegação — hoje o único
resumo de estado é a barra de uso de tokens.

### 5. Confirmação por nome digitado é sólida, mas o único mecanismo de recuperação de erro é reler texto
`DoneSheet` (`main.swift:1860-1935`) e `KillSheet` (`main.swift:2007-2053`)
exigem digitar o nome do agente para liberar o botão — deliberado e bem
documentado no comentário de topo do arquivo ("nunca um botão", linha 3-4).
Isso é uma decisão de segurança correta e deve ser preservada. O problema de
UX é menor mas real: o campo de confirmação não tem autocomplete/paste-safe
affordance (ex. um botão "copiar nome"), e o erro "o nome não confere"
(`main.swift:1924-1926`, `2035-2037`) só aparece depois do clique — não há
validação em tempo real (ex. campo fica verde ao digitar certo), o que
obriga o usuário a *clicar* para descobrir se acertou, mesmo com nomes longos
ou parecidos entre agentes.
**Sugestão:** validar o campo enquanto o usuário digita (o código já compara
`confirm == name` no `tint` do botão — reaproveitar essa mesma comparação para
colorir a borda do `TextField` em tempo real, sem exigir clique).

---

## Médio impacto

### 6. Onboarding de 4 passos é linear e correto, mas "passo 3" (criar agentes) não tem card equivalente aos passos 1 e 2
`StepCard` cobre "escolher projeto" (`main.swift:2559-2564`) e "iniciar
maestro" (`main.swift:2566-2572`) com destaque visual e botão de ação. O
"passo 3" vira só uma `Text` discreta dentro do canvas
(`main.swift:2590-2598`, "peça uma equipe ao maestro..."), sem o mesmo peso
visual dos StepCards anteriores (sem número circulado, sem botão de ação
direta). Isso quebra a progressão visual construída nos dois primeiros
passos — o usuário que se acostumou ao padrão "card com botão" pode não notar
que a frase solta no meio do canvas é, na prática, o passo 3.
**Sugestão:** usar o próprio `StepCard` (ou variante sem botão, já que a ação
é "escrever no campo do maestro") também para esse estado, mantendo
consistência visual da sequência 1→2→3.

### 7. Os "exemplos" de prompt (chips `👷 criar equipe`, etc.) só aparecem sob 3 condições simultâneas e desaparecem para sempre
`main.swift:1036`: `if orch.maestroRunning && orch.agents.isEmpty && draft.isEmpty`.
Assim que o primeiro agente é criado, os exemplos somem permanentemente
daquela sessão — mesmo que o usuário quisesse reler o texto de exemplo para
um segundo comando parecido, ou tenha clicado sem querer fora do chip. Não há
como reabrir os exemplos sem reiniciar o projeto do zero.
**Sugestão:** mover os exemplos para um menu descartável no botão de ajuda do
próprio card do maestro, ou manter acessíveis via um pequeno "?" permanente
perto do campo de prompt, em vez de condicioná-los à ausência total de
agentes.

### 8. Diff é texto puro num `TerminalText`, sem nenhuma sintaxe/realce de +/-
`DoneSheet` mostra o diff bruto (`main.swift:1883`, `TerminalText(content:
diff, ...)`) e `TerminalText` (`main.swift:752-774`) é só uma fonte
monoespaçada sem parsing. Um diff de `git diff`/`nvo diff` real tem linhas
`+`/`-`/`@@` que ficam todas na mesma cor (`Theme.text.opacity(0.85)`). Para
revisar rapidamente "o que mudou" — que é justamente o momento crítico de
aprovação irreversível (merge) — a ausência de cor verde/vermelha para
adição/remoção é uma perda real de legibilidade, especialmente em diffs
grandes que exigem rolar bastante.
**Sugestão:** um highlighter simples de linha (prefixo `+` → verde,
`-` → vermelho, `@@` → dim/accent) aplicado só na `DoneSheet`/diff sheet — não
precisa de um parser de diff completo, só colorir por prefixo de linha, o que
é barato e de alto retorno visual no momento mais sensível do fluxo.

### 9. Aprovação de plano ("aguardando") e aprovação de trabalho ("concluído") usam o verbo "aprovar" para ações de risco muito diferentes
Botão "aprovar plano" (`main.swift:1369-1373`) libera execução (reversível,
baixo risco) via `orch.approvePlan` — um clique, sem confirmação. Botão
"aprovar" no rodapé do card (`main.swift:1385-1388`) abre a `DoneSheet` que faz
merge de verdade (ação com efeito real no projeto, exige nome digitado). Dois
botões com o mesmo verbo raiz e ícones parecidos (`checkmark.seal` em ambos:
linhas 1369 e 1385) mas consequências muito diferentes — um humano
apressado pode confundir qual é o clique "seguro" e qual precisa de mais
atenção, especialmente porque o de plano *também* usa `checkmark.seal`.
**Sugestão:** usar ícones/verbos distintos: "liberar plano" com
`play.circle` (ação leve) vs. "aprovar e aplicar" mantendo `checkmark.seal`
(ação de merge) — hoje só a cor e o texto do tooltip diferenciam.

### 10. Notas (fonte de verdade do progresso) são um blob de markdown cru sem nenhuma renderização
`TextSheet` (`main.swift:1987-2005`) mostra `agent.note` via `TerminalText`
como texto puro monoespaçado — cabeçalhos `#`, listas `-`/`*`, negrito `**`,
tudo aparece com a sintaxe literal. Como o próprio comentário do arquivo diz
("notas como fonte de verdade", linha 2), essa é a superfície mais importante
para entender o que um agente fez, e hoje ela exige que o usuário "leia
markdown na cabeça".
**Sugestão:** renderizar ao menos negrito/cabeçalhos/listas com `AttributedString`
(SwiftUI já suporta Markdown nativo em `Text(markdown:)` desde macOS 12) — não
precisaria de dependência externa.

### 11. Barra lateral de arquivos (`FileBrowser`) não indica em qual worktree/agente o arquivo pertence quando aberto
Ao trocar o `Picker` de fonte (`main.swift:1501-1508`, projeto vs. agente),
`FileViewer` (`main.swift:1579-1657`) mostra caminho absoluto pequeno
(`main.swift:1618-1619`, `~/...`) mas não repete de forma destacada "isto é a
cópia do agente X" — se o usuário trocar a fonte no picker enquanto um arquivo
já está aberto, pode ficar sem saber se está olhando a versão do projeto
original ou de um agente específico até reparar no caminho pequeno em
monoespaçado cinza.
**Sugestão:** um badge de origem (nome do agente ou "projeto original") no
cabeçalho do `FileViewer`, com a mesma cor/estilo do badge "sub de X" já usado
em `AgentNode` (`main.swift:1304-1311`) — reaproveitando um padrão visual já
existente.

### 12. Zoom de UI é global e por fonte, mas não há indicação de que ele também afeta o tamanho dos cards do canvas
`UIScale` (`main.swift:726-748`) escala só tipografia via `Theme.uiSize`. Isso
é uma escolha técnica pragmática e bem documentada
(comentário de linhas 722-724 explica por quê), mas o efeito colateral é que
aumentar o zoom não redimensiona os cards (`AgentLayout.Box` guarda `w`/`h`
fixos em pontos, não relativos ao zoom) — texto maior dentro de um card de
tamanho fixo pode cortar/quebrar layout de forma inesperada em zoom alto
(150%, 200%), especialmente em `AgentNode` que empilha várias seções
(task/progress/terminal/teclas/prompt/botões) num `VStack` com altura fixa
(`main.swift:1396`, `frame(width: liveW, height: liveH...)`).
**Sugestão:** validar visualmente em 175%/200% (os dois últimos steps de
`UIScale.steps`, linha 728) se o conteúdo do card ainda cabe sem cortar
texto/botões — se não couber, considerar redimensionar minimamente os
cards padrão (`AgentLayout.defW/defH`) proporcionalmente ao zoom, só para
cards que o usuário nunca moveu manualmente.

---

## Baixo impacto

### 13. Tooltips (`.help(...)`) carregam informação essencial que não tem equivalente visual sem hover
Muitos dos textos mais explicativos do app vivem só em `.help()` — ex. o
significado de cada status (`main.swift:1290-1294`), o efeito de "descartar"
(`main.swift:1391`), a explicação da medição de tokens (`main.swift:2511`).
Em um trackpad/mouse isso funciona bem, mas tooltips do AppKit têm delay e
não são descobertos por quem não sabe que passar o mouse revela texto —
essa informação está duplicada de forma mais completa na aba "ajuda · sobre"
(`HelpView`, boa decisão), então o risco é baixo, mas usuários novos podem não
achar a aba de ajuda por padrão.
**Sugestão:** nenhuma mudança urgente — já existe uma aba de ajuda dedicada e
bem escrita; talvez vale considerar abrir essa aba automaticamente (ou um
badge "novo") na primeiríssima execução do app, quando `orch.project == nil`.

### 14. Contraste de "trabalhando" (cinza) vs. fundo do card é sutil
`AgentStatus.trabalhando.color` é `(0.63, 0.63, 0.67)` (`main.swift:92`) sobre
`Theme.card` `(0.145, 0.145, 0.16)` — contraste alto o suficiente para
leitura, mas o *pill* de status usa essa mesma cor a 12% de opacidade de fundo
(`main.swift:1289`), tornando o card do status "trabalhando" (o mais comum,
presumivelmente) visualmente o mais "apagado" da paleta de 4 estados — o
oposto do que se quer quando é o estado mais frequente e o que menos precisa
de atenção imediata é o "concluído"/"bloqueado". Isso é provavelmente
intencional (cinza = normal, cores fortes = chamam atenção), mas vale
confirmar que essa hierarquia é a pretendida.
**Sugestão:** nenhuma ação forçada — parece intencional; mencionado para
registro caso o padrão de cores não bata com a intenção original do design.

### 15. Sem suporte a VoiceOver/Dynamic Type além do zoom manual
Não há uso de `accessibilityLabel`/`accessibilityHint` em nenhum componente
custom (`SmallButton`, `TerminalText`, `AgentNode`, etc.) — os `Image(systemName:)`
usados como ícones de botão (ex. `checkmark.seal`, `xmark`,
`note.text`) dependem só do texto do `Text` ao lado para VoiceOver, o que
funciona na maioria dos botões (`SmallButton` sempre combina ícone + texto),
mas os punhos de arrastar/redimensionar dos cards
(`Image(systemName: "line.3.horizontal")`, `main.swift:1257-1277`,
`"arrow.up.left.and.arrow.down.right")`, `main.swift:1402-1423`) não têm
nenhum rótulo — para quem usa VoiceOver, mover/redimensionar um card via
drag gesture provavelmente não é operável de forma alternativa (não há atalho
de teclado equivalente a "resetar posição" além do duplo clique no mouse).
**Sugestão:** adicionar `.accessibilityLabel("mover agente")` /
`"redimensionar agente"` aos dois punhos, e considerar uma ação de teclado
(ex. menu de contexto "resetar posição") como alternativa ao duplo clique,
já que hoje a única forma de resetar um card sem mouse é usar "realinhar"
(que reseta *todos* os cards, não um só).

### 16. Texto do app é 100% em português, sem qualquer preparo para i18n
Todo o texto de UI é português hardcoded inline (não há camada de strings
localizáveis, `String(localized:)`, ou `.strings`/`.xcstrings`). Coerente com
o produto atual (documentado como PT-BR na SPEC/README), mas se o projeto
pretende crescer para além do público brasileiro (o README já está em
inglês, o repo é público no GitHub), a falta de qualquer abstração de string
tornaria uma futura tradução um trabalho de reescrever o arquivo inteiro em
vez de trocar um catálogo de strings.
**Sugestão:** sem ação necessária agora — citado apenas como custo futuro
conhecido, caso i18n vire meta do produto.

---

## Observações de arquitetura de UI (afetam a experiência, não pedem refatoração imediata)

- **Arquivo único de 2724 linhas.** Todo o app — modelo, tema, canvas,
  layout, sheets, ajudas — vive em `main.swift`. Isso não é um problema de
  *usuário final*, mas afeta a experiência indiretamente: qualquer mudança de
  UX (ex. os itens 8 e 10 acima) precisa navegar um arquivo monolítico sem
  fronteiras de módulo, o que aumenta o custo/risco de iterar rápido em
  polish visual — normalmente o tipo de mudança que se faz em lotes pequenos
  e frequentes.
- **Estado de layout (`AgentLayout`) e estado de dados (`Orchestra`) são
  singletons desacoplados por nome de agente (string).** Funciona bem hoje,
  mas cards de agentes renomeados ou removidos e recriados com o mesmo nome
  herdam posição/tamanho salvo do agente antigo (comportamento não
  necessariamente indesejado, mas não documentado em lugar nenhum do app —
  só nos comentários do código-fonte).
- **Polling fixo de 2s (`main.swift:360`) para tudo — pane de terminal, git
  status, notas.** Em projetos com muitos agentes/arquivos, isso significa
  N `git status --porcelain` + N leituras de arquivo de notas + N
  `tmux capture-pane` a cada 2 segundos, todos na mesma thread global
  concorrente. Do ponto de vista de UX isso hoje não aparece como lentidão
  perceptível (o canvas parece "vivo"), mas é o tipo de decisão que, se o
  número de agentes crescer (o próprio app expõe um limite configurável de
  equipe em Ajustes), pode começar a introduzir atraso visível entre a ação
  real do agente e a atualização do card — o que prejudicaria diretamente a
  percepção de "tempo real" que é central à proposta do canvas.

---

## Resumo priorizado

| # | Achado | Área | Impacto |
|---|--------|------|---------|
| 1 | Falha silenciosa de compilação do app no install | Onboarding | Alto |
| 2 | Sem feedback quando `nvo`/tmux não resolvem | Onboarding | Alto |
| 3 | Recuperação de permissão de Automação exige lembrar sozinho | Onboarding/Ajustes | Alto |
| 4 | Cards concluídos não se destacam no canvas | Canvas | Alto |
| 5 | Confirmação por nome sem validação em tempo real | Aprovação de diff | Alto |
| 6 | Passo 3 do onboarding sem StepCard equivalente | Onboarding | Médio |
| 7 | Exemplos de prompt somem para sempre após 1º agente | Descoberta | Médio |
| 8 | Diff sem realce de cor +/- | Aprovação de diff | Médio |
| 9 | "Aprovar" usado para 2 ações de risco muito diferente | Aprovação de diff | Médio |
| 10 | Notas em markdown cru, sem renderização | Canvas | Médio |
| 11 | FileViewer não indica origem do arquivo | Canvas | Médio |
| 12 | Zoom não escala os cards, risco de corte em zoom alto | Acessibilidade | Médio |
| 13 | Informação essencial só em tooltip | Descoberta | Baixo |
| 14 | Contraste do status mais comum é o mais apagado | Feedback visual | Baixo |
| 15 | Sem accessibilityLabel em punhos de drag/resize | Acessibilidade | Baixo |
| 16 | Sem camada de i18n | Consistência | Baixo |
