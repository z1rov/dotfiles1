#!/usr/bin/env bash
# =============================================================================
#  exegol-install.sh — Exegol installer for Arch/Debian/Fedora
#  Smart storage migration + full install
# =============================================================================
set -Eeuo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'

ok()   { echo -e "${GREEN}[OK]${RESET}    $*"; }
info() { echo -e "${CYAN}[INFO]${RESET}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
err()  { echo -e "${RED}[ERROR]${RESET} $*"; }
step() { echo -e "\n${BOLD}${CYAN}───── $* ─────${RESET}"; }

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
cat << 'BANNER'
            Made by: z1rov
          OSCP | OSCP+ | BSCP
Repo: https://github.com/z1rov/dotfiles
BANNER
echo -e "${RESET}"

# ── Root check ────────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && { err "Run as root: sudo $0"; exit 1; }

# ── Config ────────────────────────────────────────────────────────────────────
DOCKER_SRC="/var/lib/docker"
CONTAINERD_SRC="/var/lib/containerd"
DAEMON_JSON="/etc/docker/daemon.json"
CONTAINERD_CFG="/etc/containerd/config.toml"
EXEGOL_IMAGE="nwodtuhs/exegol:full-3.1.6"
MIN_FREE_GB=25
USER_NAME="${SUDO_USER:-$USER}"
SHELL_RC="/home/${USER_NAME}/.zshrc"
[[ "$(basename "${SHELL:-bash}")" == "bash" ]] && SHELL_RC="/home/${USER_NAME}/.bashrc"

# =============================================================================
#  PHASE 1 — Detect distro
# =============================================================================
step "Detecting distro"

if   command -v pacman  &>/dev/null; then PKG_MGR="pacman"
elif command -v apt-get &>/dev/null; then PKG_MGR="apt"
elif command -v dnf     &>/dev/null; then PKG_MGR="dnf"
else err "Unsupported package manager (need pacman/apt/dnf)"; exit 1; fi

info "Package manager: ${PKG_MGR}"
info "Shell RC: ${SHELL_RC}"

# =============================================================================
#  PHASE 2 — Docker
# =============================================================================
step "Docker"

if command -v docker &>/dev/null; then
  ok "$(docker --version)"
else
  info "Installing Docker..."
  case "$PKG_MGR" in
    pacman) pacman -S --needed --noconfirm docker ;;
    *)      curl -fsSL "https://get.docker.com/" | sh ;;
  esac
  systemctl enable --now docker
  ok "Docker installed"
fi

# =============================================================================
#  PHASE 3 — Dependencies
# =============================================================================
step "Dependencies"

case "$PKG_MGR" in
  pacman) pacman -S --needed --noconfirm git python-pipx ;;
  apt)    apt-get update -qq && apt-get install -y git python3 pipx ;;
  dnf)    dnf install -y git python3 pipx ;;
esac

sudo -u "$USER_NAME" pipx ensurepath 2>/dev/null || true
export PATH="/home/${USER_NAME}/.local/bin:$PATH"
ok "git + pipx ready"

# =============================================================================
#  PHASE 4 — Exegol wrapper
# =============================================================================
step "Exegol wrapper"

if ! command -v exegol &>/dev/null; then
  sudo -u "$USER_NAME" pipx install exegol
  export PATH="/home/${USER_NAME}/.local/bin:$PATH"
fi

command -v exegol &>/dev/null \
  && ok "exegol → $(which exegol)" \
  || { err "exegol not in PATH"; exit 1; }

# =============================================================================
#  PHASE 5 — Alias
# =============================================================================
step "Alias"

ALIAS_LINE="alias exegol='sudo -E /home/${USER_NAME}/.local/bin/exegol'"
grep -q "alias exegol=" "${SHELL_RC}" 2>/dev/null \
  && ok "Alias already exists" \
  || { echo "${ALIAS_LINE}" >> "${SHELL_RC}"; ok "Alias added to ${SHELL_RC}"; }

# =============================================================================
#  PHASE 6 — Smart storage migration
# =============================================================================
step "Detecting best storage mount point"

BEST_MOUNT=""
BEST_FREE=0

while IFS= read -r line; do
  mnt=$(echo "$line" | awk '{print $6}')
  free_gb=$(echo "$line" | awk '{gsub("G","",$4); print int($4)}')
  fstype=$(findmnt -n -o FSTYPE "$mnt" 2>/dev/null || echo "unknown")

  [[ "$mnt" == "/boot"* ]] && continue
  [[ "$fstype" =~ ^(tmpfs|devtmpfs|sysfs|proc|cgroup|overlay)$ ]] && continue

  if [[ "$free_gb" -gt "$BEST_FREE" ]]; then
    BEST_FREE=$free_gb
    BEST_MOUNT=$mnt
  fi
done < <(df -BG --output=source,size,used,avail,pcent,target | tail -n +2)

[[ -z "$BEST_MOUNT" ]] && { err "Could not find a suitable mount point"; exit 1; }

DOCKER_DST="${BEST_MOUNT}/docker-data/docker"
CONTAINERD_DST="${BEST_MOUNT}/containerd-data/containerd"

info "Best mount point: ${BEST_MOUNT} (${BEST_FREE}G free)"
[[ "$BEST_FREE" -lt "$MIN_FREE_GB" ]] && { err "Not enough space — need at least ${MIN_FREE_GB}G"; exit 1; }
ok "Space check passed"

step "Analyzing current storage usage"

DOCKER_SIZE=0
CONTAINERD_SIZE=0

