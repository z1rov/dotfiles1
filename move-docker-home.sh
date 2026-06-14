#!/usr/bin/env bash
# =============================================================================
#  move-docker-home.sh — Mueve el storage de Docker a /home/docker-data
# =============================================================================
set -Eeuo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'

log() { local l="$1"; shift
  case "$l" in
    ok)    echo -e "${GREEN}[OK]${RESET}    $*" ;;
    info)  echo -e "${CYAN}[INFO]${RESET}  $*" ;;
    warn)  echo -e "${YELLOW}[WARN]${RESET}  $*" ;;
    error) echo -e "${RED}[ERROR]${RESET} $*" ;;
    head)  echo -e "\n${BOLD}${CYAN}══════ $* ══════${RESET}" ;;
  esac
}

# ── Root check ────────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && { log error "Ejecuta como root: sudo ./move-docker-home.sh"; exit 1; }

DOCKER_NEW_ROOT="/home/docker-data/docker"
DAEMON_JSON="/etc/docker/daemon.json"

echo -e "${BOLD}${CYAN}"
cat << 'BANNER'
  ____             _
 |  _ \  ___   ___| | _____ _ __
 | | | |/ _ \ / __| |/ / _ \ '__|
 | |_| | (_) | (__|   <  __/ |
 |____/ \___/ \___|_|\_\___|_|
  → /home  mover
BANNER
echo -e "${RESET}"

# ── Espacio disponible ────────────────────────────────────────────────────────
log head "Verificando espacio"
AVAIL=$(df -BG /home | awk 'NR==2 {gsub("G","",$4); print $4}')
log info "Espacio disponible en /home: ${AVAIL}G"
[[ "$AVAIL" -lt 25 ]] && { log error "Menos de 25G libres en /home. Abortando."; exit 1; }
log ok "Espacio suficiente"

# ── Parar Docker ──────────────────────────────────────────────────────────────
log head "Parando Docker"
systemctl stop docker docker.socket 2>/dev/null || true
log ok "Docker detenido"

# ── Copiar datos ──────────────────────────────────────────────────────────────
log head "Copiando /var/lib/docker → ${DOCKER_NEW_ROOT}"
mkdir -p "$(dirname "$DOCKER_NEW_ROOT")"

if [[ -d /var/lib/docker ]]; then
  cp -a /var/lib/docker "$DOCKER_NEW_ROOT"
  log ok "Copia completa"
else
  mkdir -p "$DOCKER_NEW_ROOT"
  log warn "/var/lib/docker vacío — creando destino vacío"
fi

# ── daemon.json ───────────────────────────────────────────────────────────────
log head "Configurando daemon.json"
mkdir -p /etc/docker
cat > "$DAEMON_JSON" <<EOF
{
  "data-root": "${DOCKER_NEW_ROOT}"
}
EOF
log ok "daemon.json escrito → ${DAEMON_JSON}"

# ── Arrancar Docker ───────────────────────────────────────────────────────────
log head "Arrancando Docker"
systemctl start docker
sleep 2
docker info &>/dev/null && log ok "Docker daemon OK" || { log error "Docker no arrancó"; exit 1; }

# ── Verificar data-root ───────────────────────────────────────────────────────
log head "Verificación"
ACTUAL_ROOT=$(docker info 2>/dev/null | grep "Docker Root Dir" | awk '{print $NF}')
log info "Docker Root Dir: ${ACTUAL_ROOT}"

if [[ "$ACTUAL_ROOT" == "$DOCKER_NEW_ROOT" ]]; then
  log ok "Docker apunta correctamente a /home"
else
  log error "Docker Root Dir no coincide. Revisa ${DAEMON_JSON}"
  exit 1
fi

# ── Borrar original ───────────────────────────────────────────────────────────
log head "Limpiando /var/lib/docker original"
if [[ -d /var/lib/docker && "$(du -s /var/lib/docker | cut -f1)" -gt 0 ]]; then
  rm -rf /var/lib/docker
  log ok "/var/lib/docker eliminado"
else
  log warn "/var/lib/docker ya estaba vacío"
fi

# ── Resumen ───────────────────────────────────────────────────────────────────
log head "Listo"
df -h /home
echo ""
log info "Ahora puedes hacer el pull:"
log info "  sudo docker pull nwodtuhs/exegol:full-3.1.6"
