#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# GLOBALS
# ============================================================
USER_NAME="${SUDO_USER:-$USER}"
SUDO_FILE="/etc/sudoers.d/99_${USER_NAME}"
DOTFILES_REPO="https://github.com/z1rov/dotfiles"
BLACKARCH_STRAP="https://blackarch.org/strap.sh"

BANNER="
            Made by: z1rov
          OSCP | OSCP+ | CRTO
Repo: https://github.com/z1rov/dotfiles
"

# ============================================================
# COLORS / MINIMAL LOG (only [+] / [-])
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
RESET='\033[0m'

ok()  { echo -e "${GREEN}[+]${RESET} $*"; }
err() { echo -e "${RED}[-]${RESET} $*"; }

# Wraps a command, hides ALL its stdout/stderr, only prints [+]/[-]
run() {
  local msg="$1"; shift
  if "$@" &>/dev/null; then
    ok "$msg"
  else
    err "$msg"
  fi
}

banner() {
  clear
  echo -e "$BANNER"
}

# ============================================================
# CHECKS
# ============================================================
[[ $EUID -eq 0 ]] && {
  err "Do not run as root"
  exit 1
}

# ============================================================
# SINGLE CONFIRM
# ============================================================
banner
read -rp "Continue installation? (Y/n): " ans
ans=${ans,,}
[[ -n "$ans" && "$ans" != "y" && "$ans" != "yes" ]] && exit 0

# ============================================================
# SUDO (ONCE)
# ============================================================
sudo -v &>/dev/null && ok "sudo cached" || { err "sudo authentication failed"; exit 1; }

run_sudo() {
  sudo "$@"
}

# ============================================================
# SUDO NOPASSWD
# ============================================================
setup_sudo() {
  run_sudo sh -c "echo '$USER_NAME ALL=(ALL) NOPASSWD: ALL' > '$SUDO_FILE'" &>/dev/null
  run_sudo chmod 440 "$SUDO_FILE"

  if run_sudo visudo -cf "$SUDO_FILE" &>/dev/null; then
    ok "sudo NOPASSWD configured"
  else
    run_sudo rm -f "$SUDO_FILE"
    err "invalid sudoers file, reverted"
    exit 1
  fi
}

# ============================================================
# PACKAGE INSTALL
# ============================================================
install_pacman() {
  for pkg in "$@"; do
    if pacman -Qi "$pkg" &>/dev/null; then
      ok "$pkg already installed"
    elif run_sudo pacman -S --needed --noconfirm "$pkg" &>/dev/null; then
      ok "$pkg installed"
    else
      err "$pkg failed"
    fi
  done
}

install_yay() {
  command -v yay &>/dev/null || { err "yay not found, skipping AUR packages"; return; }

  for pkg in "$@"; do
    if yay -Qi "$pkg" &>/dev/null; then
      ok "$pkg already installed"
    elif yay -S --needed --noconfirm "$pkg" &>/dev/null; then
      ok "$pkg installed"
    else
      err "$pkg failed"
    fi
  done
}

# ============================================================
# YAY
# ============================================================
setup_yay() {
  if command -v yay &>/dev/null; then
    ok "yay already installed"
    return
  fi

  run_sudo pacman -S --needed --noconfirm git base-devel &>/dev/null

  tmpdir="$(mktemp -d)"
  if git clone https://aur.archlinux.org/yay.git "$tmpdir/yay" &>/dev/null; then
    (cd "$tmpdir/yay" && makepkg -si --noconfirm &>/dev/null) && ok "yay installed" || err "yay build failed"
  else
    err "failed to clone yay"
  fi
  rm -rf "$tmpdir"
}

# ============================================================
# BLACKARCH
# ============================================================
setup_blackarch() {
  if pacman -Sl blackarch &>/dev/null; then
    ok "blackarch repo already configured"
    return
  fi

  tmp="$(mktemp)"
  if curl -fsSL "$BLACKARCH_STRAP" -o "$tmp" &>/dev/null && run_sudo bash "$tmp" &>/dev/null; then
    ok "blackarch repository added"
  else
    err "failed to add blackarch repository"
  fi
  rm -f "$tmp"
  run_sudo pacman -Sy &>/dev/null
}

