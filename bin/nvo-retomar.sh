#!/usr/bin/env bash
# nvo-retomar — religa agentes cuja janela tmux morreu (sessao encerrada com
# "nvo stop", ou a maquina foi reiniciada) sem perder o que eles ja fizeram.
#
# A copia isolada (worktree), a branch e as notas de um agente sobrevivem a
# esses eventos — so a janela tmux e o processo do harness dentro dela
# somem. Este script descobre quais agentes estao "no disco mas sem janela",
# recria a janela de cada um e manda o harness de volla ao trabalho com um
# texto de retomada: a tarefa original com que ele nasceu, mais a nota atual
# dele, dizendo pra continuar dali em vez de recomecar.
#
# Nao altera bin/nvo. So le o que ja existe em disco (worktrees, .meta,
# .prompt, notas) e escreve um novo arquivo .resume.txt por agente retomado.
set -euo pipefail

ORQ="$HOME/orquestra"
# shellcheck source=platform.sh
[ -f "$ORQ/bin/platform.sh" ] && . "$ORQ/bin/platform.sh" || true
WT_ROOT="$ORQ/worktrees"
NOTES_ROOT="$ORQ/notes"
META_ROOT="$ORQ/agents"
CONF="$ORQ/project.conf"
HARNESSES="$ORQ/bin/harnesses.conf"

# mesmo ajuste de PATH do nvo: quem chama isso a partir de um servico com
# PATH pobre (ex.: launchd) tambem precisa achar tmux/git/claude.
for d in "$ORQ/bin" "$HOME/.local/bin" "$HOME/bin" /opt/homebrew/bin /usr/local/bin; do
  case ":$PATH:" in *":$d:"*) ;; *) [ -d "$d" ] && PATH="$d:$PATH" ;; esac
done
export PATH

die() { echo "nvo-retomar: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
nvo-retomar.sh — religa agentes sem janela tmux viva, sem perder o contexto.

  nvo-retomar.sh              retoma todos os agentes do projeto ativo que
                               estao sem janela viva
  nvo-retomar.sh <nome>       retoma so esse agente
  nvo-retomar.sh --help       esta ajuda

Nunca duplica a janela de um agente que ja esta rodando. Nunca apaga nem
sobrescreve nota. Se a copia isolada de um agente estiver inconsistente
(faltando .meta, .prompt ou nota), avisa com clareza e diz como limpar, em
vez de tentar adivinhar a tarefa dele.
EOF
}

# mesma regra do nvo: tmux nao aceita ponto, dois-pontos ou espaco em nome
# de sessao.
session_name() {
  printf 'orquestra-%s' "$(printf '%s' "$1" | tr -c 'A-Za-z0-9_-' '_')"
}

# mesma ordem de resolucao de projeto do nvo: NVO_PROJECT (cada aba do app
# manda o seu) antes do project.conf (ultimo usado no terminal).
load_project() {
  if [ -n "${NVO_PROJECT:-}" ]; then
    REPO="$NVO_PROJECT"
    [ -d "$REPO" ] || die "projeto nao existe: $REPO"
  else
    [ -f "$CONF" ] || die "nenhum projeto ativo. Rode: nvo init <caminho-do-repo>"
    REPO="$(cat "$CONF")"
  fi
  git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 \
    || die "projeto registrado nao e mais um repo git: $REPO"
  REPO="$(cd "$REPO" && pwd)"
  PROJ="$(basename "$REPO")"
  SESSION="$(session_name "$PROJ")"
}

wt_path()   { echo "$WT_ROOT/$PROJ/$1"; }
meta_path() { echo "$META_ROOT/$PROJ/$1"; }
note_path() { echo "$NOTES_ROOT/$PROJ/$1.md"; }

harness_field() {
  local id="$1" n="$2"
  [ -f "$HARNESSES" ] || return 0
  awk -F'|' -v id="$id" -v n="$n" \
    '/^[[:space:]]*#/ {next} NF>=7 && $1==id {print $n; exit}' "$HARNESSES"
}

harness_launch() {
  local id="$1" model="$2" tpl
  if [ -n "$model" ]; then
    tpl="$(harness_field "$id" 4)"
    tpl="${tpl//%M%/$model}"
  else
    tpl="$(harness_field "$id" 5)"
  fi
  printf '%s' "$tpl"
}

ensure_session() {
  tmux has-session -t "$SESSION" 2>/dev/null \
    || tmux new-session -d -s "$SESSION" -n maestro -c "${REPO:-$ORQ}"
  tmux set-environment -g PATH "$PATH" 2>/dev/null || true
}

window_alive() {
  tmux has-session -t "$SESSION" 2>/dev/null || return 1
  tmux list-windows -t "$SESSION" -F '#W' 2>/dev/null | grep -qxF "$1"
}

