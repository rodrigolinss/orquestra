#!/usr/bin/env bash
# nvo-review.sh — segunda opiniao de um fornecedor DIFERENTE do que construiu.
#
# Uso: bash bin/nvo-review.sh <nome-do-agente>
#
# Pega o diff (tres pontos, mesma logica de "nvo diff") e as notas de um
# agente ja criado pelo nvo, e manda revisar por um harness de fornecedor
# diferente do que construiu — instalado nesta maquina, escolhido a partir de
# bin/harnesses.conf. A revisao e adversarial: o prompt pede para tentar
# derrubar o trabalho, nao elogiar. O resultado vai para
# $ORQ/notes/<projeto>/<nome>.review.md, ao lado das notas do agente.
#
# Preferencia de revisor: chaves "prefer_review" (fornecedor preferido) e
# "avoid_harness" (fornecedor a nunca escolher sozinho) em config.conf, se
# existirem (lidas em silencio se nao existirem).

set -euo pipefail

ORQ="$HOME/orquestra"
[ -f "$ORQ/bin/platform.sh" ] && . "$ORQ/bin/platform.sh" || true
for d in "$ORQ/bin" "$HOME/.local/bin" "$HOME/bin" /opt/homebrew/bin /usr/local/bin; do
  case ":$PATH:" in *":$d:"*) ;; *) [ -d "$d" ] && PATH="$d:$PATH" ;; esac
done
export PATH

WT_ROOT="$ORQ/worktrees"
NOTES_ROOT="$ORQ/notes"
META_ROOT="$ORQ/agents"
CONF="$ORQ/project.conf"
CONFIG="$ORQ/config.conf"
# NVO_HARNESSES existe para testar o caminho degradado (lista reduzida de
# harnesses), mesma ideia de NVO_PROJECT/NVO_AGENT_CMD em bin/nvo.
HARNESSES="${NVO_HARNESSES:-$ORQ/bin/harnesses.conf}"

die() { echo "nvo-review: $*" >&2; exit 1; }

config_get() {
  local chave="$1" padrao="$2" valor=""
  [ -f "$CONFIG" ] && valor="$(sed -n "s/^$chave=//p" "$CONFIG" | tail -1)"
  printf '%s' "${valor:-$padrao}"
}

# Campo N da linha do harness, ou vazio se o harness nao existe no registro.
harness_field() {
  local id="$1" n="$2"
  [ -f "$HARNESSES" ] || return 0
  awk -F'|' -v id="$id" -v n="$n" \
    '/^[[:space:]]*#/ {next} NF>=7 && $1==id {print $n; exit}' "$HARNESSES"
}

# Ultimo modelo da lista (campo 6) = convencao do harnesses.conf para "mais
# barato" (mesma regra usada por "nvo explain").
cheapest_model() { harness_field "$1" 6 | awk -F',' '{print $NF}'; }

# Monta a linha de comando de LANCAMENTO (usada para "nvo new"/tmux) de um
# harness qualquer do registro, com o modelo aplicado.
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

check_name() {
  printf '%s' "$1" | grep -Eq '^[A-Za-z0-9_-]+$' \
    || die "nome invalido '$1' (use apenas letras, numeros, - e _)"
}

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
}

# --- 1. localizar o agente e o que o construiu -----------------------------

