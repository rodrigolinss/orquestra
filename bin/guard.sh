#!/usr/bin/env bash
# guard.sh — hook PreToolUse (matcher: Bash) do orquestrador nvo.
# Le o JSON do tool call no stdin, extrai o comando e bloqueia padroes
# perigosos com exit 2 (mensagem no stderr vira feedback para o agente).
# Camada deterministica: nao depende do modelo estar tendo um bom dia.

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

# 1. rm com flags -r e -f (juntas ou separadas) mirando caminho absoluto ou ~
if printf '%s' "$cmd" | grep -Eq '(^|[;&|`(]|\s)rm\s'; then
  if printf '%s' "$cmd" | grep -Eq 'rm\s+[^;&|]*-[A-Za-z]*r' \
     && printf '%s' "$cmd" | grep -Eq 'rm\s+[^;&|]*-[A-Za-z]*f' \
     && printf '%s' "$cmd" | grep -Eq 'rm\s+[^;&|]*\s["'"'"']?(/|~|\$HOME)'; then
    block "rm -rf em caminho absoluto ou home"
  fi
fi

# 2. sudo
printf '%s' "$cmd" | grep -Eq '(^|[;&|`(]|\s)sudo(\s|$)' \
  && block "sudo nao e permitido"

# 3. git push
printf '%s' "$cmd" | grep -Eq 'git(\s+-[^ ]+)*\s+push(\s|$)' \
  && block "git push nao e permitido; merge e decisao humana via nvo done"

# 4. git reset --hard
printf '%s' "$cmd" | grep -Eq 'git(\s+-[^ ]+)*\s+reset\s+[^;&|]*--hard' \
  && block "git reset --hard nao e permitido"

# 5. checkout/switch para main ou master
printf '%s' "$cmd" | grep -Eq 'git(\s+-[^ ]+)*\s+(checkout|switch)\s+(-[^ ]+\s+)*["'"'"']?(main|master)["'"'"']?(\s|$)' \
  && block "trocar para main/master nao e permitido; agentes ficam na propria branch"

# 6. curl/wget com pipe para sh/bash
printf '%s' "$cmd" | grep -Eq '(curl|wget)[^;&|]*\|[^;&|]*\b(sh|bash|zsh)(\s|$)' \
  && block "pipe de download direto para shell nao e permitido"

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
printf '%s' "$cmd" | grep -Eq '(~|\$HOME|/Users/[^/[:space:]]+)/\.(ssh|aws)(/|[^A-Za-z0-9_-]|$)' \
  && block "acesso a ~/.ssh e ~/.aws nao e permitido"

exit 0
