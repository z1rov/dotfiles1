#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# GLOBALS
# ============================================================
USER_NAME="${SUDO_USER:-$USER}"
SUDO_FILE="/etc/sudoers.d/99_${USER_NAME}"
DOTFILES_REPO="https://github.com/z1rov/dotfiles"

BANNER="
            Made by: z1rov
          OSCP | OSCP+ | CRTO
Repo: https://github.com/z1rov/dotfiles
"

# ============================================================
# COLORS / LOG
# ============================================================
GRN='\033[0;32m'
RED='\033[0;31m'
RST='\033[0m'

ok()  { echo -e "${GRN}[+]${RST} $*"; }
err() { echo -e "${RED}[-]${RST} $*"; }
inf() { echo -e "    $*"; }

# ============================================================
# UI
# ============================================================
banner() {
  clear
  echo -e "$BANNER\n"
}

step() {
  echo -e "\n[*] $1"
}

# ============================================================
# CHECKS
# ============================================================
[[ $EUID -eq 0 ]] && { echo "[-] Do not run as root"; exit 1; }

# ============================================================
# CONFIRM
# ============================================================
banner
read -rp "Continue installation? (Y/n): " ans
ans=${ans,,}
[[ -n "$ans" && "$ans" != "y" && "$ans" != "yes" ]] && exit 0

# ============================================================
# SUDO
# ============================================================
step "Caching sudo"
sudo -v
run_sudo() { sudo "$@"; }

# ============================================================
# SUDO NOPASSWD
# ============================================================
setup_sudo() {
  step "Configuring sudo NOPASSWD"
  run_sudo sh -c "echo '$USER_NAME ALL=(ALL) NOPASSWD: ALL' > '$SUDO_FILE'"
  run_sudo chmod 440 "$SUDO_FILE"
  run_sudo visudo -cf "$SUDO_FILE" || {
    run_sudo rm -f "$SUDO_FILE"
    err "Invalid sudoers file — reverted"
    exit 1
  }
  ok "sudo NOPASSWD configured"
}

# ============================================================
# PACKAGE INSTALL
# ============================================================
install_pacman() {
  for pkg in "$@"; do
    if pacman -Qi "$pkg" &>/dev/null; then
      ok "$pkg already installed"
    elif run_sudo pacman -S --needed --noconfirm "$pkg" &>/dev/null 2>&1; then
      ok "$pkg"
    else
      err "$pkg failed"
    fi
  done
}

install_yay() {
  command -v yay &>/dev/null || { err "yay not found — skipping AUR"; return; }
  for pkg in "$@"; do
    if yay -Qi "$pkg" &>/dev/null; then
      ok "$pkg already installed"
    elif yay -S --needed --noconfirm "$pkg" &>/dev/null 2>&1; then
      ok "$pkg"
    else
      err "$pkg failed"
    fi
  done
}

# ============================================================
# BLACKARCH REPOS
# ============================================================
setup_blackarch() {
  step "BlackArch repository"

  if grep -q "\[blackarch\]" /etc/pacman.conf 2>/dev/null; then
    ok "BlackArch already configured"
    return
  fi

  inf "Fetching strap..."
  local strap
  strap="$(mktemp)"
  curl -fsSL https://blackarch.org/strap.sh -o "$strap" 2>/dev/null
  echo "5ea40d49ecd14c2e024deecf90605426db3f1163  $strap" | sha1sum -c - &>/dev/null || {
    err "strap.sh checksum mismatch — aborting BlackArch setup"
    rm -f "$strap"
    return
  }
  run_sudo chmod +x "$strap"
  run_sudo bash "$strap" &>/dev/null
  rm -f "$strap"

  run_sudo pacman -Sy --noconfirm &>/dev/null
  ok "BlackArch repository added"
}

# ============================================================
# YAY
# ============================================================
setup_yay() {
  if command -v yay &>/dev/null; then
    ok "yay already installed"
    return
  fi
  step "Installing yay"
  run_sudo pacman -S --needed --noconfirm git base-devel &>/dev/null
  local tmpdir
  tmpdir="$(mktemp -d)"
  git clone https://aur.archlinux.org/yay.git "$tmpdir/yay" &>/dev/null
  cd "$tmpdir/yay"
  makepkg -si --noconfirm &>/dev/null
  cd /
  rm -rf "$tmpdir"
  ok "yay installed"
}

# ============================================================
# DOCKER
# ============================================================
setup_docker() {
  step "Docker"
  if command -v docker &>/dev/null; then
    ok "docker already installed"
  else
    if run_sudo pacman -S --needed --noconfirm docker docker-compose &>/dev/null 2>&1; then
      ok "docker installed"
    else
      err "docker failed"; return
    fi
  fi
  run_sudo systemctl enable --now docker &>/dev/null
  ok "docker service enabled"
  if ! getent group docker | grep -q "\b${USER_NAME}\b"; then
    run_sudo usermod -aG docker "$USER_NAME"
    ok "$USER_NAME added to docker group"
  else
    ok "$USER_NAME already in docker group"
  fi
}

