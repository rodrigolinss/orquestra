<p align="center">
  <a href="https://nevoaai.com/?utm_source=orquestra&utm_medium=readme&utm_campaign=opensource_orchestrator">
    <img src="docs/logo.png" width="110" alt="Orquestra">
  </a>
</p>

<h1 align="center">Orquestra</h1>

<p align="center">
  <strong>Rode um time de agentes de IA na sua máquina — isolados, supervisionados e seguros por construção.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/plataforma-macOS%20%C2%B7%20Linux%20%C2%B7%20Windows%20(WSL2)-black" alt="Plataformas">
  <img src="https://img.shields.io/badge/agentes-Claude%20Code%20%C2%B7%20Codex-CCFF00" alt="Agentes">
  <img src="https://img.shields.io/badge/licen%C3%A7a-MIT-blue" alt="MIT">
  <img src="https://img.shields.io/badge/feito%20com-SwiftUI%20%2B%20Bash-orange" alt="Stack">
</p>

<p align="center">
  <a href="#instalação">Instalação</a> ·
  <a href="#por-que-orquestra">Por que</a> ·
  <a href="#uso">Uso</a> ·
  <a href="#modelo-de-segurança">Segurança</a> ·
  <a href="#arquitetura">Arquitetura</a>
</p>

---

O Orquestra transforma sua máquina em um time de engenharia de IA supervisionado. Um agente **maestro** recebe suas instruções em linguagem natural e recruta agentes trabalhadores — cada um trancado dentro do próprio git worktree e da própria branch, vigiado por um firewall determinístico de comandos, e integrado de volta **apenas** com a sua aprovação explícita.

Sem ficar copiando e colando entre terminais. Sem nenhum agente encostando na sua branch principal. Sem momentos "ops".

```
                    ┌─────────────┐
                    │   MAESTRO   │  ← você fala com ele em linguagem natural
                    └──────┬──────┘
             ┌─────────────┼─────────────┐
        ┌────┴────┐   ┌────┴────┐   ┌────┴────┐
        │ builder │   │reviewer │   │  docs   │  ← cada um no seu worktree,
        └─────────┘   └─────────┘   └─────────┘     branch agent/<nome>
                 notas compartilhadas = protocolo de progresso
```

## Por que Orquestra

Rodar 3–4 agentes de IA em terminais soltos transforma você num roteador de copy-paste. O Orquestra resolve isso com três decisões de arquitetura:

| | Decisão | Resultado |
|---|---|---|
| 🗂 | **O isolamento mora no sistema de arquivos, não no prompt** | Cada agente só enxerga o próprio worktree. Um agente confuso não consegue quebrar o trabalho de outro — nem a sua branch principal. |
| 🛡 | **Barreiras determinísticas** | Um hook `PreToolUse` bloqueia comandos destrutivos *antes* que eles rodem. Não depende do modelo estar num dia bom. |
| ✍️ | **Integrar é decisão humana** | No app, aprovar é um clique deliberado em "aplicar no projeto" no card do agente, sempre com o diff visível. No terminal, `nvo done` pede o nome exato do agente. Não existe merge automático. Nunca. |

## Recursos

