#!/usr/bin/env bash
# nvo-orcamento.sh — vigia o consumo de tokens do time e freia antes do teto.
#
# Le o consumo atual pelo medidor que ja existe (bin/nvo-usage.py --json),
# compara com um teto (em tokens da janela rolante de 5h) e age:
#   < 80%  do teto: nada, so relatorio.
#   >= 80% do teto: avisa (stdout).
#   >= 100% do teto: manda, pela sessao tmux do projeto, uma pausa
#                     cooperativa para cada agente vivo — pede que registre
#                     nas notas onde parou e aguarde. NUNCA mata processo,
#                     NUNCA remove worktree.
#
# Idempotente: um agente so recebe a pausa uma vez por estouro. O registro
# so e limpo quando o consumo volta a ficar abaixo do teto (nova janela de
# 5h, por exemplo) — so ai um novo estouro volta a avisar todo mundo.
#
# Feito para ser chamado periodicamente (cron, launchd, o que for por fora)
# — este script nao instala nenhum agendamento sozinho.
#
# Teto, nesta ordem de precedencia:
#   1. variavel de ambiente NVO_ORCAMENTO_TETO (tokens da janela de 5h)
#   2. arquivo $ORQ/orcamento.conf, linha "teto=<numero>"
#   3. padrao de 3000000 tokens
#
# Uso: nvo-orcamento.sh

set -euo pipefail

ORQ="${ORQ:-$HOME/orquestra}"
WT_ROOT="$ORQ/worktrees"
META_ROOT="$ORQ/agents"
CONF="$ORQ/project.conf"
ORCAMENTO_CONF="$ORQ/orcamento.conf"
TETO_PADRAO=3000000

die() { echo "nvo-orcamento: $*" >&2; exit 1; }

# mesma sanitizacao de bin/nvo (session_name): "orquestra-<projeto>"
session_name() {
  printf 'orquestra-%s' "$(printf '%s' "$1" | tr -c 'A-Za-z0-9_-' '_')"
}

teto_atual() {
  if [ -n "${NVO_ORCAMENTO_TETO:-}" ]; then
    printf '%s' "$NVO_ORCAMENTO_TETO"
    return
  fi
  if [ -f "$ORCAMENTO_CONF" ]; then
    local v
    v="$(sed -n 's/^teto=//p' "$ORCAMENTO_CONF" | tail -1)"
    if [ -n "$v" ]; then
      printf '%s' "$v"
      return
    fi
  fi
  printf '%s' "$TETO_PADRAO"
}

# NVO_ORCAMENTO_USAGE_CMD existe so para teste: deixa trocar o medidor real
# por um fixture. Em uso real e sempre bin/nvo-usage.py --json.
usage_json() {
  if [ -n "${NVO_ORCAMENTO_USAGE_CMD:-}" ]; then
    bash -c "$NVO_ORCAMENTO_USAGE_CMD"
  else
    python3 "$ORQ/bin/nvo-usage.py" --json
  fi
}

[ -f "$CONF" ] || die "nenhum projeto ativo em $CONF (rode: nvo init <caminho>)"
REPO="$(cat "$CONF")"
[ -d "$REPO" ] || die "projeto registrado nao existe: $REPO"
PROJ="$(basename "$REPO")"
SESSION="$(session_name "$PROJ")"

TETO="$(teto_atual)"
printf '%s' "$TETO" | grep -Eq '^[0-9]+$' || die "teto invalido: '$TETO' (precisa ser um numero inteiro de tokens)"
[ "$TETO" -gt 0 ] || die "teto precisa ser maior que zero"

USAGE_OUT="$(usage_json)" || die "falha ao ler consumo"
TOKENS="$(printf '%s' "$USAGE_OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["block"]["tokens"])')" \
  || die "resposta do medidor de consumo nao e o JSON esperado"

PCT=$(( TOKENS * 100 / TETO ))

echo "nvo-orcamento — vigia de credito do time"
echo "  projeto: $PROJ"
echo "  consumo (janela de 5h): $TOKENS tokens"
echo "  teto:                   $TETO tokens"
echo "  uso:                    ${PCT}%"
echo

PAUSADOS_FILE="$META_ROOT/$PROJ/.orcamento-pausados"

if [ "$PCT" -lt 80 ]; then
  echo "estado: OK — abaixo de 80% do teto."
  # some com o registro de pausados: se o consumo caiu, um estouro futuro
  # (proxima janela de 5h) deve voltar a avisar todo mundo, nao ficar calado.
  rm -f "$PAUSADOS_FILE"
  exit 0
fi

if [ "$PCT" -lt 100 ]; then
  echo "estado: AVISO — passou de 80% do teto ($PCT%). Va fechando as tarefas em andamento."
  rm -f "$PAUSADOS_FILE"
  exit 0
fi

echo "estado: ESTOURO — passou de 100% do teto ($PCT%). Pausando agentes vivos (cooperativamente)."
echo

mkdir -p "$META_ROOT/$PROJ"
touch "$PAUSADOS_FILE"

if [ ! -d "$WT_ROOT/$PROJ" ]; then
  echo "  (nenhum agente vivo em $PROJ)"
  exit 0
fi

MSG="PAUSA COOPERATIVA (orcamento do time passou de 100% do teto de uso): pare no proximo ponto seguro. Registre nas notas exatamente onde parou e qual e o proximo passo, e aguarde novas instrucoes antes de continuar. Nao finalize nem faca merge agora."

for dir in "$WT_ROOT/$PROJ"/*/; do
  [ -d "$dir" ] || continue
  name="$(basename "$dir")"
  if grep -qxF "$name" "$PAUSADOS_FILE" 2>/dev/null; then
    echo "  - $name: ja avisado neste estouro, nao repete"
    continue
  fi
  if tmux send-keys -t "$SESSION:$name" -l "$MSG" 2>/dev/null; then
    sleep 0.3
    tmux send-keys -t "$SESSION:$name" Enter 2>/dev/null || true
    echo "  - $name: pausa cooperativa enviada"
    echo "$name" >> "$PAUSADOS_FILE"
  else
    echo "  - $name: sem janela tmux ativa, nao deu para avisar"
  fi
done