if [[ -d "$DOCKER_SRC" && -n "$(ls -A "$DOCKER_SRC" 2>/dev/null)" ]]; then
  DOCKER_SIZE=$(du -sB1G "$DOCKER_SRC" 2>/dev/null | awk '{print $1}')
  info "Docker storage:     ${DOCKER_SIZE}G  (${DOCKER_SRC})"
else
  info "Docker storage:     empty / not found"
fi

if [[ -d "$CONTAINERD_SRC" && -n "$(ls -A "$CONTAINERD_SRC" 2>/dev/null)" ]]; then
  CONTAINERD_SIZE=$(du -sB1G "$CONTAINERD_SRC" 2>/dev/null | awk '{print $1}')
  info "Containerd storage: ${CONTAINERD_SIZE}G  (${CONTAINERD_SRC})"
else
  info "Containerd storage: empty / not found"
fi

TOTAL_NEEDED=$(( DOCKER_SIZE + CONTAINERD_SIZE + 5 ))
info "Space needed (+ 5G buffer): ~${TOTAL_NEEDED}G"

[[ "$BEST_FREE" -lt "$TOTAL_NEEDED" ]] && {
  err "Not enough space on ${BEST_MOUNT}. Need ~${TOTAL_NEEDED}G, have ${BEST_FREE}G"
  exit 1
}
ok "Space is sufficient"

# ── Check if migration already done ───────────────────────────────────────────
CURRENT_DOCKER_ROOT=""
command -v docker &>/dev/null && \
  CURRENT_DOCKER_ROOT=$(docker info 2>/dev/null | awk '/Docker Root Dir/{print $NF}') || true

CURRENT_CONTAINERD_ROOT=""
[[ -f "$CONTAINERD_CFG" ]] && \
  CURRENT_CONTAINERD_ROOT=$(awk '/^root/{print $3}' "$CONTAINERD_CFG" | tr -d '"') || true

if [[ "$CURRENT_DOCKER_ROOT" == "$DOCKER_DST" && "$CURRENT_CONTAINERD_ROOT" == "$CONTAINERD_DST" ]]; then
  ok "Docker + Containerd already on ${BEST_MOUNT} — skipping migration"
else
  step "Migrating Docker + Containerd to ${BEST_MOUNT}"
  systemctl stop docker docker.socket containerd 2>/dev/null || true
  ok "Services stopped"

  # Docker
  mkdir -p "$(dirname "$DOCKER_DST")"
  if [[ -d "$DOCKER_SRC" && -n "$(ls -A "$DOCKER_SRC" 2>/dev/null)" ]]; then
    info "Moving Docker storage..."
    cp -a "$DOCKER_SRC" "$DOCKER_DST"
    rm -rf "$DOCKER_SRC"
    ok "Docker storage moved"
  else
    mkdir -p "$DOCKER_DST"
    warn "Docker source empty — created empty destination"
  fi

  mkdir -p /etc/docker
  cat > "$DAEMON_JSON" <<EOF
{
  "data-root": "${DOCKER_DST}"
}
EOF
  ok "daemon.json updated"

  # Containerd
  mkdir -p "$(dirname "$CONTAINERD_DST")"
  if [[ -d "$CONTAINERD_SRC" && -n "$(ls -A "$CONTAINERD_SRC" 2>/dev/null)" ]]; then
    info "Moving Containerd storage..."
    cp -a "$CONTAINERD_SRC" "$CONTAINERD_DST"
    rm -rf "$CONTAINERD_SRC"
    ok "Containerd storage moved"
  else
    mkdir -p "$CONTAINERD_DST"
    warn "Containerd source empty — created empty destination"
  fi

  mkdir -p /etc/containerd
  containerd config default > "$CONTAINERD_CFG" 2>/dev/null || true
  if grep -q "^root" "$CONTAINERD_CFG" 2>/dev/null; then
    sed -i "s|^root = .*|root = \"${CONTAINERD_DST}\"|" "$CONTAINERD_CFG"
  else
    sed -i "1s|^|root = \"${CONTAINERD_DST}\"\n|" "$CONTAINERD_CFG"
  fi
  ok "Containerd config updated"

  # Restart
  systemctl start containerd && sleep 2
  systemctl start docker     && sleep 2
  docker info &>/dev/null && ok "Docker daemon running" || { err "Docker failed to start"; exit 1; }

  ACTUAL=$(docker info 2>/dev/null | awk '/Docker Root Dir/{print $NF}')
  info "Docker Root Dir: ${ACTUAL}"
  [[ "$ACTUAL" != "$DOCKER_DST" ]] && { err "Root mismatch — check ${DAEMON_JSON}"; exit 1; }
  ok "Migration complete"
fi

# =============================================================================
#  PHASE 7 — Pull Exegol image
# =============================================================================
step "Pulling Exegol image (${EXEGOL_IMAGE})"
warn "This will take a while — ~20 GB"

if docker image inspect "$EXEGOL_IMAGE" &>/dev/null; then
  ok "Image already present — skipping pull"
else
  if docker pull "$EXEGOL_IMAGE"; then
    ok "Image pulled successfully"
  else
    err "Pull failed — check space and connectivity"
    df -h "$BEST_MOUNT"
    exit 1
  fi
fi

# =============================================================================
#  PHASE 8 — Final verification
# =============================================================================
step "Final verification"

docker info &>/dev/null && ok "Docker daemon OK" || err "Docker not responding"
command -v exegol &>/dev/null && ok "exegol in PATH" || warn "Restart terminal to apply PATH"
echo ""
docker images | grep -E "REPOSITORY|exegol" || true
echo ""
df -h "$BEST_MOUNT"
echo ""
info "Start your first container:  sudo -E exegol start"
