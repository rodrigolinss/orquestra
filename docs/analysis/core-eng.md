# Análise do motor do Orquestra (bin/, install.sh, config.conf)

Escopo revisado: `bin/nvo`, `bin/guard.sh`, `bin/platform.sh`, `bin/harnesses.conf`,
`bin/nvo-usage.py`, `install.sh`, `config.conf`. Não existe diretório `agents/`
no repositório (o `agents/` citado na tarefa é criado em runtime dentro de
`~/orquestra/agents/`, não faz parte do código-fonte) — nada a analisar ali
além do que já é coberto pelo uso que `bin/nvo` faz dele.

Esta é uma análise somente; nenhum código foi alterado.

---

## Alto impacto

### 1. Race condition (TOCTOU) nos limites de hierarquia em `nvo new`
**bin/nvo:270-291**

`cmd_new` conta `filhos` (via `grep -l` nos `.meta`) e `vivos` (via `ls *.meta`),
valida contra `NVO_MAX_FANOUT`/`NVO_MAX_AGENTS`, e só bem mais adiante (linha
308-310) escreve o `.meta` do novo agente. Entre a contagem e a escrita não há
nenhum lock. Se o maestro (ou um agente-pai) disparar duas chamadas de
`nvo new` em paralelo — cenário real, já que o próprio fluxo incentiva criar
"builder" e "reviewer" quase juntos — as duas leem a mesma contagem antiga e
ambas passam na checagem, estourando `max_fanout`/`max_agents` silenciosamente.
**Sugestão:** usar um lock de arquivo simples (`mkdir` atômico ou `flock` via
`bin/flock`/`shlock`) em `$META_ROOT/$PROJ/.lock` envolvendo contagem +
escrita do `.meta`, ou aceitar a criação e falhar/reverter se, ao term inar,
a contagem pós-escrita excedeu o limite (compensação em vez de exclusão mútua).

### 2. `guard.sh` — bypass do bloqueio de `git push`, `reset --hard` e `checkout main`
**bin/guard.sh:35, 39, 43**

Os três regexes assumem que qualquer flag antes do subcomando é de token único
(`(\s+-[^ ]+)*`). Uma flag com argumento separado — `-C <dir>`,
`--git-dir=<dir>` não é o problema (tem `=`), mas `-C <dir>` sim — quebra o
casamento porque o token seguinte (`<dir>`) não é nem `-algo` nem o
subcomando esperado:
```
git -C /tmp/outro-repo push origin main     # NÃO bloqueado
git -C /tmp/outro-repo reset --hard HEAD~1  # NÃO bloqueado
git -C /tmp/outro-repo checkout main        # NÃO bloqueado
```
Isso é exatamente o tipo de comando que um agente confuso (ou um prompt
injection vindo de conteúdo do repositório) tentaria para escapar do próprio
worktree. **Sugestão:** normalizar o comando antes de casar — extrair o
subcomando git de forma mais robusta (ex.: `git help -a`-style parse, ou pelo
menos permitir explicitamente `-C ARG`/`--git-dir=ARG`/`--work-tree=ARG` no
padrão de flags) em vez de assumir só flags de token único.

### 3. `guard.sh` — bypass do bloqueio de `rm -rf`
**bin/guard.sh:22-28**

O bloqueio exige, na mesma invocação de `rm`, uma flag com `r`, uma com `f` e
um caminho absoluto/`~`/`$HOME` **literal** na linha de comando. Três formas
triviais de escapar:
- `rm --recursive --force /` (flags longas, o regex só casa `-[A-Za-z]*`)
- `cd / && rm -rf *` (o caminho perigoso não está na invocação do `rm`)
- `p=$HOME; rm -rf "$p"` (indireção por variável — a checagem é textual, não
  avalia o shell)

Isso é uma limitação estrutural de guard por regex, não um bug isolado, mas
vale registrar porque o comentário do arquivo ("camada deterministica") pode
passar confiança maior do que o mecanismo garante. **Sugestão:** documentar
explicitamente as limitações conhecidas no cabeçalho do arquivo (para não
criar falsa sensação de segurança), e cobrir pelo menos as flags longas
(`--recursive`, `--force`) e `cd <perigoso> && rm -rf`/`rm -rf *` como
padrões adicionais.

### 4. Nome de agente reservado colide com a janela `maestro`
**bin/nvo:180-183 (`check_name`), bin/nvo:389 (`tmux new-window ... -n "$name"`)**

`check_name` só valida o charset (`^[A-Za-z0-9_-]+$`), não impede nomes
reservados. Rodar `nvo new maestro "..."` cria uma segunda janela tmux
chamada `maestro` na mesma sessão. tmux permite nomes de janela duplicados
(são endereçados por índice internamente), então a partir daí
`tmux send-keys -t "$SESSION:maestro"` (usado em `cmd_maestro`, linha 502, e
em `cmd_send`/`cmd_read` para esse "agente") passa a ser ambíguo e pode
atingir a janela errada — quebrando silenciosamente a comunicação com o
maestro real. **Sugestão:** em `check_name`, recusar explicitamente o nome
`maestro` (e qualquer outro nome reservado usado como janela/sessão fixa).

