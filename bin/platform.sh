#!/usr/bin/env bash
# platform.sh — deteccao de plataforma, compartilhada por nvo e install.sh.
# Sourced, nunca executado direto. Define:
#   ORQ_OS        macos | wsl | linux | desconhecido
#   ORQ_PKG       brew | apt | dnf | pacman | none
#   ORQ_SHELL_RC  arquivo de rc do shell do usuario
#   ORQ_HAS_APP   1 se a plataforma suporta o app nativo (so macOS)
# E as funcoes orq_pkg_hint <pacote> e orq_pkg_install <pacote>.

case "$(uname -s)" in
  Darwin) ORQ_OS="macos" ;;
  Linux)
    # WSL se anuncia no /proc/version e via WSL_DISTRO_NAME
    if grep -qi microsoft /proc/version 2>/dev/null || [ -n "${WSL_DISTRO_NAME:-}" ]; then
      ORQ_OS="wsl"
    else
      ORQ_OS="linux"
    fi
    ;;
  *) ORQ_OS="desconhecido" ;;
esac

[ "$ORQ_OS" = "macos" ] && ORQ_HAS_APP=1 || ORQ_HAS_APP=0

if   command -v brew    >/dev/null 2>&1; then ORQ_PKG="brew"
elif command -v apt-get >/dev/null 2>&1; then ORQ_PKG="apt"
elif command -v dnf     >/dev/null 2>&1; then ORQ_PKG="dnf"
elif command -v pacman  >/dev/null 2>&1; then ORQ_PKG="pacman"
else                                          ORQ_PKG="none"
fi

orq_pkg_hint() {
  case "$ORQ_PKG" in
    brew)   echo "brew install $1" ;;
    apt)    echo "sudo apt-get install -y $1" ;;
    dnf)    echo "sudo dnf install -y $1" ;;
    pacman) echo "sudo pacman -S --noconfirm $1" ;;
    *)      echo "instale '$1' pelo gerenciador de pacotes do seu sistema" ;;
  esac
}

orq_pkg_install() {
  case "$ORQ_PKG" in
    brew)   brew install "$1" ;;
    apt)    sudo apt-get install -y "$1" ;;
    dnf)    sudo dnf install -y "$1" ;;
    pacman) sudo pacman -S --noconfirm "$1" ;;
    *)      return 1 ;;
  esac
}

case "$(basename "${SHELL:-/bin/bash}")" in
  zsh)  ORQ_SHELL_RC="$HOME/.zshrc" ;;
  bash) ORQ_SHELL_RC="$HOME/.bashrc" ;;
  fish) ORQ_SHELL_RC="$HOME/.config/fish/config.fish" ;;
  *)    ORQ_SHELL_RC="$HOME/.profile" ;;
esac