- **App nativo para macOS** — canvas visual com o maestro no topo e os cards dos agentes conectados abaixo dele. Status, saída do terminal, notas e diffs num relance. *No Linux e no Windows/WSL2 a interface é a CLI, que faz tudo o que o app faz.*
- **Funciona com Claude Code e Codex** — escolha o harness por agente. Times mistos (builder no Claude + reviewer no Codex) funcionam de imediato.
- **Instalação sem credenciais** — o instalador detecta o que você já tem. Claude/Codex já logados? Git já configurado? O Orquestra simplesmente aproveita.
- **Pronto para GitHub** — abra uma pasta local ou cole `usuario/repo` e o Orquestra clona e registra. Repositórios privados funcionam com suas credenciais git existentes.
- **Protocolo de notas compartilhadas** — os agentes reportam progresso, decisões e bloqueios em notas markdown. Quando um escreve `STATUS: CONCLUIDO` ou `BLOQUEADO`, o estado muda no `nvo ls` — e no macOS chega também uma notificação do sistema.
- **Inspetor de arquivos embutido** (app do macOS) — uma barra lateral opcional (fechada por padrão) para navegar pelo worktree de qualquer agente e inspecionar arquivos modificados recentemente sem sair do app.
- **Medição de tokens ao vivo** — uma faixa de status mostra a janela de sessão de 5 horas atual (tokens, valor equivalente em API, horário de reset), o total do dia e a distribuição por modelo. Também disponível como `nvo usage`.
- **Escolha de modelo por agente** — rode trabalhadores em Sonnet ou Haiku por uma fração do custo do Opus, direto no diálogo de novo agente ou com `nvo new <nome> "<tarefa>" claude sonnet`.
- **Nada para babá** — sem daemon, sem banco de dados. O estado é o sistema de arquivos; mate o tmux e nada se perde.

## Instalação

