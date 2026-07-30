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
nvo explain <nome>           resume o diff e as notas em portugues simples,
                             via harness barato (ex.: haiku)
nvo check <nome> [segundos]  roda o comando de teste do projeto (detectado ou
                             config.conf 'verify') dentro do worktree do
                             agente; nunca bloqueia aprovacao, so registra
                             evidencia no .meta
nvo collisions               lista pares de agentes vivos que alteraram o
                             mesmo arquivo; aviso, nunca bloqueio
nvo status <nome>            saida chave=valor com o resultado do ultimo
                             check e as colisoes do agente, para a interface
                             grafica consumir
nvo done <nome>              mostra o diff, exige confirmacao, so entao faz
                             merge --no-ff e remove o worktree. Caminho
                             padrao: o app, com um clique em "aplicar no
                             projeto" no card do agente. Alternativa: o
                             terminal, digitando o nome do agente.
        [--confirm <nome>]   recebe a confirmacao por argumento, para que a
                             interface grafica do app passe o nome sozinha
                             apos o clique; o valor tem de bater com o nome
                             do agente
nvo kill <nome>              encerra a janela e remove o worktree SEM merge
nvo attach                   tmux attach -t orquestra
nvo stop [--keep-project]    encerra a sessao (maestro e agentes) preservando
                             worktrees, branches e notas

## Regras de seguranca, obrigatorias
1. Nenhum agente roda na branch principal. Sempre worktree + branch agent/<nome>.
2. Nunca usar --dangerously-skip-permissions em nenhum ponto.
3. Criar ~/orquestra/.claude/settings.json com hook PreToolUse no matcher
   Bash apontando para ~/orquestra/bin/guard.sh
4. guard.sh bloqueia com exit 2 e mensagem no stderr: rm -rf em caminho
   absoluto ou ~, sudo, git push, git reset --hard, git checkout ou switch
   para main ou master, curl ou wget com pipe para sh ou bash, chmod 777,
   e qualquer acesso a .env, .env.*, *.pem, id_rsa, ~/.ssh, ~/.aws
5. O agente orquestrador nunca edita codigo. Ele so usa nvo new, ls, read,
   send, note, diff e approve — nunca nvo done nem nvo kill.
6. nvo done nunca faz merge automatico; a decisao e sempre humana e sempre
   depois de ver o diff. Caminho padrao: o app, onde a confirmacao e um
   clique deliberado em "aplicar no projeto" no card do agente — digitar o
   nome ali nao acrescentava seguranca, so atrito, entao a interface grafica
   passa o nome sozinha via --confirm. Alternativa: o terminal, sem
   --confirm, onde o nvo pede para digitar o nome do agente.
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
