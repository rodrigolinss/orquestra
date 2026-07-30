#!/usr/bin/env bash
# platform.sh — deteccao de plataforma, compartilhada por nvo e install.sh.
# Sourced, nunca executado direto. Define:
#   ORQ_OS        macos | windows | desconhecido
#   ORQ_PKG       brew | pacman | none
#   ORQ_SHELL_RC  arquivo de rc do shell do usuario
#   ORQ_HAS_APP   1 se a plataforma suporta o app nativo (so macOS)
#   ORQ_PTY       prefixo para rodar programa interativo (winpty no Windows)
# E as funcoes orq_pkg_hint <pacote> e orq_pkg_install <pacote>.
#
# O orquestra roda em macOS e Windows, so. No Windows tudo e programa do
# Windows — bash.exe e tmux.exe, instalados em Arquivos de Programas. Nao ha
# subsistema, maquina virtual, usuario nem senha envolvidos.

case "$(uname -s)" in
  Darwin)               ORQ_OS="macos" ;;
  MSYS*|MINGW*|CYGWIN*) ORQ_OS="windows" ;;
  *)                    ORQ_OS="desconhecido" ;;
esac

[ "$ORQ_OS" = "macos" ] && ORQ_HAS_APP=1 || ORQ_HAS_APP=0

# O claude do Windows e um executavel nativo: dentro do terminal ele precisa do
# winpty para receber teclado e desenhar a tela. Sem isso o agente sobe mudo e
# parece travado.
ORQ_PTY=""
if [ "$ORQ_OS" = "windows" ] && command -v winpty >/dev/null 2>&1; then
  ORQ_PTY="winpty"
fi

if   [ "$ORQ_OS" = "macos" ]   && command -v brew   >/dev/null 2>&1; then ORQ_PKG="brew"
elif [ "$ORQ_OS" = "windows" ] && command -v pacman >/dev/null 2>&1; then ORQ_PKG="pacman"
else                                                                      ORQ_PKG="none"
fi

orq_pkg_hint() {
  case "$ORQ_PKG" in
    brew)   echo "brew install $1" ;;
    pacman) echo "pacman -S --noconfirm --needed $1" ;;
    *)      echo "instale '$1' e deixe no PATH" ;;
  esac
}

orq_pkg_install() {
  case "$ORQ_PKG" in
    brew)   brew install "$1" ;;
    pacman) pacman -S --noconfirm --needed "$1" ;;
    *)      return 1 ;;
  esac
}

case "$(basename "${SHELL:-/bin/bash}")" in
  zsh)  ORQ_SHELL_RC="$HOME/.zshrc" ;;
  bash) ORQ_SHELL_RC="$HOME/.bashrc" ;;
  fish) ORQ_SHELL_RC="$HOME/.config/fish/config.fish" ;;
  *)    ORQ_SHELL_RC="$HOME/.profile" ;;
esac
# Cuidado: o valor de saida deste arquivo e o do ultimo comando, e quem faz o
# source usa "&& ... || fallback". Um teste falso na ultima linha derrubava o
# carregamento inteiro e a plataforma virava "desconhecido".
if [ "$ORQ_OS" = "windows" ]; then
  ORQ_SHELL_RC="$HOME/.bashrc"
fi
true
