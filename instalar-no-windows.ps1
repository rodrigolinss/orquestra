# instalar-no-windows.ps1 — instalacao do Orquestra no Windows, sem perguntas.
#
# O motor do Orquestra e bash + tmux, que nao existem no Windows nativo, entao
# ele mora dentro do WSL2 — um recurso do proprio Windows. Este script cuida
# disso inteiro: liga o WSL, instala o Ubuntu SEM criar usuario nem senha
# (roda como root, entao nao ha login nem sudo), instala as dependencias, o
# Node, o Claude Code e o Orquestra, e cria um atalho no seu Desktop.
#
# Uso, no PowerShell como administrador:
#   irm https://raw.githubusercontent.com/rodrigolinss/orquestra/main/instalar-no-windows.ps1 | iex

$ErrorActionPreference = 'Stop'
$distro = 'Ubuntu'
$repo   = 'https://github.com/rodrigolinss/orquestra.git'

function Passo($t) { Write-Host "`n-> $t" -ForegroundColor Cyan }
function Ok($t)    { Write-Host "   ok: $t" -ForegroundColor Green }
function Aviso($t) { Write-Host "   aviso: $t" -ForegroundColor Yellow }
function Erro($t)  { Write-Host "`nERRO: $t" -ForegroundColor Red; exit 1 }

Write-Host "Orquestra — instalacao no Windows" -ForegroundColor White

# --- administrador ---------------------------------------------------------
$souAdmin = ([Security.Principal.WindowsPrincipal] `
  [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $souAdmin) {
  Erro "abra o PowerShell como administrador e rode de novo.`n" +
       "      (menu Iniciar -> digite PowerShell -> botao direito -> Executar como administrador)"
}

# --- 1. WSL ----------------------------------------------------------------
Passo "verificando o WSL"
$wslOk = $false
try { wsl.exe --status *> $null; $wslOk = ($LASTEXITCODE -eq 0) } catch { $wslOk = $false }

if (-not $wslOk) {
  Passo "ligando o WSL (recurso do Windows) — isso pede um reinicio"
  wsl.exe --install --no-launch --no-distribution
  Write-Host ""
  Write-Host "REINICIE O COMPUTADOR e rode este mesmo comando de novo." -ForegroundColor Yellow
  Write-Host "Da segunda vez ele termina sozinho, sem perguntar nada." -ForegroundColor Yellow
  exit 0
}
Ok "WSL disponivel"

# --- 2. Ubuntu, sem criar usuario nem senha --------------------------------
# --no-launch e o que evita o prompt de "crie um nome de usuario e uma senha":
# a distro fica instalada e nunca abre o assistente de primeiro uso. Sem
# usuario criado, o padrao e root — e root no WSL nao tem senha nem sudo.
$instalado = (wsl.exe --list --quiet) -replace "`0", "" | Where-Object { $_.Trim() -eq $distro }
if (-not $instalado) {
  Passo "instalando o $distro (sem criar usuario nem senha)"
  wsl.exe --install --no-launch -d $distro
  if ($LASTEXITCODE -ne 0) { Erro "nao consegui instalar o $distro. Rode 'wsl --install -d $distro' e me diga o erro." }
  Ok "$distro instalado"
} else {
  Ok "$distro ja instalado"
}

Passo "deixando o root como usuario padrao (sem login, sem senha)"
& "$distro.exe" config --default-user root 2>$null
if ($LASTEXITCODE -ne 0) { Aviso "nao consegui fixar o usuario padrao; seguindo com --user root" }

# --- 3. Orquestra dentro do Ubuntu ----------------------------------------
# Tudo numa chamada so, como root: sem senha, sem prompt, sem interacao.
Passo "instalando dependencias, Claude Code e Orquestra (demora alguns minutos)"
$bash = @"
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq git tmux jq curl ca-certificates >/dev/null
if [ -d /root/orquestra/.git ]; then
  git -C /root/orquestra pull --ff-only -q || true
else
  git clone -q $repo /root/orquestra
fi
cd /root/orquestra
bash install.sh --tudo
"@
$bash = $bash -replace "`r", ""
wsl.exe -d $distro -u root -- bash -lc $bash
if ($LASTEXITCODE -ne 0) { Erro "a instalacao dentro do $distro falhou. A saida acima diz em que passo." }

# --- 4. atalho no Windows --------------------------------------------------
Passo "criando o atalho"
$cmd = Join-Path $env:USERPROFILE 'orquestra.cmd'
@"
@echo off
wsl -d $distro -u root --cd /root/orquestra -- bash -lc "export PATH=/root/orquestra/bin:\$PATH; exec bash"
"@ | Set-Content -Path $cmd -Encoding ASCII

$desktop  = [Environment]::GetFolderPath('Desktop')
$atalho   = Join-Path $desktop 'Orquestra.lnk'
$shell    = New-Object -ComObject WScript.Shell
$lnk      = $shell.CreateShortcut($atalho)
$lnk.TargetPath = $cmd
$lnk.Description = 'Orquestra — orquestrador de agentes'
$lnk.Save()
Ok "atalho 'Orquestra' criado no Desktop"

# --- 5. prova que funciona -------------------------------------------------
Passo "provando o fluxo completo (nao gasta token)"
wsl.exe -d $distro -u root -- bash -lc "/root/orquestra/bin/nvo autoteste"

Write-Host ""
Write-Host "Pronto." -ForegroundColor Green
Write-Host ""
Write-Host "  1. abra o atalho 'Orquestra' no seu Desktop"
Write-Host "  2. rode 'claude' uma vez e faca login (abre o navegador do Windows)"
Write-Host "  3. nvo init ~/meu-projeto     <- a pasta do seu codigo"
Write-Host "     nvo maestro                <- o chefe; fale com ele em portugues"
Write-Host ""
Write-Host "Nao foi criado nenhum usuario nem senha de Linux." -ForegroundColor DarkGray
