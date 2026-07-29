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

# 2. plataforma (macOS / Linux / Windows via WSL2)
# shellcheck source=bin/platform.sh
. "$ORQ/bin/platform.sh"
case "$ORQ_OS" in
  macos) echo "-> plataforma: macOS (CLI + app nativo)" ;;
  wsl)   echo "-> plataforma: Windows via WSL2 (${WSL_DISTRO_NAME:-linux}) — CLI" ;;
  linux) echo "-> plataforma: Linux — CLI" ;;
  *)     echo "aviso: plataforma nao reconhecida ($(uname -s)); seguindo como Linux" ;;
esac

# 3. dependencias (so instala o que falta)
if [ "$ORQ_PKG" = "none" ]; then
  echo "aviso: nenhum gerenciador de pacotes conhecido — instale tmux e jq manualmente"
else
  [ "$ORQ_PKG" = "apt" ] && command -v tmux >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 \
    || { [ "$ORQ_PKG" = "apt" ] && sudo apt-get update -qq || true; }
  for pkg in tmux jq; do
    command -v "$pkg" >/dev/null 2>&1 && continue
    echo "-> instalando $pkg ($ORQ_PKG)"
    orq_pkg_install "$pkg" || echo "   aviso: falhou; rode manualmente: $(orq_pkg_hint "$pkg")"
  done
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

# 5. PATH (sintaxe conforme o shell do usuario)
SHELL_RC="$ORQ_SHELL_RC"
mkdir -p "$(dirname "$SHELL_RC")"
if ! grep -q 'orquestra/bin' "$SHELL_RC" 2>/dev/null; then
  case "$SHELL_RC" in
    *config.fish)
      printf '\n# orquestra (nvo)\nset -gx PATH $HOME/orquestra/bin $PATH\n' >> "$SHELL_RC" ;;
    *)
      printf '\n# orquestra (nvo)\nexport PATH="$HOME/orquestra/bin:$PATH"\n' >> "$SHELL_RC" ;;
  esac
  echo "-> PATH adicionado em $SHELL_RC"
fi
export PATH="$ORQ/bin:$PATH"

# 6. app nativo (exclusivo do macOS; a CLI e a interface nas outras plataformas)
if [ "$ORQ_HAS_APP" = 1 ]; then
  if xcrun swiftc --version >/dev/null 2>&1; then
    echo "-> compilando Orquestra.app"
    bash "$ORQ/app/build.sh" >/dev/null && echo "   ok: ~/Applications/Orquestra.app"
  else
    echo "aviso: Xcode Command Line Tools ausentes — pulando o app"
    echo "       para compilar depois: xcode-select --install && bash $ORQ/app/build.sh"
  fi
fi

# 7. diagnostico final: mostra o que foi detectado da maquina da pessoa
echo
"$ORQ/bin/nvo" doctor || true

echo
echo "proximos passos:"
echo "  1. abra um terminal novo (ou: source $SHELL_RC)"
echo "  2. se o doctor apontou Claude Code sem login: rode 'claude' uma vez"
if [ "$ORQ_HAS_APP" = 1 ]; then
  echo "  3. abra o Orquestra.app (Spotlight -> Orquestra) e clique em 'projeto'"
  echo "     ou pela CLI: nvo init <pasta> && cd ~/orquestra && claude"
else
  echo "  3. nvo init <pasta-do-projeto>"
  echo "  4. cd ~/orquestra && claude       <- o maestro; fale com ele em portugues"
  echo "  5. nvo ls                         <- status dos agentes  |  nvo attach = ver ao vivo"
fi