**Requisitos:** pelo menos uma CLI de agente ([Claude Code](https://docs.anthropic.com/en/docs/claude-code) ou [Codex](https://github.com/openai/codex)) instalada e logada, mais `git`, `tmux` e `jq` (o instalador cuida dos dois últimos). As CLIs de agente precisam de **Node.js** — no macOS ele costuma já estar lá; no Ubuntu do WSL2, não vem, e o [passo 3](#3-instalar-o-nodejs) resolve.

| Plataforma | Interface | Observação |
|---|---|---|
| **macOS** | App nativo + CLI | Requer [Homebrew](https://brew.sh); o app compila se as Xcode Command Line Tools estiverem presentes |
| **Linux** | CLI | Detecta `apt`, `dnf` ou `pacman` |
| **Windows** | CLI, via **WSL2** | Não roda no Windows nativo. O [passo a passo completo](#windows-passo-a-passo-completo) está logo abaixo — siga por ele, não pelos dois comandos acima |

No macOS e no Linux:

```bash
git clone https://github.com/rodrigolinss/orquestra.git ~/orquestra
cd ~/orquestra && ./install.sh
```

### Windows — passo a passo completo

O motor do Orquestra é bash + git + tmux, então ele roda **dentro do WSL2**, não no Windows nativo. Não existe PowerShell aqui: depois do passo 1, tudo acontece no terminal do Ubuntu.

**O que você tem no Windows:** a CLI completa. **O que você não tem:** o app visual (ele é SwiftUI, exclusivo da Apple) e as notificações do sistema. O acompanhamento é pelo `nvo ls` e pelo `nvo attach`.

#### 1. Instalar o WSL2

No **PowerShell como administrador**:

```powershell
wsl --install
```

Reinicie o computador. Ao voltar, o Ubuntu abre sozinho e pede para você **criar um usuário e uma senha do Linux** — são novos, não têm relação com a conta do Windows. Guarde a senha: ela é pedida em todo `sudo`.

Daqui em diante, todos os comandos são no terminal do Ubuntu (procure por "Ubuntu" no menu Iniciar).

#### 2. Instalar as dependências

```bash
sudo apt-get update
sudo apt-get install -y git tmux jq curl
```

#### 3. Instalar o Node.js

O Ubuntu do WSL **vem sem Node**, e sem ele o passo 4 falha com `npm: command not found`:

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs
node --version    # confirme que respondeu algo como v22.x
```

#### 4. Instalar o Claude Code dentro do WSL

```bash
npm install -g @anthropic-ai/claude-code
claude          # faça login uma vez; abre o navegador do Windows
```

> **A pegadinha que mais derruba gente:** o WSL enxerga o `PATH` do Windows. Se você já tem o Claude Code instalado no Windows, o `claude.exe` dele aparece no terminal do Ubuntu e é encontrado primeiro — mas ele não entende caminhos `/home/...` e quebra de formas difíceis de entender. Instale a versão do Linux, aqui dentro. O `nvo doctor` detecta esse caso e avisa qual programa está vindo do lado errado.

#### 5. Instalar o Orquestra

```bash
git clone https://github.com/rodrigolinss/orquestra.git ~/orquestra
cd ~/orquestra && ./install.sh
source ~/.bashrc      # ou abra um terminal novo
nvo doctor            # deve terminar com "pronto para orquestrar."
```

#### 6. Onde deixar os seus projetos

**Deixe os projetos dentro do Linux (`~/projetos/...`), não em `/mnt/c/...`.** O Orquestra cria uma cópia de trabalho isolada por agente (git worktree), e no disco do Windows visto pelo WSL isso fica lento a ponto de atrapalhar, além de embaralhar permissões de arquivo.

Se o seu código já está no Windows, clone de novo do lado do Linux:

```bash
mkdir -p ~/projetos && cd ~/projetos
git clone <url-do-seu-repo>
nvo init ~/projetos/<seu-repo>
```

Para abrir esses arquivos no VS Code do Windows, use a extensão **WSL** e o comando `code .` de dentro do Ubuntu — ele abre a janela do Windows editando os arquivos do Linux, sem a perda de desempenho.

#### 7. O dia a dia sem o app

```bash
nvo maestro                          # o chefe: fale com ele em português
nvo ls                               # status de todos os agentes, colorido
nvo attach                           # entra na visão ao vivo (tmux)
nvo diff <nome>                      # o que o agente mudou
nvo done <nome>                      # aprova: pede o nome digitado e faz o merge
```

Duas teclas do tmux que você vai usar: **`Ctrl-b` depois `d`** sai da visão ao vivo sem matar nada, e **`Ctrl-b` depois `n`** passa para a próxima janela. Fechar o terminal também não mata os agentes — eles seguem rodando, e o `nvo ls` mostra o estado quando você voltar.

Se a máquina reiniciar ou o terminal cair, `nvo religar --todos` recria as janelas e manda cada agente continuar de onde parou.

O diagnóstico no Windows termina assim (sem a linha do app, que é só do macOS):

```
nvo doctor — diagnostico do ambiente
  ✓ plataforma: Windows via WSL2 (Ubuntu)
  ✓ tmux 3.4
  ✓ git 2.43 · identidade configurada
  ✓ Claude Code instalado
  ✓ hook de seguranca configurado
pronto para orquestrar.
```

O instalador é idempotente e só preenche as lacunas: instala `tmux`/`jq` se faltarem, conecta o hook de segurança, adiciona a CLI ao seu `PATH` e compila o app nativo quando as Xcode Command Line Tools estão presentes. Ao final, faz um diagnóstico completo do ambiente:

```
nvo doctor — verificação do ambiente
  ✓ tmux 3.7b
  ✓ git 2.50 · identidade configurada
  ✓ Claude Code instalado — o login existente será usado
  ✓ Codex CLI instalado
  ✓ hook de segurança configurado
  ✓ Orquestra.app instalado
pronto para orquestrar.
```

## Uso

### O app (macOS)

No Linux e no Windows/WSL2, pule para [A CLI](#a-cli) — ela cobre todo o fluxo.

Abra o **Orquestra** (Spotlight → "Orquestra"). Escolha um projeto — uma pasta local ou um repositório do GitHub — depois inicie o maestro e diga o que você quer:

> *"cria um agente builder pra implementar o webhook de pagamento do docs/webhook.md, e um reviewer pra auditar. Me avisa quando os dois terminarem."*

Cada agente aparece como um card ao vivo conectado ao maestro: status, saída do terminal, campo de prompt direto, notas e diff. Quando um agente termina ou trava, o macOS te notifica e um aviso aparece no painel. Aprovar é um clique no próprio card — ver o diff e apertar "aplicar no projeto"; o merge acontece ali, sem precisar abrir o terminal.

### A CLI

No macOS a aprovação padrão é o clique no app. A CLI cobre isso e todo o resto, de forma scriptável — e é a interface completa no Linux e no Windows/WSL2:

```bash
nvo init ~/projetos/minha-api         # registra o projeto ativo
nvo maestro                           # abre o maestro no projeto, com briefing
nvo new builder "implementa X"        # branch + worktree + janela tmux + agente
nvo new reviewer "audita isso" codex  # o mesmo, mas rodando no Codex
nvo new --plan big "refatora Y"       # agente planeja e espera aprovação
nvo approve big                       # libera o plano para execução
nvo ls                                # visão geral com status colorido
nvo read builder 60                   # espia a tela de um agente, sem interferir
nvo send builder "prioriza o retry"   # envia um prompt
nvo note builder                      # lê as notas de progresso dele
nvo diff builder                      # revisa o trabalho contra a branch base
nvo explain builder                   # resume o diff em português simples (harness barato)
nvo check builder                     # roda os testes do projeto na cópia do agente
nvo collisions                        # avisa quais agentes vivos mexem no mesmo arquivo
nvo status builder                    # situação do check e das colisões, em chave=valor
nvo done builder                      # diff → nome digitado → merge --no-ff (alternativa ao clique no app)
nvo kill reviewer                     # descarta sem merge (a branch é preservada)
nvo attach                            # acompanha tudo ao vivo no tmux
nvo clear maestro                     # o maestro esquece a conversa (economiza muito token)
nvo religar --todos                   # terminal caiu? recria as janelas e retoma o contexto
nvo projects                          # projetos já usados e quantos agentes vivos em cada
nvo limpar                            # recomeço: maestro novo, quadro em branco, notas arquivadas
nvo stop                              # encerra a sessão, preservando o trabalho
nvo doctor                            # diagnóstico do ambiente
nvo usage                             # consumo de tokens: janela de 5h, dia, modelos
```

Vários projetos ao mesmo tempo funcionam: cada um tem a própria sessão tmux, os próprios agentes e as próprias notas, sem se enxergarem. No terminal, `NVO_PROJECT=/caminho/do/projeto nvo <comando>` opera num projeto sem trocar o ativo; no app do macOS, ⌘N abre outra aba já pedindo a pasta.

### Plano antes de executar

Para tarefas grandes ou ambíguas, `--plan` (ou a caixa "pedir plano" no app) faz o agente parar antes de escrever código:

```bash
nvo new --plan refactor "reorganiza o módulo de cobrança"
# o agente investiga, escreve o plano nas notas e marca STATUS: AGUARDANDO APROVACAO
nvo note refactor      # você lê o que ele pretende fazer
nvo approve refactor   # aprovado → ele executa
```

É o maior economizador de tokens do sistema: barato descobrir que o entendimento estava errado **antes** de implementar. Os agentes também são instruídos a parar e perguntar (`BLOQUEADO: <pergunta>` nas notas) em vez de adivinhar quando uma dúvida muda o resultado do trabalho — e a não inventar features, refatorações ou abstrações fora do escopo pedido.

### Eficiência de tokens

O Orquestra é desenhado para manter a supervisão barata e o gasto visível:

1. **Meça antes** — a faixa de uso (ou `nvo usage`) mostra a janela de 5 horas e o horário de reset, então você sabe sua folga antes de lançar um time.
2. **Dimensione o modelo** — builders e reviewers raramente precisam do modelo topo de linha. O Sonnet entrega a maior parte das tarefas de código a ~40% do custo do Opus; o Haiku dá conta do trabalho mecânico a ~20%.
3. **Tarefas fechadas gastam menos** — uma tarefa delimitada ("implementa X conforme docs/x.md, com testes") termina com muito menos tokens do que uma aberta ("melhora o backend").
4. **Notas em vez de telas** — o maestro lê as notas dos agentes em vez de reler o scrollback do terminal, mantendo o próprio contexto pequeno.

## Modelo de segurança

O Orquestra parte do princípio de que os agentes *vão* se comportar mal em algum momento, e torna isso sobrevivível:

| Camada | Como é imposta |
|---|---|
| **Isolamento por worktree** | Agentes nunca rodam na branch principal. Worktrees fora de `~/orquestra/worktrees` são rejeitados. |
| **Firewall de comandos** (`guard.sh`) | Bloqueia antes da execução: `rm -rf` em caminhos absolutos/home, `sudo`, `git push`, `git reset --hard`, checkout/switch para main/master, pipes `curl\|sh`, `chmod 777`, e qualquer acesso a `.env*`, `*.pem`, `id_rsa`, `~/.ssh`, `~/.aws`. |
| **Merge com trava humana** | A aprovação vive no app: card do agente → diff → clique deliberado em "aplicar no projeto". Quem prefere terminal usa `nvo done`, que exige digitar o nome exato do agente. Nunca há merge sem o diff visível primeiro. |
| **Permissões padrão** | Os prompts de permissão dos agentes nunca são contornados. `--dangerously-skip-permissions` não é usado em lugar nenhum do código. |

O hook do firewall é distribuído automaticamente para todo worktree (como `.claude/settings.local.json`, ignorado pelo git), então os agentes carregam suas barreiras junto.

**Privacidade:** o repositório versiona apenas código. Seus worktrees, notas, repositórios clonados e o registro de projeto são excluídos pelo `.gitignore` e nunca saem da sua máquina.

## Arquitetura

```
~/orquestra/
├── bin/nvo                  CLI — a única fonte de ação (bash, multiplataforma)
├── bin/guard.sh             firewall determinístico de comandos (hook PreToolUse)
├── bin/platform.sh          detecção de macOS / Linux / WSL2
├── bin/nvo-usage.py         medidor de tokens (lê os transcritos do Claude Code)
├── app/main.swift           app nativo de macOS (SwiftUI, arquivo único)
├── app/build.sh             recompilação em um comando
├── .claude/settings.json    hook de segurança do maestro
├── install.sh               instalador idempotente com detecção de ambiente
└── runtime (ignorado pelo git)
    ├── worktrees/<projeto>/<agente>/   cópia de trabalho isolada por agente
    ├── notes/<projeto>/<agente>.md     protocolo de progresso
    └── repos/                          clones do GitHub
```

**Princípios de design**

1. **A CLI é a única fonte de ação.** Todo botão do app chama o `nvo` — não existe um segundo caminho de código para auditar.
2. **As notas são o protocolo.** Os agentes escrevem progresso estruturado em markdown; status, notificações e supervisão derivam disso.
3. **O estado é o sistema de arquivos.** Sem daemon, sem banco, sem lock-in. Tudo é inspecionável com `ls` e `git`.

## Desenvolvimento

```bash
bash app/build.sh                        # recompila o app após editar o main.swift
NVO_AGENT_CMD=bash nvo new t "..."       # sobe um shell comum em vez de um agente (teste)
swift app/gen_icon.swift out.png         # regenera os arquivos do ícone
```

## Licença

[MIT](LICENSE) © 2026 [Nevoa AI](https://nevoaai.com/?utm_source=orquestra&utm_medium=readme&utm_campaign=opensource_orchestrator)

<p align="center">
  <a href="https://nevoaai.com/?utm_source=orquestra&utm_medium=readme_footer&utm_campaign=opensource_orchestrator">
    <img src="https://img.shields.io/badge/powered%20by-nevoaai.com-CCFF00?labelColor=09090B" alt="powered by nevoaai.com">
  </a>
</p>
