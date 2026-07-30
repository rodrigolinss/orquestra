# instalar-no-windows.ps1 — instalacao do Orquestra no Windows.
#
# Tudo aqui e programa do Windows, instalado em Arquivos de Programas:
#   - MSYS2      da o bash.exe e o tmux.exe, que sao o motor do orquestra
#   - Git        o versionamento, que e como os agentes trabalham isolados
#   - Claude Code o agente, na versao nativa de Windows
# Nao ha subsistema, maquina virtual, distribuicao, usuario nem senha.
#
# Uso, no PowerShell:
#   irm https://raw.githubusercontent.com/rodrigolinss/orquestra/main/instalar-no-windows.ps1 | iex

$ErrorActionPreference = 'Stop'
$repo    = 'https://github.com/rodrigolinss/orquestra.git'
$msysDir = 'C:\msys64'

function Passo($t) { Write-Host "`n-> $t" -ForegroundColor Cyan }
function Ok($t)    { Write-Host "   ok: $t" -ForegroundColor Green }
function Aviso($t) { Write-Host "   aviso: $t" -ForegroundColor Yellow }
function Erro($t)  { Write-Host "`nERRO: $t" -ForegroundColor Red; exit 1 }

Write-Host "Orquestra — instalacao no Windows" -ForegroundColor White

# --- winget: o instalador de programas do proprio Windows ------------------
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  Erro ("o 'winget' nao foi encontrado. Ele vem no Windows 10 1809+ e no Windows 11.`n" +
        "      Atualize o 'Instalador de Aplicativo' pela Microsoft Store e rode de novo.")
}

# --- 1. Git ----------------------------------------------------------------
Passo "verificando o Git"
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  winget install --id Git.Git -e --source winget --accept-source-agreements --accept-package-agreements
  if ($LASTEXITCODE -ne 0) { Erro "nao consegui instalar o Git. Baixe em https://git-scm.com/downloads/win e rode de novo." }
  Ok "Git instalado"
} else { Ok "Git ja instalado" }

# --- 2. MSYS2 (bash.exe e tmux.exe) ----------------------------------------
# O tmux e o que mantem cada agente vivo na sua propria janela, deixa ler a
# tela sem interromper e continuar depois que voce fecha o terminal. O MSYS2
# entrega bash e tmux como executaveis de Windows.
Passo "verificando o MSYS2 (bash e tmux)"
if (-not (Test-Path "$msysDir\usr\bin\bash.exe")) {
  winget install --id MSYS2.MSYS2 -e --source winget --accept-source-agreements --accept-package-agreements
  if ($LASTEXITCODE -ne 0) { Erro "nao consegui instalar o MSYS2. Baixe em https://www.msys2.org e rode de novo." }
}
if (-not (Test-Path "$msysDir\usr\bin\bash.exe")) {
  Erro "o MSYS2 nao apareceu em $msysDir. Se voce instalou noutro lugar, edite `$msysDir no topo deste script."
}
Ok "MSYS2 em $msysDir"

$bashExe = "$msysDir\usr\bin\bash.exe"
function Bash($cmd) {
  $cmd = $cmd -replace "`r", ""
  & $bashExe -lc $cmd
}

# --- 3. Claude Code, versao nativa de Windows ------------------------------
Passo "verificando o Claude Code"
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  irm https://claude.ai/install.ps1 | iex
  $env:Path = "$env:USERPROFILE\.local\bin;$env:Path"
  if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Aviso "instalei o Claude Code mas ele ainda nao esta no PATH desta janela — feche e abra o PowerShell depois"
  } else { Ok "Claude Code instalado" }
} else { Ok "Claude Code ja instalado" }

# --- 4. tmux, jq e winpty dentro do MSYS2 ----------------------------------
# winpty faz o claude.exe (programa de Windows) receber teclado e desenhar a
# tela quando roda dentro de uma janela do tmux.
Passo "instalando tmux, jq e winpty"
Bash 'pacman -Syu --noconfirm --needed tmux jq winpty git >/dev/null 2>&1 || pacman -S --noconfirm --needed tmux jq winpty git'
if ($LASTEXITCODE -ne 0) { Erro "a instalacao de tmux/jq/winpty falhou. Abra o 'MSYS2 UCRT64' e rode: pacman -S tmux jq winpty" }
Ok "tmux, jq e winpty prontos"

# --- 5. Orquestra ----------------------------------------------------------
Passo "instalando o Orquestra"
Bash @"
set -e
export PATH="/c/Program Files/Git/cmd:`$HOME/.local/bin:`$PATH"
if [ -d "`$HOME/orquestra/.git" ]; then
  git -C "`$HOME/orquestra" pull --ff-only -q || true
else
  git clone -q $repo "`$HOME/orquestra"
fi
cd "`$HOME/orquestra"
bash install.sh
"@
if ($LASTEXITCODE -ne 0) { Erro "a instalacao do Orquestra falhou. A saida acima diz em que passo." }
Ok "Orquestra instalado"

# --- 6. atalho -------------------------------------------------------------
Passo "criando o atalho"
$cmd = Join-Path $env:USERPROFILE 'orquestra.cmd'
@"
@echo off
set MSYS2_PATH_TYPE=inherit
set CHERE_INVOKING=1
"$msysDir\usr\bin\bash.exe" -li -c "cd ~/orquestra && export PATH=\$HOME/orquestra/bin:\$PATH && exec bash"
"@ | Set-Content -Path $cmd -Encoding ASCII

$desktop = [Environment]::GetFolderPath('Desktop')
$shell   = New-Object -ComObject WScript.Shell
$lnk     = $shell.CreateShortcut((Join-Path $desktop 'Orquestra.lnk'))
$lnk.TargetPath  = $cmd
$lnk.Description = 'Orquestra — orquestrador de agentes'
$lnk.Save()
Ok "atalho 'Orquestra' criado no Desktop"

# --- 7. prova que funciona -------------------------------------------------
Passo "provando o fluxo completo (nao gasta token)"
Bash 'export PATH="$HOME/orquestra/bin:/c/Program Files/Git/cmd:$PATH"; nvo autoteste'

Write-Host ""
Write-Host "Pronto." -ForegroundColor Green
Write-Host ""
Write-Host "  1. abra o atalho 'Orquestra' no seu Desktop"
Write-Host "  2. rode 'claude' uma vez e faca login"
Write-Host "  3. nvo init ~/meu-projeto     <- a pasta do seu codigo"
Write-Host "     nvo maestro                <- o chefe; fale com ele em portugues"
