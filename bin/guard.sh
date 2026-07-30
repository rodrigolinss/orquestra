#!/usr/bin/env bash
# guard.sh — hook PreToolUse (matcher: Bash) do orquestrador nvo.
# Le o JSON do tool call no stdin, extrai o comando e bloqueia padroes
# perigosos com exit 2 (mensagem no stderr vira feedback para o agente).
# Camada deterministica: nao depende do modelo estar tendo um bom dia.
#
# Limitacoes conhecidas (isto casa TEXTO, nao executa nem interpreta shell):
# - indirecao por variavel escapa (ex.: p=$HOME; rm -rf "$p") porque o guard
#   nunca avalia a expansao, so olha a string do comando;
# - ofuscacao via eval com payload em base64 (ou qualquer outra codificacao)
#   nao e decodificada, entao passa incolume;
# - so intercepta o tool Bash: escrita/edicao de arquivo via Write/Edit nao
#   passa por este hook.

set -u

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"

# Sem comando extraivel: nao ha o que inspecionar, deixa passar
[ -z "$cmd" ] && exit 0

block() {
  echo "guard.sh BLOQUEOU: $1" >&2
  echo "Comando: $cmd" >&2
  exit 2
}

# flags do git que tomam argumento antes do subcomando, forma separada por
# espaco (a forma com "=" ja e coberta por -[^ ]+, que casa o token inteiro)
GITFLAGS='(\s+(-C\s+[^ ]+|--git-dir\s+[^ ]+|--work-tree\s+[^ ]+|--namespace\s+[^ ]+|-[^ ]+))*'
# variantes curtas (-r/-f, combinaveis com outras letras) ou longas do rm
RM_R='(-[A-Za-z]*r[A-Za-z]*|--recursive)'
RM_F='(-[A-Za-z]*f[A-Za-z]*|--force)'

# 1. rm com flags -r e -f (curtas ou longas, juntas ou separadas) mirando
#    caminho absoluto ou ~
if printf '%s' "$cmd" | grep -Eq '(^|[;&|`(]|\s)rm\s'; then
  if printf '%s' "$cmd" | grep -Eq "rm\s+[^;&|]*${RM_R}" \
     && printf '%s' "$cmd" | grep -Eq "rm\s+[^;&|]*${RM_F}" \
     && printf '%s' "$cmd" | grep -Eq 'rm\s+[^;&|]*\s["'"'"']?(/|~|\$HOME)'; then
    block "rm -rf em caminho absoluto ou home"
  fi
fi

# 1b. cd para caminho perigoso encadeado com && seguido de rm -rf, mesmo que
#     o alvo do rm seja um curinga (o caminho perigoso esta no cd, nao no rm)
if printf '%s' "$cmd" | grep -Eq 'cd\s+["'"'"']?(/|~|\$HOME)([^;&|]*)?\s*&&' \
   && printf '%s' "$cmd" | grep -Eq "rm\s+[^;&|]*${RM_R}" \
   && printf '%s' "$cmd" | grep -Eq "rm\s+[^;&|]*${RM_F}"; then
  block "cd para caminho perigoso encadeado com rm -rf"
fi

# 2. sudo
printf '%s' "$cmd" | grep -Eq '(^|[;&|`(]|\s)sudo(\s|$)' \
  && block "sudo nao e permitido"

# 3. git push
printf '%s' "$cmd" | grep -Eq "git${GITFLAGS}\s+push(\s|\$)" \
  && block "git push nao e permitido; merge e decisao humana via nvo done"

# 4. git reset --hard
printf '%s' "$cmd" | grep -Eq "git${GITFLAGS}\s+reset\s+[^;&|]*--hard" \
  && block "git reset --hard nao e permitido"

# 5. checkout/switch para main ou master
printf '%s' "$cmd" | grep -Eq "git${GITFLAGS}\s+(checkout|switch)\s+(-[^ ]+\s+)*[\"']?(main|master)[\"']?(\s|\$)" \
  && block "trocar para main/master nao e permitido; agentes ficam na propria branch"

# 6. curl/wget com pipe para sh/bash
printf '%s' "$cmd" | grep -Eq '(curl|wget)[^;&|]*\|[^;&|]*\b(sh|bash|zsh)(\s|$)' \
  && block "pipe de download direto para shell nao e permitido"