### 5. Sem rollback em falha parcial de `nvo new`
**bin/nvo:305-397**

A sequência é: `git worktree add` (306) → grava `.meta` (309) → grava nota
(312-313) → `install_guard_local` (316, que pode falhar silenciosamente,
tem `return 0` em vários pontos) → grava `.prompt` (319-386) → `tmux
new-window` (389) → `tmux send-keys` (397). Se o script for interrompido
(Ctrl-C, falha de disco, sessão tmux quebrada) entre a criação do worktree e
a escrita do `.meta`, o resultado é um worktree e uma branch `agent/<nome>`
que existem em disco, `agent_exists` retorna verdadeiro (linha 224, só
checa o diretório), mas `nvo diff`/`nvo done`/`nvo kill` falham em
`get_base` (linha 587-591, "metadados... nao encontrados") sem indicar como
recuperar. **Sugestão:** ou envolver os passos em um `trap` que remove o
worktree/branch se o script sair antes de completar, ou pelo menos detectar
em `cmd_ls`/`agent_exists` o caso "worktree sem `.meta`" e orientar o comando
de limpeza manual (`git worktree remove --force` + `git branch -D`).

---

## Médio impacto

### 6. `nvo-usage.py` reprocessa todos os transcritos do zero a cada chamada
**bin/nvo-usage.py:62-97**

`collect()` é chamado do zero em toda invocação (o app nativo chama isso a
cada 30s via `usageTimer`, `app/main.swift:363`/370). Para cada arquivo
`.jsonl` modificado nas últimas 36h, o script lê e faz `json.loads` linha a
linha, mesmo que a maior parte do arquivo já tenha sido processada na
chamada anterior. Em sessões longas (transcritos de dezenas de MB, comuns em
uso pesado de Claude Code) isso é uma janela de I/O e CPU redundante
recorrente. **Sugestão:** cache incremental por arquivo, guardando
(mtime, offset de bytes já lidos) num arquivo de estado, e só relendo o
que mudou; ou pelo menos aumentar o intervalo de poll no chamador.

### 7. Validação de harness/modelo duplicada entre `cmd_new` e `cmd_maestro`
**bin/nvo:255-266 vs bin/nvo:429-436**

As duas funções repetem quase literalmente: `harness_exists` → `harness_field
... 3` (binário) → `command -v "$hbin"` com a mesma mensagem de erro →
validação do modelo com o mesmo regex `^[A-Za-z0-9._/-]+$`. Qualquer ajuste
futuro (por exemplo, mudar a mensagem de erro ou adicionar um novo tipo de
validação) precisa ser replicado nos dois lugares — já aconteceria de
divergir despercebido. **Sugestão:** extrair uma função
`resolve_harness_bin <cli>` (existência + binário instalado) e
`validate_model <valor>`, usadas nas duas funções.

### 8. Escrita de `config.conf` não é atômica sob concorrência
**bin/nvo:87-93**

`cmd_config` escreve sempre no mesmo nome fixo `"$CONFIG.tmp"`. Duas
chamadas simultâneas de `nvo config` (ex.: humano ajustando pelo app
enquanto o maestro também tenta configurar) podem se sobrepor: ambas leem o
arquivo, ambas escrevem `$CONFIG.tmp`, e o `mv` de uma pode sobrescrever o
resultado da outra ou operar sobre um arquivo truncado pela outra escrita
concorrente. Impacto é baixo em frequência mas o arquivo é lido por toda
invocação de `nvo` (via `config_get`, linha 43-45) então uma corrupção afeta
todo comando subsequente. **Sugestão:** usar um nome de temporário único
(`mktemp` ou `$CONFIG.tmp.$$`) e, se quiser mutex real, um lock com
`mkdir` atômico como no achado #1.

### 9. Caminho `~/orquestra` hardcoded em múltiplos arquivos, sem variável de override
**bin/nvo:8, install.sh:7**

`ORQ="$HOME/orquestra"` aparece fixo em `bin/nvo` e em `install.sh`
(independentemente um do outro — não há uma fonte única). Não há suporte a
`$XDG_DATA_HOME` nem a uma variável de ambiente para relocar a instalação
(útil para testes, múltiplas instalações, ou usuários que já têm
`~/orquestra` ocupado por outra coisa). **Sugestão:**
`ORQ="${ORQ:-$HOME/orquestra}"` nos dois arquivos, permitindo override por
ambiente sem mudar comportamento padrão.

### 10. Lógica de dependências em `install.sh` é difícil de ler e tem numeração de comentário duplicada
**install.sh:35-46, 48**

