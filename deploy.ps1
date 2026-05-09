# deploy.ps1 - Deploiement GoldSignal sur VPS
# Usage : .\deploy.ps1

$ErrorActionPreference = "Stop"

# ── Configuration ────────────────────────────────────────────────
$VPS_IP     = "31.220.86.31"
$VPS_USER   = "root"
$SSH_KEY    = "C:\Users\iboul\.ssh\id_ed25519"
$REMOTE_DIR = "/opt/goldsignal"

$BACKEND_DIR = "$PSScriptRoot\backend"
$SSH_TARGET  = "${VPS_USER}@${VPS_IP}"

# Helper : ecrit un script bash (LF) dans /tmp sur le VPS puis l'execute
function Run-Remote([string]$script, [string]$label) {
    Write-Host "  >> $label" -ForegroundColor DarkGray
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(
        $script.Replace("`r`n", "`n").Replace("`r", "`n")
    )
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "gs_$(Get-Random).sh"
    [System.IO.File]::WriteAllBytes($tmp, $bytes)
    try {
        & scp -i $SSH_KEY -o StrictHostKeyChecking=no -q $tmp "${SSH_TARGET}:/tmp/gs_cmd.sh"
        if ($LASTEXITCODE -ne 0) { throw "scp echoue" }
        & ssh -i $SSH_KEY -o StrictHostKeyChecking=no $SSH_TARGET "bash /tmp/gs_cmd.sh; rm -f /tmp/gs_cmd.sh"
        if ($LASTEXITCODE -ne 0) { throw "Script distant echoue : $label" }
    } finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  GoldSignal - Deploiement VPS $VPS_IP" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# ── 1. Test SSH ───────────────────────────────────────────────────
Write-Host "[1/5] Test de la connexion SSH..." -ForegroundColor Yellow
Run-Remote "echo 'Connexion OK'" "echo OK"
Write-Host "      OK" -ForegroundColor Green

# ── 2. Installation Docker si absent ─────────────────────────────
Write-Host "[2/5] Verification / installation de Docker..." -ForegroundColor Yellow
Run-Remote @'
set -e
if ! command -v docker &>/dev/null; then
    echo "Docker absent - installation..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
else
    echo "Docker present : $(docker --version)"
fi
if ! docker compose version &>/dev/null 2>&1; then
    apt-get install -y docker-compose-plugin
    echo "docker-compose-plugin installe"
else
    echo "Docker Compose : $(docker compose version)"
fi
'@ "check/install Docker"
Write-Host "      OK" -ForegroundColor Green

# ── 3. Dossier distant ───────────────────────────────────────────
Write-Host "[3/5] Creation du dossier distant $REMOTE_DIR..." -ForegroundColor Yellow
Run-Remote "mkdir -p $REMOTE_DIR && echo 'OK'" "mkdir $REMOTE_DIR"
Write-Host "      OK" -ForegroundColor Green

# ── 4. Transfert des fichiers ─────────────────────────────────────
Write-Host "[4/5] Transfert des fichiers vers le VPS..." -ForegroundColor Yellow

$TMP_ARCHIVE = Join-Path ([System.IO.Path]::GetTempPath()) "goldsignal_$(Get-Random).tar.gz"

Write-Host "      Creation de l'archive locale (sans bin/obj)..." -ForegroundColor DarkGray
Push-Location $BACKEND_DIR
try {
    & tar -czf $TMP_ARCHIVE `
        --exclude='./.git' `
        --exclude='./GoldSignal.Ai.Api/bin' `
        --exclude='./GoldSignal.Ai.Api/obj' `
        --exclude='./GoldSignal.Dashboard/bin' `
        --exclude='./GoldSignal.Dashboard/obj' `
        .
    if ($LASTEXITCODE -ne 0) { throw "tar a echoue" }
} finally {
    Pop-Location
}

Write-Host "      Upload de l'archive..." -ForegroundColor DarkGray
& scp -i $SSH_KEY -o StrictHostKeyChecking=no $TMP_ARCHIVE "${SSH_TARGET}:/tmp/goldsignal.tar.gz"
if ($LASTEXITCODE -ne 0) { throw "scp archive echoue" }
Remove-Item $TMP_ARCHIVE -Force

Write-Host "      Extraction sur le VPS..." -ForegroundColor DarkGray
Run-Remote "tar -xzf /tmp/goldsignal.tar.gz -C $REMOTE_DIR && rm /tmp/goldsignal.tar.gz && echo 'Extraction OK'" "extract archive"
Write-Host "      OK" -ForegroundColor Green

# ── 5. Docker Compose up ──────────────────────────────────────────
Write-Host "[5/5] Lancement de docker compose..." -ForegroundColor Yellow
$COMPOSE_SCRIPT = @"
set -e
cd $REMOTE_DIR
echo '--- Arret des anciens conteneurs ---'
docker compose down --remove-orphans || true
echo '--- Build et demarrage ---'
docker compose up -d --build
echo '--- Statut ---'
docker compose ps
"@
Run-Remote $COMPOSE_SCRIPT "docker compose up --build"
Write-Host "      OK" -ForegroundColor Green

# ── Résumé ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "  Deploiement termine avec succes !" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  API       : http://${VPS_IP}:5010/swagger" -ForegroundColor Cyan
Write-Host "  Dashboard : http://${VPS_IP}:5011"         -ForegroundColor Cyan
Write-Host ""
Write-Host "  Logs : ssh -i $SSH_KEY ${SSH_TARGET} 'docker compose -f $REMOTE_DIR/docker-compose.yml logs -f'"