# ============================================================
# HTB-OPERATOR
# ============================================================
setup_htb_operator() {
  step "htb-operator"
  if ! command -v pipx &>/dev/null; then
    run_sudo pacman -S --needed --noconfirm python-pipx &>/dev/null || {
      err "python-pipx failed"; return
    }
    pipx ensurepath &>/dev/null || true
    export PATH="$HOME/.local/bin:$PATH"
  fi
  if pipx list 2>/dev/null | grep -q "htb-operator"; then
    ok "htb-operator already installed"
  else
    if pipx install htb-operator &>/dev/null; then
      ok "htb-operator installed"
    else
      err "htb-operator failed"
    fi
  fi
}

# ============================================================
# SERVICES
# ============================================================
setup_services() {
  step "Services"
  run_sudo systemctl enable NetworkManager lxdm &>/dev/null
  run_sudo systemctl start NetworkManager &>/dev/null
  echo "exec bspwm" > ~/.xinitrc
  run_sudo chsh -s /bin/zsh "$USER_NAME" &>/dev/null
  ok "Services configured"
}

# ============================================================
# ZSH
# ============================================================
setup_zsh() {
  step "ZSH / oh-my-zsh"
  if [[ -d ~/.oh-my-zsh ]]; then
    ok "oh-my-zsh already installed"
  else
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
      "" --unattended &>/dev/null
    ok "oh-my-zsh installed"
  fi

  ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"

  if [[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
    ok "zsh-autosuggestions already present"
  else
    git clone https://github.com/zsh-users/zsh-autosuggestions \
      "$ZSH_CUSTOM/plugins/zsh-autosuggestions" &>/dev/null
    ok "zsh-autosuggestions installed"
  fi

  if [[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
    ok "zsh-syntax-highlighting already present"
  else
    git clone https://github.com/zsh-users/zsh-syntax-highlighting \
      "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" &>/dev/null
    ok "zsh-syntax-highlighting installed"
  fi
}

# ============================================================
# DOTFILES
# ============================================================
setup_dotfiles() {
  step "Dotfiles"
  local DOTDIR="$HOME/dotfiles"

  if [[ -d "$DOTDIR/.git" ]]; then
    git -C "$DOTDIR" pull &>/dev/null
    ok "Dotfiles updated"
  else
    git clone "$DOTFILES_REPO" "$DOTDIR" &>/dev/null
    ok "Dotfiles cloned"
  fi

  mkdir -p "$HOME/.config"

  [[ -d "$DOTDIR/config" ]] && {
    cp -r "$DOTDIR/config/"* "$HOME/.config/"
    ok "config/ → ~/.config/"
  }
  [[ -f "$DOTDIR/home/.zshrc" ]] && { cp "$DOTDIR/home/.zshrc" "$HOME/"; ok ".zshrc deployed"; }
  [[ -d "$DOTDIR/home/.mozilla" ]] && { cp -r "$DOTDIR/home/.mozilla" "$HOME/"; ok ".mozilla deployed"; }
  [[ -d "$DOTDIR/home/.local" ]] && { cp -r "$DOTDIR/home/.local" "$HOME/"; ok ".local deployed"; }

  if [[ -d "$DOTDIR/bin" ]]; then
    while IFS= read -r -d '' binfile; do
      local bname
      bname=$(basename "$binfile")
      [[ "$bname" == .* || "$bname" == README* || "$bname" == LICENSE* ]] && continue
      [[ ! -f "$binfile" ]] && continue
      if run_sudo cp "$binfile" "/usr/bin/$bname" && run_sudo chmod +x "/usr/bin/$bname"; then
        ok "$bname → /usr/bin/$bname"
      else
        err "$bname failed"
      fi
    done < <(find "$DOTDIR/bin" -maxdepth 1 -type f -print0)
  fi

  [[ -f "$HOME/.config/bspwm/bspwmrc" ]] && chmod +x "$HOME/.config/bspwm/bspwmrc"
  [[ -d "$HOME/.config/bspwm/scripts" ]] && find "$HOME/.config/bspwm/scripts" -type f -exec chmod 755 {} \;

  mkdir -p "$HOME/Documents" "$HOME/Downloads" "$HOME/CTF"
  ok "Dotfiles deployed"
}

# ============================================================
# ROOT SYNC
# ============================================================
setup_root() {
  step "Root sync"
  run_sudo chsh -s /bin/zsh root &>/dev/null
  run_sudo cp -r ~/.oh-my-zsh /root/ &>/dev/null
  run_sudo cp ~/.zshrc /root/ &>/dev/null
  run_sudo cp -r ~/.config /root/ &>/dev/null
  ok "Root synced"
}

# ============================================================
# BURPSUITE
# ============================================================
setup_burpsuite() {
  step "Burpsuite"
  if ! command -v burpsuite &>/dev/null && ! pacman -Qi burpsuite &>/dev/null 2>&1; then
    if run_sudo pacman -S --needed --noconfirm burpsuite &>/dev/null 2>&1; then
      ok "burpsuite installed"
    else
      err "burpsuite failed — is BlackArch enabled?"
      return
    fi
  else
    ok "burpsuite already installed"
  fi

  # Find the launcher and patch it
  local launcher
  launcher="$(command -v burpsuite 2>/dev/null || true)"

  # Fallback locations if not in PATH yet
  if [[ -z "$launcher" || ! -f "$launcher" ]]; then
    for candidate in \
      /usr/local/bin/burpsuite \
      /usr/bin/burpsuite \
      /opt/burpsuite/burpsuite \
      /usr/share/burpsuite/burpsuite; do
      [[ -f "$candidate" ]] && launcher="$candidate" && break
    done
  fi

  # If still not found, use the default path
  [[ -z "$launcher" ]] && launcher="/usr/local/bin/burpsuite"

  run_sudo tee "$launcher" > /dev/null << 'EOF'
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

  run_sudo chmod +x "$launcher"
  ok "burpsuite launcher patched → $launcher"
}

# ============================================================
# SSH
# ============================================================
setup_ssh() {
  banner
  read -rp "Generate SSH keys? (Y/n): " ans
  ans=${ans,,}
  [[ -n "$ans" && "$ans" != "y" && "$ans" != "yes" ]] && return

  step "SSH key setup"
  local DEFAULT_USER="$USER_NAME"

  echo -e "  1) Default — no passphrase\n  2) Secure  — with passphrase"
  read -rp "  Option [1]: " mode
  [[ "$mode" != "2" ]] && mode=1

  read -rp "  SSH key label [${DEFAULT_USER}]: " SSH_USER
  SSH_USER="${SSH_USER:-$DEFAULT_USER}"

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  local PASSPHRASE_RSA="" PASSPHRASE_ED25519=""

  if [[ "$mode" == "2" ]]; then
    while true; do
      read -s -p "  RSA passphrase: " p1; echo
      read -s -p "  Confirm: " p2; echo
      [[ "$p1" == "$p2" ]] && PASSPHRASE_RSA="$p1" && break
      err "Passphrases do not match"
    done
    read -s -p "  ED25519 passphrase (ENTER = reuse RSA): " q1; echo
    if [[ -z "$q1" ]]; then
      PASSPHRASE_ED25519="$PASSPHRASE_RSA"
    else
      while true; do
        read -s -p "  Confirm ED25519: " q2; echo
        [[ "$q1" == "$q2" ]] && PASSPHRASE_ED25519="$q1" && break
        err "Passphrases do not match"
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

  banner
  [[ -f ~/.ssh/id_rsa.pub ]]     && { echo "--- id_rsa.pub ---";     cat ~/.ssh/id_rsa.pub;     echo; }
  [[ -f ~/.ssh/id_ed25519.pub ]] && { echo "--- id_ed25519.pub ---"; cat ~/.ssh/id_ed25519.pub; echo; }
  read -rp "Press ENTER to continue..."
}

# ============================================================
# VMWARE
# ============================================================
setup_vmware() {
  if ! systemd-detect-virt --quiet --vm 2>/dev/null | grep -q vmware && \
     ! grep -qi "vmware" /sys/class/dmi/id/sys_vendor 2>/dev/null; then
    return
  fi
  step "VMware guest"
  if run_sudo pacman -S --needed --noconfirm open-vm-tools gtkmm3 &>/dev/null 2>&1; then
    ok "open-vm-tools + gtkmm3 installed"
  else
    err "open-vm-tools failed"; return
  fi
  run_sudo systemctl enable --now vmtoolsd.service vmware-vmblock-fuse.service &>/dev/null
  ok "VMware services enabled"

  local BSPWMRC="$HOME/.config/bspwm/bspwmrc"
  if [[ -f "$BSPWMRC" ]] && ! grep -q "vmware-user" "$BSPWMRC"; then
    printf '\n# VMware clipboard & drag-drop\npgrep vmware-user || vmware-user &\n' >> "$BSPWMRC"
    ok "vmware-user added to bspwmrc"
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
setup_blackarch
install_pacman "${PACMAN_PKGS[@]}"
install_yay "${YAY_PKGS[@]}"
setup_docker
setup_htb_operator
setup_services
setup_zsh
setup_dotfiles
setup_vmware
setup_burpsuite
setup_root
setup_ssh

run_sudo dracut --regenerate-all --force &>/dev/null
ok "dracut rebuilt"

banner
ok "Done — reboot recommended"