O bloco de checagem de `tmux`/`jq` (35-46) usa uma dupla negação confusa —
`[ "$ORQ_PKG" = "apt" ] && cmd1 && cmd2 || { [ "$ORQ_PKG" = "apt" ] && ... ||
true; }` — que na prática só executa `apt-get update` quando `ORQ_PKG=apt` E
falta uma das duas dependências, mas isso exige reler o comando duas vezes
para confirmar. Além disso os comentários `# 3. dependencias` (linha 35) e
`# 3. permissoes e diretorios de runtime` (linha 48) usam o mesmo número —
resquício de edição anterior, deixa a numeração da lista de passos
inconsistente daí em diante (pula de 3 para 3, depois 4, 5, 6, 7).
**Sugestão:** reescrever como
```sh
if [ "$ORQ_PKG" = "apt" ] && { ! command -v tmux >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; }; then
  sudo apt-get update -qq || true
fi
```
e renumerar os comentários sequencialmente.

---

## Baixo impacto

### 11. Limpeza de `.meta`/`.prompt` duplicada entre `cmd_done` e `cmd_kill`
**bin/nvo:656 vs bin/nvo:695**

`rm -f "$(meta_path "$name").meta" "$(meta_path "$name").prompt"` aparece
idêntico nas duas funções. **Sugestão:** extrair `cleanup_meta <name>`.

### 12. Linha morta / no-op em `cmd_new`
**bin/nvo:303**

```sh
[ "$base" = "main" ] || [ "$base" = "master" ] || true  # base pode ser qualquer branch
```
Por causa do `|| true` final, essa linha sempre retorna sucesso
independentemente do valor de `$base` — não faz nada além de ocupar espaço
e confundir quem lê (parece uma validação, mas não valida nada).
**Sugestão:** remover a linha; o comentário sozinho já documenta a decisão
("base pode ser qualquer branch").

### 13. Bloco de `IFS read` duplicado dentro de `cmd_config`
**bin/nvo:64-66 vs bin/nvo:80-82**

O padrão
```sh
IFS='|' read -r min max rotulo ajuda <<EOF
$spec
EOF
```
aparece duas vezes dentro da mesma função (uma no branch de listagem, outra
no branch de escrita). **Sugestão:** extrair uma função
`parse_spec <chave>` que já retorna as quatro variáveis (ex.: via `eval` de
um `printf` seguro, ou reatribuindo globais fixas), eliminando a repetição.

### 14. `cmd_ls` dispara vários subprocessos por agente a cada chamada
**bin/nvo:519-557**

Para cada agente, `cmd_ls` roda `git branch --show-current`, `git status
--porcelain | wc -l`, `agent_status` (que lê o arquivo de notas) e `tmux
capture-pane` — quatro operações externas por agente, sem cache. Com o
limite atual de `max_agents=12` (config.conf:1) o custo é aceitável, mas se
esse teto for aumentado (o app permite até 24, `bin/nvo:52`) o tempo de
`nvo ls`/o polling do app escala linearmente e pode ficar perceptível.
**Sugestão:** não é urgente agora, mas vale considerar paralelizar as
chamadas de `git` (elas são independentes por diretório) se o teto de
agentes subir na prática.

---

## Resumo

| # | Achado | Impacto | Arquivo:linha |
|---|--------|---------|----------------|
| 1 | Race condition nos limites de hierarquia (fanout/agentes vivos) | Alto | bin/nvo:270-291 |
| 2 | `guard.sh` bypass de push/reset --hard/checkout via flag com argumento separado | Alto | bin/guard.sh:35,39,43 |
| 3 | `guard.sh` bypass de `rm -rf` (flags longas, indireção, `cd` prévio) | Alto | bin/guard.sh:22-28 |
| 4 | Nome de agente `maestro` colide com a janela tmux do maestro | Alto | bin/nvo:180-183, 389 |
| 5 | Sem rollback em falha parcial de `nvo new` (worktree órfão) | Alto | bin/nvo:305-397 |
| 6 | `nvo-usage.py` reprocessa transcritos inteiros a cada chamada | Médio | bin/nvo-usage.py:62-97 |
| 7 | Validação de harness/modelo duplicada (`cmd_new`/`cmd_maestro`) | Médio | bin/nvo:255-266, 429-436 |
| 8 | Escrita de `config.conf` não atômica sob concorrência | Médio | bin/nvo:87-93 |
| 9 | `~/orquestra` hardcoded sem variável de override | Médio | bin/nvo:8, install.sh:7 |
| 10 | Lógica confusa + numeração de comentário duplicada em `install.sh` | Médio | install.sh:35-46, 48 |
| 11 | Limpeza de `.meta`/`.prompt` duplicada | Baixo | bin/nvo:656, 695 |
| 12 | Linha morta/no-op em `cmd_new` | Baixo | bin/nvo:303 |
| 13 | Bloco `IFS read` duplicado em `cmd_config` | Baixo | bin/nvo:64-66, 80-82 |
| 14 | `cmd_ls` sem cache/paralelismo entre subprocessos | Baixo | bin/nvo:519-557 |

Nenhum problema de portabilidade macOS/Linux/WSL2 foi encontrado além dos já
tratados corretamente no código (detecção de WSL via `/proc/version`, `sed -i`
portátil via arquivo temporário, `wc -l | tr -d ' '` para BSD `wc`, gate do
app nativo só em macOS). O ponto de atenção real de portabilidade é o #9
(caminho fixo), que é mais uma limitação de configuração do que um bug
cross-platform.
