# Orquestrador local de agentes (nvo)

## Objetivo
CLI em bash chamada `nvo`, em ~/orquestra/bin/nvo, que gerencia varios
agentes Claude Code em paralelo dentro de uma sessao tmux chamada
"orquestra", cada agente isolado em seu proprio git worktree e branch.

## Comandos
nvo init <caminho-do-repo>   registra o projeto ativo
nvo new <nome> "<tarefa>"    cria branch agent/<nome>, worktree em
                             ~/orquestra/worktrees/<projeto>/<nome>,
                             abre janela tmux e inicia o claude ali com
                             o prompt inicial da tarefa
nvo ls                       lista agentes, branch, status git e as
                             ultimas 3 linhas da tela de cada um
nvo read <nome> [n]          tmux capture-pane, sem interromper o agente
nvo send <nome> "<texto>"    tmux send-keys, envia prompt ao agente
nvo note <nome>              imprime notes/<projeto>/<nome>.md
nvo diff <nome>              git diff da branch do agente contra a base
nvo done <nome>              mostra o diff, exige confirmacao digitando o
                             nome, so entao faz merge --no-ff e remove
                             o worktree
nvo kill <nome>              encerra a janela e remove o worktree SEM merge
nvo attach                   tmux attach -t orquestra

## Regras de seguranca, obrigatorias
1. Nenhum agente roda na branch principal. Sempre worktree + branch agent/<nome>.
2. Nunca usar --dangerously-skip-permissions em nenhum ponto.
3. Criar ~/orquestra/.claude/settings.json com hook PreToolUse no matcher
   Bash apontando para ~/orquestra/bin/guard.sh
4. guard.sh bloqueia com exit 2 e mensagem no stderr: rm -rf em caminho
   absoluto ou ~, sudo, git push, git reset --hard, git checkout ou switch
   para main ou master, curl ou wget com pipe para sh ou bash, chmod 777,
   e qualquer acesso a .env, .env.*, *.pem, id_rsa, ~/.ssh, ~/.aws
5. O agente orquestrador nunca edita codigo. Ele so usa nvo new, read,
   send e note.
6. nvo done nunca faz merge automatico.
7. Worktree fora de ~/orquestra/worktrees e recusado.

## Notas compartilhadas
Cada agente recebe no prompt inicial a instrucao de registrar progresso,
decisoes e bloqueios em notes/<projeto>/<nome>.md ao fim de cada etapa.
O orquestrador le as notas em vez de ler a tela dos agentes.

## Entregaveis
- ~/orquestra/bin/nvo e ~/orquestra/bin/guard.sh, executaveis
- ~/orquestra/.claude/settings.json com o hook
- ~/orquestra/README.md com o fluxo de uso
- adicionar ~/orquestra/bin ao PATH no ~/.zshrc
- testar ponta a ponta criando dois agentes em um repo de teste e
  destruindo depois