# ============================================================
# BURPSUITE (install + patch launcher)
# ============================================================
setup_burpsuite() {
  install_pacman burpsuite

  local found
  found="$(run_sudo find /usr -maxdepth 5 -type f -name burpsuite 2>/dev/null | head -n1)"
  [[ -z "$found" ]] && found="/usr/local/bin/burpsuite"

  if run_sudo tee "$found" >/dev/null <<'EOF'
#!/bin/sh
_JAVA_AWT_WM_NONREPARENTING=1 java \
  -Dswing.defaultlaf=javax.swing.plaf.metal.MetalLookAndFeel \
  -Dsun.java2d.opengl=false \
  -Dsun.java2d.xrender=false \
  -Dsun.java2d.pmoffscreen=false \
  -Dswing.noxp=true \
  -Dswing.metalTheme=steel \
  -jar /usr/share/burpsuite/burpsuite.jar "$@"
EOF
  then
    run_sudo chmod +x "$found"
    ok "burpsuite launcher patched ($found)"
  else
    err "failed to patch burpsuite launcher"
  fi
}

# ============================================================
# DOCKER
# ============================================================
setup_docker() {
  if command -v docker &>/dev/null; then
    ok "docker already installed"
  else
    run_sudo pacman -S --needed --noconfirm docker docker-compose &>/dev/null \
      && ok "docker installed" || { err "docker install failed"; return; }
  fi

  run_sudo systemctl enable --now docker &>/dev/null && ok "docker service enabled"

  if ! getent group docker | grep -q "\b${USER_NAME}\b"; then
    run_sudo usermod -aG docker "$USER_NAME" && ok "$USER_NAME added to docker group"
  else
    ok "$USER_NAME already in docker group"
  fi
}

# ============================================================
# HTB-OPERATOR
# ============================================================
setup_htb_operator() {
  if ! command -v pipx &>/dev/null; then
    run_sudo pacman -S --needed --noconfirm python-pipx &>/dev/null || { err "pipx install failed"; return; }
    pipx ensurepath &>/dev/null || true
    export PATH="$HOME/.local/bin:$PATH"
  fi

  if pipx list 2>/dev/null | grep -q "htb-operator"; then
    ok "htb-operator already installed"
  else
    pipx install htb-operator &>/dev/null && ok "htb-operator installed" || err "htb-operator install failed"
  fi
}

# ============================================================
# SERVICES
# ============================================================
setup_services() {
  run_sudo systemctl enable NetworkManager lxdm &>/dev/null
  run_sudo systemctl start NetworkManager &>/dev/null
  echo "exec bspwm" > ~/.xinitrc
  run_sudo chsh -s /bin/zsh "$USER_NAME" &>/dev/null
  ok "services configured"
}

# ============================================================
# ZSH (fully unattended, no prompts)
# ============================================================
setup_zsh() {
  if [[ -d ~/.oh-my-zsh ]]; then
    ok "oh-my-zsh already installed"
  else
    if CHSH=no RUNZSH=no KEEP_ZSHRC=yes sh -c \
      "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
      "" --unattended &>/dev/null; then
      ok "oh-my-zsh installed"
    else
      err "oh-my-zsh install failed"
    fi
  fi

  ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"

  git clone https://github.com/zsh-users/zsh-autosuggestions \
    "$ZSH_CUSTOM/plugins/zsh-autosuggestions" &>/dev/null \
    && ok "zsh-autosuggestions added" || ok "zsh-autosuggestions already present"

  git clone https://github.com/zsh-users/zsh-syntax-highlighting \
    "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" &>/dev/null \
    && ok "zsh-syntax-highlighting added" || ok "zsh-syntax-highlighting already present"
}