# 6b. derrubar o servidor de terminais inteiro
# Um agente vive numa janela do tmux, e as janelas dos OUTROS agentes (e do
# maestro) vivem no mesmo servidor. Matar o servidor mata a equipe toda de uma
# vez: as sessoes de todos morrem no meio do trabalho, sem aviso e sem chance
# de salvar contexto. Nenhuma tarefa legitima de agente precisa disto — quem
# testa o motor cria a propria sessao e derruba SO ela, pelo nome.
printf '%s' "$cmd" | grep -Eq 'tmux[^;&|]*\bkill-server(\s|$)' \
  && block "tmux kill-server nao e permitido: derruba o maestro e todos os agentes de uma vez. Para limpar um teste, mate a sua sessao pelo nome (tmux kill-session -t <sua-sessao>)"

printf '%s' "$cmd" | grep -Eq '(pkill|killall)\s+([^;&|]*\s)?tmux(\s|$)' \
  && block "matar o processo do tmux nao e permitido: derruba o maestro e todos os agentes de uma vez"

# 6c. comandos do orquestrador que derrubam a equipe inteira
# 'nvo stop' e 'nvo limpar' sao decisoes do humano sobre a sessao dele: um
# desliga maestro e todos os agentes, o outro zera o painel. Um agente que
# testa o motor chama esses comandos com a melhor das intencoes e mata os
# colegas que estavam no meio do trabalho — aconteceu duas vezes hoje. Quem
# precisa testar isso de verdade sobe a propria sessao noutro socket, com
# NVO_TMUX_SOCKET=teste, e la faz o que quiser.
printf '%s' "$cmd" | grep -Eq '(^|[;&|`(]|\s)([^ ]*/)?nvo\s+(stop|limpar)(\s|$)' \
  && block "'nvo stop' e 'nvo limpar' sao do humano, nao do agente: derrubam o maestro e todos os agentes de uma vez. Para testar, use uma sessao propria: NVO_TMUX_SOCKET=teste nvo ..."

# 6c-bis. trocar o projeto ativo do humano
# 'nvo init' reescreve qual e o projeto ativo — o que o app abre quando sobe.
# Um agente testando o motor init-ou num repositorio temporario e o painel do
# humano abriu la, num /var/folders, sem os agentes dele. Quem precisa operar
# outro projeto usa NVO_PROJECT=<caminho> na frente do comando: funciona igual
# e nao mexe na escolha de quem esta olhando a tela.
printf '%s' "$cmd" | grep -Eq '(^|[;&|`(]|\s)([^ ]*/)?nvo\s+init(\s|$)' \
  && block "'nvo init' troca o projeto ativo do humano e faz o painel dele abrir em outro lugar. Para trabalhar noutro projeto use: NVO_PROJECT=/caminho nvo <comando>"

# 6d. matar janela ou sessao de tmux no servidor da equipe
# O agente vive numa janela; as dos colegas estao no mesmo servidor. Qualquer
# kill aqui atinge quem esta trabalhando. Com -L apontando para outro socket
# (a sessao de teste do proprio agente) esta liberado.
if printf '%s' "$cmd" | grep -Eq 'tmux[^;&|]*\bkill-(session|window|pane)(\s|$)'; then
  printf '%s' "$cmd" | grep -Eq 'tmux\s+-L\s+[^ ]+' \
    || block "matar janela ou sessao no servidor da equipe nao e permitido: os outros agentes vivem nele. Suba a sua sessao de teste noutro socket (tmux -L teste ...) e mate a sua la"
fi

# 7. chmod 777
printf '%s' "$cmd" | grep -Eq 'chmod\s+[^;&|]*777' \
  && block "chmod 777 nao e permitido"

# 8. arquivos e diretorios sensiveis
printf '%s' "$cmd" | grep -Eq '(^|[/[:space:]"'"'"'=])\.env(\.[A-Za-z0-9_.-]+)?([^A-Za-z0-9_-]|$)' \
  && block "acesso a arquivos .env nao e permitido"
printf '%s' "$cmd" | grep -Eq '\.pem([^A-Za-z0-9_-]|$)' \
  && block "acesso a arquivos .pem nao e permitido"
printf '%s' "$cmd" | grep -Eq 'id_rsa' \
  && block "acesso a chaves SSH nao e permitido"
# cobre home de macOS (/Users/x), Linux e WSL (/home/x, /root), ~ e $HOME
printf '%s' "$cmd" | grep -Eq '(~|\$HOME|/root|/(Users|home)/[^/[:space:]]+)/\.(ssh|aws)(/|[^A-Za-z0-9_-]|$)' \
  && block "acesso a ~/.ssh e ~/.aws nao e permitido"

exit 0