[ $# -eq 1 ] || die 'uso: nvo-review.sh <nome-do-agente>'
NAME="$1"
check_name "$NAME"
load_project

WT="$WT_ROOT/$PROJ/$NAME"
[ -d "$WT" ] || die "agente '$NAME' nao existe (esperava $WT)"
# revisores como o codex exploram o proprio cwd com ferramentas de shell
# (mesmo em modo read-only); rodar de dentro do worktree do agente garante
# que arquivo/linha que ele citar batem com o codigo que esta sendo revisado
cd "$WT"

META="$META_ROOT/$PROJ/$NAME.meta"
[ -f "$META" ] || die "metadados do agente '$NAME' nao encontrados ($META)"

BASE="$(sed -n 's/^base=//p' "$META")"
BUILDER_CLI="$(sed -n 's/^cli=//p' "$META")"
BUILDER_MODEL="$(sed -n 's/^model=//p' "$META")"
[ -n "$BASE" ] || die "meta de '$NAME' sem 'base=' ($META)"

NOTE="$NOTES_ROOT/$PROJ/$NAME.md"
REVIEW_OUT="$NOTES_ROOT/$PROJ/$NAME.review.md"

# --- 2. diff correto (merge-base, tres pontos) e notas ----------------------

DIFF_TEXT="$(git -C "$WT" diff "$BASE"...)"
[ -n "$DIFF_TEXT" ] || die "sem diff: agente '$NAME' nao tem mudancas contra $BASE"

NOTES_TEXT=""
[ -f "$NOTE" ] && NOTES_TEXT="$(cat "$NOTE")"

MAX_CHARS=12000
TRUNCATED=0
if [ "${#DIFF_TEXT}" -gt "$MAX_CHARS" ]; then
  DIFF_TEXT="${DIFF_TEXT:0:$MAX_CHARS}"
  TRUNCATED=1
fi

# --- 3. escolher o revisor ---------------------------------------------------
#
# Devolve, em uma linha "id<TAB>modelo<TAB>nota": nota explica a diversidade
# real (fornecedor diferente / mesmo fornecedor, modelo diferente / autorrevisao).
# Codigo de saida 2 = nenhum harness instalado.
pick_reviewer() {
  local builder_cli="$1" builder_model="$2"
  [ -f "$HARNESSES" ] || return 2

  local -a installed=()
  local id label hbin
  while IFS='|' read -r id label hbin _ _ _ _; do
    case "$id" in ''|\#*) continue ;; esac
    command -v "$hbin" >/dev/null 2>&1 && installed+=("$id")
  done < "$HARNESSES"

  # avoid_harness (config.conf): fornecedor que a pessoa nunca quer ver
  # escolhido automaticamente — tira da lista de candidatos antes de tudo.
  local avoid
  avoid="$(config_get avoid_harness "")"
  if [ -n "$avoid" ]; then
    local kept=() x
    for x in "${installed[@]}"; do [ "$x" = "$avoid" ] || kept+=("$x"); done
    installed=(${kept[@]+"${kept[@]}"})
  fi
  [ "${#installed[@]}" -gt 0 ] || return 2

  # prefer_review (config.conf): fornecedor preferido para revisar, se
  # instalado (e nao for o que acabou de ser excluido por avoid_harness).
  # Modelo sempre o mais barato do fornecedor — revisao e leitura.
  local pref_harness
  pref_harness="$(config_get prefer_review "")"
  if [ -n "$pref_harness" ]; then
    local ok=0 x
    for x in "${installed[@]}"; do [ "$x" = "$pref_harness" ] && ok=1; done
    if [ "$ok" -eq 1 ]; then
      local nota
      if [ "$pref_harness" != "$builder_cli" ]; then
        nota="preferencia configurada (prefer_review=$pref_harness em config.conf): fornecedor diferente do que construiu ($builder_cli)."
      else
        nota="AVISO: a preferencia configurada (prefer_review=$pref_harness) e o MESMO fornecedor que construiu ($builder_cli) — diversidade menor, mas foi um pedido explicito em config.conf."
      fi
      printf '%s\t%s\t%s\n' "$pref_harness" "$(cheapest_model "$pref_harness")" "$nota"
      return 0
    fi
  fi

  # fornecedor diferente do que construiu, primeiro instalado (ordem do arquivo)
  local cand
  for cand in "${installed[@]}"; do
    if [ "$cand" != "$builder_cli" ]; then
      printf '%s\t%s\t%s\n' "$cand" "$(cheapest_model "$cand")" \
        "fornecedor diferente do que construiu ($builder_cli -> $cand): revisor sem o mesmo ponto cego."
      return 0
    fi
  done

  # so o mesmo fornecedor esta instalado: tenta modelo diferente
  for cand in "${installed[@]}"; do
    [ "$cand" = "$builder_cli" ] || continue
    local models chosen="" m
    models="$(harness_field "$cand" 6)"
    IFS=',' read -r -a marr <<< "$models"
    local i
    for ((i = ${#marr[@]} - 1; i >= 0; i--)); do
      m="${marr[$i]}"
      if [ "$m" != "$builder_model" ]; then chosen="$m"; break; fi
    done
    if [ -n "$chosen" ]; then
      printf '%s\t%s\t%s\n' "$cand" "$chosen" \
        "AVISO: so o mesmo fornecedor que construiu ($cand) esta instalado. Revisando com modelo diferente ($chosen em vez de $builder_model) — diversidade MENOR do que trocar de fornecedor."
    else
      printf '%s\t%s\t%s\n' "$cand" "$builder_model" \
        "AVISO: so existe o mesmo fornecedor E o mesmo modelo ($cand/$builder_model) instalados. Isto e AUTORREVISAO — vale menos, o ponto cego pode se repetir."
    fi
    return 0
  done

  return 2
}

PICK="$(pick_reviewer "$BUILDER_CLI" "$BUILDER_MODEL")" || {
  rc=$?
  if [ "$rc" -eq 2 ]; then
    die "nenhum harness de agente instalado nesta maquina para revisar (veja bin/harnesses.conf e 'nvo harnesses')"
  fi
  die "nao foi possivel escolher um revisor"
}
REVIEWER_CLI="$(printf '%s' "$PICK" | cut -f1)"
REVIEWER_MODEL="$(printf '%s' "$PICK" | cut -f2)"
DIVERSITY_NOTE="$(printf '%s' "$PICK" | cut -f3)"

# --- 4. montar o prompt adversarial -----------------------------------------

TRUNC_MSG=""
[ "$TRUNCATED" -eq 1 ] && TRUNC_MSG=" (TRUNCADO em ${MAX_CHARS} caracteres)"

# O diff e as notas sao conteudo GERADO por outro agente: podem ter crases
# (code span de markdown), cifrao, backtick etc. Delimitador de heredoc
# ENTRE ASPAS ('EOF') evita que o bash tente expandir isso como comando; a
# parte variavel entra depois, via printf '%s', que nunca reinterpreta o
# conteudo. Evite parenteses desbalanceados aqui dentro (ex.: "1)"): o bash
# 3.2 do macOS conta parenteses no corpo do heredoc mesmo dentro de aspas
# simples e quebra o "$(...)" que envolve o "cat" — bug real, testado nesta
# maquina.
INSTRUCOES="$(cat <<'EOF'
Voce e um revisor adversarial de codigo. Sua tarefa e tentar DERRUBAR este
trabalho, nao elogia-lo. Seja cetico por padrao.

Responda em portugues, curto (no maximo ~15 linhas), cobrindo nesta ordem:
1. Erros de verdade, com arquivo e linha. So aponte o que tiver certeza que
   esta errado — nao e revisao de estilo ou preferencia.
2. O que as notas do agente PROMETEM mas nao aparece no diff (trabalho nao
   entregue, ou notas que descrevem algo que o codigo nao faz).
3. O risco concreto de aplicar este diff do jeito que esta.

Se depois de procurar de verdade voce nao achar nenhum problema real, diga
isso em UMA linha: "nao encontrei problema real" — em vez de inventar
critica so para parecer util.
EOF
)"

PROMPT="$(printf '%s\n\n=== NOTAS DO AGENTE ===\n%s\n\n=== DIFF (base...agente%s) ===\n%s\n' \
  "$INSTRUCOES" "${NOTES_TEXT:-(sem notas)}" "$TRUNC_MSG" "$DIFF_TEXT")"

# --- 5. rodar o revisor sem sessao interativa, com timeout ------------------

TIMEOUT_SECS=240

# Espera "$pid" ate "$secs" segundos; TERM e depois KILL se estourar.
# Devolve 124 no timeout, senao o codigo de saida do processo.
wait_timeout() {
  local pid="$1" secs="$2" waited=0
  while kill -0 "$pid" 2>/dev/null; do
    sleep 1
    waited=$((waited + 1))
    if [ "$waited" -ge "$secs" ]; then
      kill -TERM "$pid" 2>/dev/null || true
      sleep 1
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
  done
  wait "$pid"
}

REVIEWER_BIN="$(harness_field "$REVIEWER_CLI" 3)"
[ -n "$REVIEWER_BIN" ] && command -v "$REVIEWER_BIN" >/dev/null 2>&1 \
  || die "'$REVIEWER_CLI' nao esta instalado (nada para chamar em $REVIEWER_BIN)"

OUT_TMP="$(mktemp)"
trap 'rm -f "$OUT_TMP"' EXIT

# Cada CLI tem seu proprio jeito de rodar sem abrir sessao interativa. Os tres
# conhecidos ganham a chamada certa; qualquer harness novo em harnesses.conf
# (deepseek/aider incluso) cai no generico: template de lancamento do arquivo
# + prompt como ultimo argumento + stdin de /dev/null, mesma convencao que o
# proprio harnesses.conf documenta.
case "$REVIEWER_CLI" in
  claude)
    ( printf '%s' "$PROMPT" | "$REVIEWER_BIN" --model "$REVIEWER_MODEL" -p ) \
      > "$OUT_TMP" 2>&1 &
    ;;
  codex)
    ( printf '%s' "$PROMPT" | "$REVIEWER_BIN" exec -m "$REVIEWER_MODEL" --sandbox read-only - ) \
      > "$OUT_TMP" 2>&1 &
    ;;
  gemini)
    ( "$REVIEWER_BIN" -m "$REVIEWER_MODEL" -p "$PROMPT" < /dev/null ) \
      > "$OUT_TMP" 2>&1 &
    ;;
  *)
    TPL="$(harness_launch "$REVIEWER_CLI" "$REVIEWER_MODEL")"
    read -r -a GEN_CMD <<< "$TPL"
    GEN_CMD+=("$PROMPT")
    ( "${GEN_CMD[@]}" < /dev/null ) > "$OUT_TMP" 2>&1 &
    ;;
