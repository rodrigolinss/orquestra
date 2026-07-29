#!/usr/bin/env bash
# install.sh — instalador do orquestra. Idempotente: rodar de novo so conserta.
# Detecta o que ja existe na maquina (claude logado, git configurado, tmux)
# e so instala o que falta. Nao pede credencial de nada.
set -euo pipefail

ORQ="$HOME/orquestra"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "== orquestra — instalador =="
echo

# 1. garante que o codigo esta em ~/orquestra (nvo assume esse caminho)
if [ "$HERE" != "$ORQ" ]; then
  if [ -e "$ORQ" ]; then
    echo "erro: ja existe $ORQ e voce esta rodando de $HERE" >&2
    echo "mova ou remova o antigo, ou rode o install de dentro dele." >&2
    exit 1
  fi
  echo "-> copiando para $ORQ"
  cp -R "$HERE" "$ORQ"
fi
cd "$ORQ"

# 2. dependencias (so instala o que falta)
if ! command -v brew >/dev/null 2>&1; then
  echo "aviso: Homebrew nao encontrado — instale tmux e jq manualmente se faltarem"
else
  command -v tmux >/dev/null 2>&1 || { echo "-> instalando tmux"; brew install tmux; }
  command -v jq   >/dev/null 2>&1 || { echo "-> instalando jq";   brew install jq; }
fi

# 3. permissoes e diretorios de runtime
chmod +x "$ORQ/bin/nvo" "$ORQ/bin/guard.sh" "$ORQ/app/build.sh" 2>/dev/null || true
mkdir -p "$ORQ/worktrees" "$ORQ/notes" "$ORQ/agents" "$ORQ/repos"

# 4. hook de seguranca (recria se nao existir; nunca sobrescreve customizacao)
if [ ! -f "$ORQ/.claude/settings.json" ]; then
  mkdir -p "$ORQ/.claude"
  cat > "$ORQ/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"$HOME/orquestra/bin/guard.sh\""
          }
        ]
      }
    ]
  }
}
EOF
  echo "-> hook de seguranca criado"
fi

# 5. PATH
SHELL_RC="$HOME/.zshrc"
[ -n "${BASH_VERSION:-}" ] && [ -f "$HOME/.bashrc" ] && SHELL_RC="$HOME/.bashrc"
if ! grep -q 'orquestra/bin' "$SHELL_RC" 2>/dev/null; then
  printf '\n# orquestra (nvo)\nexport PATH="$HOME/orquestra/bin:$PATH"\n' >> "$SHELL_RC"
  echo "-> PATH adicionado em $SHELL_RC"
fi
export PATH="$ORQ/bin:$PATH"

# 6. app nativo (opcional, macOS + Command Line Tools)
if [ "$(uname)" = "Darwin" ] && xcrun swiftc --version >/dev/null 2>&1; then
  echo "-> compilando Orquestra.app"
  bash "$ORQ/app/build.sh" >/dev/null && echo "   ok: ~/Applications/Orquestra.app"
else
  echo "aviso: swiftc indisponivel — pulando o app nativo (a CLI funciona igual)"
fi

# 7. diagnostico final: mostra o que foi detectado da maquina da pessoa
echo
"$ORQ/bin/nvo" doctor || true

echo
echo "proximos passos:"
echo "  1. abra um terminal novo (ou: source $SHELL_RC)"
echo "  2. se o doctor apontou Claude Code sem login: rode 'claude' uma vez"
echo "  3. nvo init <pasta-do-projeto>   (ou abra o Orquestra.app e clique em 'projeto')"
echo "  4. cd ~/orquestra && claude      (o maestro)  — ou use o app"