# ============================================================
# DOTFILES
# ============================================================
setup_dotfiles() {
  DOTDIR="$HOME/dotfiles"

  if [[ -d "$DOTDIR/.git" ]]; then
    git -C "$DOTDIR" pull &>/dev/null && ok "dotfiles updated"
  else
    git clone "$DOTFILES_REPO" "$DOTDIR" &>/dev/null && ok "dotfiles cloned" || { err "dotfiles clone failed"; return; }
  fi

  mkdir -p "$HOME/.config"

  [[ -d "$DOTDIR/config" ]] && { cp -r "$DOTDIR/config/"* "$HOME/.config/"; ok "config/ deployed"; }
  [[ -f "$DOTDIR/home/.zshrc" ]] && { cp "$DOTDIR/home/.zshrc" "$HOME/"; ok ".zshrc deployed"; }
  [[ -d "$DOTDIR/home/.mozilla" ]] && { cp -r "$DOTDIR/home/.mozilla" "$HOME/"; ok ".mozilla deployed"; }
  [[ -d "$DOTDIR/home/.local" ]] && { cp -r "$DOTDIR/home/.local" "$HOME/"; ok ".local deployed"; }

  if [[ -d "$DOTDIR/bin" ]]; then
    while IFS= read -r -d '' binfile; do
      bname=$(basename "$binfile")
      [[ "$bname" == .* || "$bname" == README* || "$bname" == LICENSE* ]] && continue
      [[ ! -f "$binfile" ]] && continue
      if run_sudo cp "$binfile" "/usr/bin/$bname" && run_sudo chmod +x "/usr/bin/$bname"; then
        ok "$bname deployed"
      else
        err "$bname deploy failed"
      fi
    done < <(find "$DOTDIR/bin" -maxdepth 1 -type f -print0)
  fi

  [[ -f "$HOME/.config/bspwm/bspwmrc" ]] && chmod +x "$HOME/.config/bspwm/bspwmrc"
  [[ -d "$HOME/.config/bspwm/scripts" ]] && find "$HOME/.config/bspwm/scripts" -type f -exec chmod 755 {} \;

  mkdir -p "$HOME/Documents" "$HOME/Downloads" "$HOME/CTF"
  ok "dotfiles deployed"
}

# ============================================================
# ROOT SYNC
# ============================================================
setup_root() {
  run_sudo chsh -s /bin/zsh root &>/dev/null
  run_sudo cp -r ~/.oh-my-zsh /root/ &>/dev/null
  run_sudo cp ~/.zshrc /root/ &>/dev/null
  run_sudo cp -r ~/.config /root/ &>/dev/null
  ok "root synced"
}

# ============================================================
# SSH
# ============================================================
setup_ssh() {
  read -rp "Generate SSH keys? (Y/n): " ans
  ans=${ans,,}
  [[ -n "$ans" && "$ans" != "y" && "$ans" != "yes" ]] && return

  DEFAULT_USER="$USER_NAME"

  echo -e "Choose SSH key mode:\n  1) Default — no passphrase\n  2) Secure  — with passphrase (recommended)"
  read -rp "Select option [1]: " mode
  [[ "$mode" != "2" ]] && mode=1

  read -rp "SSH key label [${DEFAULT_USER}]: " SSH_USER
  SSH_USER="${SSH_USER:-$DEFAULT_USER}"

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  PASSPHRASE_RSA=""
  PASSPHRASE_ED25519=""

  if [[ "$mode" == "2" ]]; then
    while true; do
      read -s -p "RSA passphrase: " p1; echo
      read -s -p "Confirm: " p2; echo
      [[ "$p1" == "$p2" ]] && PASSPHRASE_RSA="$p1" && break
      err "passphrases do not match"
    done

    read -s -p "ED25519 passphrase (ENTER = reuse RSA): " q1; echo
    if [[ -z "$q1" ]]; then
      PASSPHRASE_ED25519="$PASSPHRASE_RSA"
    else
      while true; do
        read -s -p "Confirm ED25519: " q2; echo
        [[ "$q1" == "$q2" ]] && PASSPHRASE_ED25519="$q1" && break
        err "passphrases do not match"
      done
    fi
  fi

  generate_key() {
    local path="$1" type="$2" bits="$3" pass="$4"

    if [[ -f "$path" ]]; then
      read -rp "[!] $path exists — overwrite? (y/N): " ow
      [[ "${ow,,}" != "y" ]] && return
      cp "$path" "$path.bak" 2>/dev/null || true
      cp "$path.pub" "$path.pub.bak" 2>/dev/null || true
      rm -f "$path" "$path.pub"
    fi

    if [[ "$type" == "rsa" ]]; then
      ssh-keygen -t rsa -b "$bits" -f "$path" -C "${SSH_USER}@$(hostname)" -N "$pass" -q
    else
      ssh-keygen -t ed25519 -f "$path" -C "${SSH_USER}@$(hostname)" -N "$pass" -q
    fi

    chmod 600 "$path"
    chmod 644 "$path.pub"
    ok "$type key generated"
  }

  generate_key "$HOME/.ssh/id_rsa"     "rsa"     4096 "$PASSPHRASE_RSA"
  generate_key "$HOME/.ssh/id_ed25519" "ed25519" ""   "$PASSPHRASE_ED25519"

  [[ -f ~/.ssh/id_rsa.pub ]] && { echo "--- id_rsa.pub ---"; cat ~/.ssh/id_rsa.pub; echo; }
  [[ -f ~/.ssh/id_ed25519.pub ]] && { echo "--- id_ed25519.pub ---"; cat ~/.ssh/id_ed25519.pub; echo; }
}