esac
PID=$!

RC=0
wait_timeout "$PID" "$TIMEOUT_SECS" || RC=$?

OUTPUT="$(cat "$OUT_TMP")"

if [ "$RC" -eq 124 ]; then
  die "revisor '$REVIEWER_CLI' ($REVIEWER_MODEL) estourou o timeout de ${TIMEOUT_SECS}s e foi encerrado. Saida ate agora:
$OUTPUT"
fi
if [ "$RC" -ne 0 ] || [ -z "$OUTPUT" ]; then
  die "chamada ao revisor '$REVIEWER_CLI' ($REVIEWER_MODEL) falhou (codigo $RC). Saida real:
$OUTPUT"
fi

# --- 6. gravar ao lado das notas e resumir no terminal ----------------------

{
  printf '# revisao adversarial de %s\n\n' "$NAME"
  printf 'construiu: %s / %s\n' "$BUILDER_CLI" "${BUILDER_MODEL:-(sem modelo registrado)}"
  printf 'revisou:   %s / %s\n' "$REVIEWER_CLI" "$REVIEWER_MODEL"
  printf 'diversidade: %s\n' "$DIVERSITY_NOTE"
  [ "$TRUNCATED" -eq 1 ] && printf 'aviso: diff truncado em %s caracteres antes de enviar ao revisor.\n' "$MAX_CHARS"
  printf '\n---\n\n%s\n' "$OUTPUT"
} > "$REVIEW_OUT"

echo "nvo-review: construiu $BUILDER_CLI/$BUILDER_MODEL, revisou $REVIEWER_CLI/$REVIEWER_MODEL"
echo "nvo-review: $DIVERSITY_NOTE"
[ "$TRUNCATED" -eq 1 ] && echo "nvo-review: diff truncado em $MAX_CHARS caracteres antes de enviar ao revisor"
echo "nvo-review: resultado salvo em $REVIEW_OUT"
echo
echo "$OUTPUT"