# Junta a tarefa original (o prompt com que o agente nasceu) com a nota
# atual dele num texto so, deixando claro que o trabalho ja descrito na nota
# esta feito e o agente deve continuar dali, sem reler nem repetir do zero.
build_resume_prompt() {
  local name="$1" prompt="$2" note="$3" out="$4"
  {
    printf 'Voce e o agente "%s", retomando depois de uma parada (sessao encerrada ou maquina reiniciada).\n' "$name"
    printf 'Sua copia isolada (worktree), sua branch e suas notas continuam intactas — so a janela caiu.\n\n'
    printf '== SUA TAREFA ORIGINAL, exatamente como foi lancada =========================\n\n'
    cat "$prompt"
    printf '\n\n== SUAS NOTAS ATE AGORA (o que voce ja fez) ==================================\n\n'
    cat "$note"
    printf '\n\n== RETOMADA ===================================================================\n'
    printf 'Voce ja fez o que esta descrito acima nas notas. Nao recomece do zero: confira\n'
    printf 'o estado atual do seu worktree (git status, git log) e continue exatamente de\n'
    printf 'onde parou. Se as notas ja tem "STATUS: CONCLUIDO", so confirme que esta tudo\n'
    printf 'aplicado e pare. Continue agora.\n'
  } > "$out"
}

RESUMED=0
SKIPPED=0
FAIL=0

inconsistente() {
  local name="$1" msg="$2"
  echo "inconsistente: agente '$name' — $msg" >&2
  FAIL=$((FAIL + 1))
}

resume_one() {
  local name="$1" wt meta prompt note cli model launch resume

  wt="$(wt_path "$name")"
  meta="$(meta_path "$name").meta"
  prompt="$(meta_path "$name").prompt"
  note="$(note_path "$name")"

  if [ ! -f "$meta" ] || [ ! -f "$prompt" ] || [ ! -f "$note" ]; then
    local faltando=""
    [ -f "$meta" ]   || faltando="$faltando $meta"
    [ -f "$prompt" ] || faltando="$faltando $prompt"
    [ -f "$note" ]   || faltando="$faltando $note"
    inconsistente "$name" "tem copia isolada em $wt mas falta:$faltando. Nao vou adivinhar a tarefa dele. Para limpar: se o trabalho nao importa mais, rode 'nvo kill $name' (remove a copia isolada, a branch fica no git); se importa, restaure o(s) arquivo(s) que faltam antes de retomar."
    return 0
  fi

  git -C "$wt" rev-parse --git-dir >/dev/null 2>&1 || {
    inconsistente "$name" "tem metadados em $meta mas $wt nao e mais um worktree git valido. Para limpar: 'git -C $REPO worktree prune' e depois apague $meta, $prompt e $note a mao se quiser descartar de vez."
    return 0
  }

  cli="$(sed -n 's/^cli=//p' "$meta" | tail -1)"
  model="$(sed -n 's/^model=//p' "$meta" | tail -1)"
  if [ -z "$cli" ]; then
    inconsistente "$name" "$meta nao tem a linha 'cli=' — nao vou adivinhar o harness. Edite $meta a mao ou rode 'nvo kill $name' para descartar."
    return 0
  fi

  if window_alive "$name"; then
    echo "'$name' ja esta rodando — janela viva, nao mexi."
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi

  if [ "$cli" = "bash" ]; then
    launch="bash"
  else
    launch="$(harness_launch "$cli" "$model")"
    if [ -z "$launch" ]; then
      inconsistente "$name" "harness '$cli' nao esta mais registrado em $HARNESSES. Edite $meta com um harness valido ou rode 'nvo kill $name' para descartar."
      return 0
    fi
  fi

  resume="$(meta_path "$name").resume.txt"
  build_resume_prompt "$name" "$prompt" "$note" "$resume"

  ensure_session
  tmux new-window -t "$SESSION" -n "$name" -c "$wt"
  tmux send-keys -t "$SESSION:$name" "$launch \"\$(cat '$resume')\"" Enter

  echo "'$name' retomado ($cli${model:+ · $model}) — janela: $SESSION:$name"
  RESUMED=$((RESUMED + 1))
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

load_project
[ -d "$WT_ROOT/$PROJ" ] || die "nenhum agente em $PROJ ($WT_ROOT/$PROJ nao existe)"

if [ $# -eq 1 ]; then
  name="$1"
  [ -d "$(wt_path "$name")" ] || die "agente '$name' nao existe (sem copia isolada em $(wt_path "$name"))"
  resume_one "$name"
elif [ $# -eq 0 ]; then
  found=0
  for dir in "$WT_ROOT/$PROJ"/*/; do
    [ -d "$dir" ] || continue
    found=1
    resume_one "$(basename "$dir")"
  done
  [ "$found" -eq 1 ] || die "nenhum agente em $PROJ"
else
  die "uso: nvo-retomar.sh [<nome>]"
fi

echo
echo "resumo: $RESUMED retomado(s), $SKIPPED ja rodando, $FAIL inconsistente(s)"
[ "$FAIL" -eq 0 ]