# ============================================================
# VMWARE DETECTION
# ============================================================
setup_vmware() {
  if ! systemd-detect-virt --quiet --vm 2>/dev/null | grep -q vmware && \
     ! grep -qi "vmware" /sys/class/dmi/id/sys_vendor 2>/dev/null; then
    return
  fi

  if run_sudo pacman -S --needed --noconfirm open-vm-tools gtkmm3 &>/dev/null; then
    ok "open-vm-tools + gtkmm3 installed"
  else
    err "open-vm-tools install failed"
    return
  fi

  run_sudo systemctl enable vmtoolsd.service &>/dev/null
  run_sudo systemctl start  vmtoolsd.service &>/dev/null
  ok "vmtoolsd enabled"

  run_sudo systemctl enable vmware-vmblock-fuse.service &>/dev/null
  run_sudo systemctl start  vmware-vmblock-fuse.service &>/dev/null
  ok "vmware-vmblock-fuse enabled"

  BSPWMRC="$HOME/.config/bspwm/bspwmrc"
  if [[ -f "$BSPWMRC" ]]; then
    if ! grep -q "vmware-user" "$BSPWMRC"; then
      {
        echo ""
        echo "# VMware clipboard & drag-drop"
        echo "pgrep vmware-user || vmware-user &"
      } >> "$BSPWMRC"
      ok "vmware-user added to bspwmrc"
    else
      ok "vmware-user already in bspwmrc"
    fi
  else
    err "bspwmrc not found — add 'pgrep vmware-user || vmware-user &' manually"
  fi
}

# ============================================================
# PACKAGES
# ============================================================
PACMAN_PKGS=(
  xorg xorg-xinit bspwm sxhkd picom feh lxdm
  kitty zsh tmux neovim rofi thunar gvfs ttf-jetbrains-mono
  bat eza xclip brightnessctl pamixer firefox
  pipewire pipewire-pulse wireplumber papirus-icon-theme
  dunst flameshot gnome-themes-extra
  linux linux-firmware mesa opencl-mesa xf86-video-amdgpu polybar nodejs npm
)

YAY_PKGS=( i3lock-color ttf-hack-nerd ttf-firacode-nerd )

# ============================================================
# MAIN
# ============================================================
setup_sudo
setup_yay
install_pacman "${PACMAN_PKGS[@]}"
install_yay "${YAY_PKGS[@]}"
setup_blackarch
setup_burpsuite
setup_docker
setup_htb_operator
setup_services
setup_zsh
setup_dotfiles
setup_vmware
setup_root
setup_ssh

run_sudo dracut --regenerate-all --force &>/dev/null && ok "initramfs regenerated"

banner
ok "installation finished"
