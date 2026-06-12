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
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RESET='\033[0m'

log() {
  local level="$1"; shift
  case "$level" in
    ok)    echo -e "${GREEN}[OK]${RESET}    $*" ;;
    info)  echo -e "${CYAN}[INFO]${RESET}  $*" ;;
    warn)  echo -e "${YELLOW}[WARN]${RESET}  $*" ;;
    error) echo -e "${RED}[ERROR]${RESET} $*" ;;
  esac
}

# ============================================================
# UI
# ============================================================
banner() {
  clear
  echo -e "$BANNER\n"
}

step() {
  banner
  echo -e "➜ $1\n"
}

# ============================================================
# CHECKS
# ============================================================
[[ $EUID -eq 0 ]] && {
  echo "[!] Do not run as root"
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
step "Caching sudo credentials"
sudo -v

run_sudo() {
  sudo "$@"
}

# ============================================================
# SUDO NOPASSWD
# ============================================================
setup_sudo() {
  step "Configuring sudo NOPASSWD"

  run_sudo sh -c "echo '$USER_NAME ALL=(ALL) NOPASSWD: ALL' > '$SUDO_FILE'"
  run_sudo chmod 440 "$SUDO_FILE"

  run_sudo visudo -cf "$SUDO_FILE" || {
    run_sudo rm -f "$SUDO_FILE"
    log error "Invalid sudoers file, reverted"
    exit 1
  }
  log ok "sudo NOPASSWD configured"
}

# ============================================================
# PACKAGE INSTALL
# ============================================================
install_pacman() {
  for pkg in "$@"; do
    log info "Installing $pkg..."
    if pacman -Qi "$pkg" &>/dev/null; then
      log ok "$pkg already installed — skipping"
    elif run_sudo pacman -S --needed --noconfirm "$pkg" &>/dev/null; then
      log ok "$pkg installed"
    else
      log error "Failed to install $pkg"
    fi
  done
}

install_yay() {
  command -v yay &>/dev/null || {
    log warn "yay not found, skipping AUR packages"
    return
  }

  for pkg in "$@"; do
    log info "Installing AUR $pkg..."
    if yay -Qi "$pkg" &>/dev/null; then
      log ok "$pkg already installed — skipping"
    elif yay -S --needed --noconfirm "$pkg" &>/dev/null; then
      log ok "$pkg installed"
    else
      log error "Failed to install AUR $pkg"
    fi
  done
}

# ============================================================
# YAY
# ============================================================
setup_yay() {
  if command -v yay &>/dev/null; then
    step "yay already installed — skipping"
    log ok "yay present"
    return
  fi

  step "Installing yay"
  run_sudo pacman -S --needed --noconfirm git base-devel

  tmpdir="$(mktemp -d)"
  log info "Cloning yay AUR repo..."
  git clone https://aur.archlinux.org/yay.git "$tmpdir/yay"
  cd "$tmpdir/yay"
  makepkg -si --noconfirm
  cd /
  rm -rf "$tmpdir"
  log ok "yay installed"
}

# ============================================================
# BLACKARCH
# ============================================================
setup_blackarch() {
  banner
  read -rp "Install BlackArch repositories? (Y/n): " ans
  ans=${ans,,}
  [[ -n "$ans" && "$ans" != "y" && "$ans" != "yes" ]] && {
    log info "Skipping BlackArch"
    return
  }

  step "Setting up BlackArch"

  if grep -q "\[blackarch\]" /etc/pacman.conf 2>/dev/null; then
    log ok "BlackArch repo already present — skipping"
    return
  fi

  log info "Downloading BlackArch strap..."
  TMP_STRAP="$(mktemp)"
  curl -fsSL https://blackarch.org/strap.sh -o "$TMP_STRAP"

  log info "Verifying SHA1..."
  EXPECTED="5ea40d49ecd14c2e024deecf90605426db97ea0c"
  ACTUAL="$(sha1sum "$TMP_STRAP" | cut -d' ' -f1)"

  if [[ "$ACTUAL" != "$EXPECTED" ]]; then
    log error "SHA1 mismatch! Expected: $EXPECTED | Got: $ACTUAL"
    log error "Aborting BlackArch setup for security reasons"
    rm -f "$TMP_STRAP"
    return
  fi

  chmod +x "$TMP_STRAP"
  run_sudo bash "$TMP_STRAP"
  rm -f "$TMP_STRAP"

  run_sudo pacman -Syyu --noconfirm
  log ok "BlackArch repositories added"
}

# ============================================================
# BLACKARCH-ONLY TOOLS (sliver, bloodhound)
# ============================================================
install_blackarch_tools() {
  step "BlackArch tools"

  BLACKARCH_TOOLS=(sliver bloodhound)
  for tool in "${BLACKARCH_TOOLS[@]}"; do
    log info "Installing $tool..."
    if pacman -Qi "$tool" &>/dev/null; then
      log ok "$tool already installed — skipping"
    elif run_sudo pacman -S --needed --noconfirm "$tool" &>/dev/null; then
      log ok "$tool installed"
    else
      log error "Failed to install $tool"
    fi
  done
}

# ============================================================
# PENTEST TOOLS
# ============================================================
install_python() {
  step "Python"
  log info "Installing Python 3..."
  if run_sudo pacman -S --noconfirm python python-pip &>/dev/null; then
    log ok "python3 installed"
  else
    log error "Failed to install python3"
  fi

  log info "Installing Python 2..."
  if run_sudo pacman -S --noconfirm python2 &>/dev/null; then
    log ok "python2 installed"
    if ! command -v pip2 &>/dev/null; then
      log info "Bootstrapping pip2..."
      curl -sS https://bootstrap.pypa.io/pip/2.7/get-pip.py -o /tmp/get-pip2.py
      python2 /tmp/get-pip2.py &>/dev/null && log ok "pip2 installed" || log warn "pip2 bootstrap failed"
    fi
  else
    log warn "python2 not available (expected on newer Arch)"
  fi
}

install_pentest_tools() {
  step "Pentest tools"
  TOOLS=(
    nmap hashcat ffuf feroxbuster git wget curl sqlmap whatweb netcat
    john obsidian unzip burpsuite gobuster wfuzz nikto sslscan
    smbclient freerdp rdesktop proxychains-ng responder enum4linux
    smbmap ldns
  )
  for tool in "${TOOLS[@]}"; do
    log info "Installing $tool..."
    if pacman -Qi "$tool" &>/dev/null; then
      log ok "$tool already installed — skipping"
    elif run_sudo pacman -S --noconfirm "$tool" &>/dev/null; then
      log ok "$tool installed"
    else
      log warn "$tool not found in repos (may need BlackArch or AUR)"
    fi
  done
}

# ============================================================
# PIPX TOOLS (AD / HTB)
# ============================================================
install_pipx_tools() {
  step "Pipx tools"

  log info "Installing python-pipx..."
  if run_sudo pacman -S --needed --noconfirm python-pipx &>/dev/null; then
    log ok "python-pipx installed"
  else
    log error "Failed to install python-pipx"
    return
  fi

  pipx ensurepath &>/dev/null || true

  PIPX_TOOLS=(htb-operator bloodyad certipy-ad netexec ldapdomaindump)
  for tool in "${PIPX_TOOLS[@]}"; do
    log info "Installing $tool..."
    if pipx list 2>/dev/null | grep -q "$tool"; then
      log ok "$tool already installed — skipping"
    elif pipx install "$tool" &>/dev/null; then
      log ok "$tool installed"
    else
      log error "Failed to install $tool"
    fi
  done
}

# ============================================================
# SERVICES
# ============================================================
setup_services() {
  step "Services"
  run_sudo systemctl enable NetworkManager lxdm
  run_sudo systemctl start NetworkManager
  echo "exec bspwm" > ~/.xinitrc
  run_sudo chsh -s /bin/zsh "$USER_NAME"
  log ok "Services configured"
}

# ============================================================
# ZSH
# ============================================================
setup_zsh() {
  step "ZSH"
  if [[ -d ~/.oh-my-zsh ]]; then
    log ok "oh-my-zsh already installed — skipping"
  else
    log info "Installing oh-my-zsh..."
    RUNZSH=no sh -c \
      "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    log ok "oh-my-zsh installed"
  fi

  ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"

  log info "Cloning zsh-autosuggestions..."
  git clone https://github.com/zsh-users/zsh-autosuggestions \
    "$ZSH_CUSTOM/plugins/zsh-autosuggestions" 2>/dev/null || log ok "zsh-autosuggestions already present"

  log info "Cloning zsh-syntax-highlighting..."
  git clone https://github.com/zsh-users/zsh-syntax-highlighting \
    "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" 2>/dev/null || log ok "zsh-syntax-highlighting already present"

  log ok "ZSH configured"
}

# ============================================================
# DOTFILES
# ============================================================
setup_dotfiles() {
  step "Dotfiles"

  DOTDIR="$HOME/dotfiles"

  if [[ -d "$DOTDIR/.git" ]]; then
    log info "Dotfiles already cloned — pulling updates"
    git -C "$DOTDIR" pull
  else
    log info "Cloning dotfiles..."
    git clone "$DOTFILES_REPO" "$DOTDIR"
  fi

  mkdir -p "$HOME/.config"

  # config/
  [[ -d "$DOTDIR/config" ]] && {
    cp -r "$DOTDIR/config/"* "$HOME/.config/"
    log ok "config/ deployed to ~/.config/"
  }

  # home/
  [[ -f "$DOTDIR/home/.zshrc" ]] && {
    cp "$DOTDIR/home/.zshrc" "$HOME/"
    log ok ".zshrc deployed"
  }
  [[ -d "$DOTDIR/home/.mozilla" ]] && {
    cp -r "$DOTDIR/home/.mozilla" "$HOME/"
    log ok ".mozilla deployed"
  }
  [[ -d "$DOTDIR/home/.local" ]] && {
    cp -r "$DOTDIR/home/.local" "$HOME/"
    log ok ".local deployed"
  }

  # bin/ → /usr/bin/
  if [[ -d "$DOTDIR/bin" ]]; then
    log info "Deploying bin/ to /usr/bin/..."
    while IFS= read -r -d '' binfile; do
      bname=$(basename "$binfile")
      [[ "$bname" == .* || "$bname" == README* || "$bname" == LICENSE* ]] && continue
      [[ ! -f "$binfile" ]] && continue
      if run_sudo cp "$binfile" "/usr/bin/$bname" && run_sudo chmod +x "/usr/bin/$bname"; then
        log ok "$bname → /usr/bin/$bname"
      else
        log error "Failed to deploy $bname"
      fi
    done < <(find "$DOTDIR/bin" -maxdepth 1 -type f -print0)
  fi

  # bspwm permissions
  [[ -f "$HOME/.config/bspwm/bspwmrc" ]] && chmod +x "$HOME/.config/bspwm/bspwmrc"
  [[ -d "$HOME/.config/bspwm/scripts" ]] && find "$HOME/.config/bspwm/scripts" -type f -exec chmod 755 {} \;

  mkdir -p "$HOME/Documents" "$HOME/Downloads" "$HOME/CTF"
  log ok "Dotfiles deployed"
}

# ============================================================
# CUSTOM TOOLS (pivoting + AD)
# ============================================================
setup_custom_tools() {
  step "Custom tools (z1rov repos)"

  log info "Cloning z1rov/pivoting-tools..."
  TMP_PIVOT="$(mktemp -d)"
  if git clone -q https://github.com/z1rov/pivoting-tools "$TMP_PIVOT"; then
    while IFS= read -r -d '' tool_dir; do
      dname=$(basename "$tool_dir")
      [[ "$dname" == .* ]] && continue
      dst="/usr/share/$dname"
      run_sudo mkdir -p "$dst"
      run_sudo cp -r "$tool_dir/." "$dst/"
      log ok "pivoting-tools/$dname → $dst"
    done < <(find "$TMP_PIVOT" -mindepth 1 -maxdepth 1 -type d -print0)
    rm -rf "$TMP_PIVOT"
    log ok "pivoting-tools deployed"
  else
    log error "Failed to clone pivoting-tools"
  fi

  log info "Cloning z1rov/active-directory-tools..."
  TMP_AD="$(mktemp -d)"
  if git clone -q https://github.com/z1rov/active-directory-tools "$TMP_AD"; then
    while IFS= read -r -d '' tool_dir; do
      dname=$(basename "$tool_dir")
      [[ "$dname" == .* ]] && continue
      dst="/usr/share/$dname"
      run_sudo mkdir -p "$dst"
      run_sudo cp -r "$tool_dir/." "$dst/"
      log ok "active-directory-tools/$dname → $dst"
    done < <(find "$TMP_AD" -mindepth 1 -maxdepth 1 -type d -print0)
    rm -rf "$TMP_AD"
    log ok "active-directory-tools deployed"
  else
    log error "Failed to clone active-directory-tools"
  fi

  log info "Cloning z1rov/tools → /usr/local/bin..."
  TMP_TOOLS="$(mktemp -d)"
  if git clone -q https://github.com/z1rov/tools "$TMP_TOOLS"; then
    while IFS= read -r -d '' bin; do
      bname=$(basename "$bin")
      [[ "$bname" == .* || "$bname" == README* || "$bname" == LICENSE* ]] && continue
      [[ ! -f "$bin" ]] && continue
      if run_sudo cp "$bin" "/usr/local/bin/$bname" && run_sudo chmod +x "/usr/local/bin/$bname"; then
        log ok "$bname → /usr/local/bin/$bname"
      else
        log error "Failed to deploy $bname"
      fi
    done < <(find "$TMP_TOOLS" -maxdepth 1 -type f -print0)
    rm -rf "$TMP_TOOLS"
    log ok "z1rov/tools deployed"
  else
    log error "Failed to clone z1rov/tools"
  fi
}

# ============================================================
# WORDLISTS
# ============================================================
setup_wordlists() {
  step "Wordlists"
  WDIR="/usr/share/wordlists"
  run_sudo mkdir -p "$WDIR"

  log info "Cloning SecLists..."
  if [[ -d /usr/share/seclists/.git ]]; then
    run_sudo git -C /usr/share/seclists pull -q
    log ok "SecLists updated"
  elif run_sudo git clone -q --depth 1 https://github.com/danielmiessler/SecLists /usr/share/seclists; then
    log ok "SecLists cloned"
  else
    log error "Failed to clone SecLists"
  fi

  log info "Cloning z1rov/wordlists..."
  TMP_WL="$(mktemp -d)"
  if git clone -q https://github.com/z1rov/wordlists "$TMP_WL"; then
    for file in "$TMP_WL"/*; do
      fname=$(basename "$file")
      [[ "$fname" == README* || "$fname" == .* ]] && continue
      case "$fname" in
        *.zip)
          dest_name="${fname%.zip}"
          run_sudo mkdir -p "$WDIR/$dest_name"
          run_sudo unzip -o "$file" -d "$WDIR/$dest_name/" &>/dev/null
          nested=$(find "$WDIR/$dest_name" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
          if [[ $(echo "$nested" | grep -c .) -eq 1 ]] && \
             [[ -z "$(find "$WDIR/$dest_name" -mindepth 1 -maxdepth 1 -type f 2>/dev/null)" ]]; then
            run_sudo mv "$nested"/* "$WDIR/$dest_name/" 2>/dev/null || true
            run_sudo rmdir "$nested" 2>/dev/null || true
          fi
          log ok "$fname extracted"
          ;;
        *.tar.gz|*.tgz)
          dest_name="${fname%.tar.gz}"; dest_name="${dest_name%.tgz}"
          run_sudo mkdir -p "$WDIR/$dest_name"
          run_sudo tar -xzf "$file" -C "$WDIR/$dest_name/" &>/dev/null
          log ok "$fname extracted"
          ;;
        *.gz)
          dest_name="${fname%.gz}"
          run_sudo bash -c "gunzip -c '$file' > '$WDIR/$dest_name'" 2>/dev/null
          [[ -d "$WDIR/$dest_name" ]] && run_sudo rm -rf "$WDIR/$dest_name"
          log ok "$fname decompressed"
          ;;
        *)
          run_sudo cp "$file" "$WDIR/" 2>/dev/null
          log ok "$fname copied"
          ;;
      esac
    done

    # Fix rockyou if extracted as dir
    if [[ -d "$WDIR/rockyou.txt" ]]; then
      INNER=$(find "$WDIR/rockyou.txt" -type f | head -1)
      if [[ -n "$INNER" ]]; then
        run_sudo mv "$INNER" "$WDIR/rockyou.txt.tmp"
        run_sudo rm -rf "$WDIR/rockyou.txt"
        run_sudo mv "$WDIR/rockyou.txt.tmp" "$WDIR/rockyou.txt"
        log ok "rockyou.txt fixed"
      fi
    fi

    rm -rf "$TMP_WL"
    log ok "Wordlists ready at $WDIR"
  else
    log error "Failed to clone z1rov/wordlists"
  fi
}

# ============================================================
# ALIASES
# ============================================================
setup_aliases() {
  step "Aliases"
  SHELL_RC="$HOME/.zshrc"
  [[ ! -f "$SHELL_RC" ]] && touch "$SHELL_RC"

  MARKER="# ── z1rov pentest aliases ──"
  grep -q "$MARKER" "$SHELL_RC" 2>/dev/null && \
    sed -i "/$MARKER/,/# ── end z1rov aliases ──/d" "$SHELL_RC"

  {
    echo ""
    echo "# ── z1rov pentest aliases ──"
    [[ -d /usr/share/wordlists ]]   && echo "alias wordlists='cd /usr/share/wordlists && ls'"
    [[ -d /usr/share/seclists ]]    && echo "alias seclists='cd /usr/share/seclists && ls'"
    [[ -d /usr/share/pivoting-tools ]] && echo "alias pivoting='cd /usr/share/pivoting-tools && ls'"
    [[ -d /usr/share/active-directory-tools ]] && echo "alias adtools='cd /usr/share/active-directory-tools && ls'"
    echo "# ── end z1rov aliases ──"
  } >> "$SHELL_RC"

  log ok "Aliases written to $SHELL_RC"
}

# ============================================================
# ROOT SYNC
# ============================================================
setup_root() {
  step "Root sync"
  run_sudo chsh -s /bin/zsh root
  run_sudo cp -r ~/.oh-my-zsh /root/
  run_sudo cp ~/.zshrc /root/
  run_sudo cp -r ~/.config /root/
  log ok "Root synced"
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
      echo "RSA passphrase:"
      read -s -p "Passphrase: " p1; echo
      read -s -p "Confirm: " p2; echo
      [[ "$p1" == "$p2" ]] && PASSPHRASE_RSA="$p1" && break
      log warn "Passphrases do not match"
    done

    read -s -p "ED25519 passphrase (ENTER = reuse RSA): " q1; echo
    if [[ -z "$q1" ]]; then
      PASSPHRASE_ED25519="$PASSPHRASE_RSA"
    else
      while true; do
        read -s -p "Confirm ED25519: " q2; echo
        [[ "$q1" == "$q2" ]] && PASSPHRASE_ED25519="$q1" && break
        log warn "Passphrases do not match"
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

    log info "Generating $type key..."
    if [[ "$type" == "rsa" ]]; then
      ssh-keygen -t rsa -b "$bits" -f "$path" -C "${SSH_USER}@$(hostname)" -N "$pass" -q
    else
      ssh-keygen -t ed25519 -f "$path" -C "${SSH_USER}@$(hostname)" -N "$pass" -q
    fi

    chmod 600 "$path"
    chmod 644 "$path.pub"
    log ok "$type key generated"
  }

  generate_key "$HOME/.ssh/id_rsa"     "rsa"     4096 "$PASSPHRASE_RSA"
  generate_key "$HOME/.ssh/id_ed25519" "ed25519" ""   "$PASSPHRASE_ED25519"

  banner
  [[ -f ~/.ssh/id_rsa.pub ]] && {
    echo "--- id_rsa.pub ---"
    cat ~/.ssh/id_rsa.pub
    echo
  }
  [[ -f ~/.ssh/id_ed25519.pub ]] && {
    echo "--- id_ed25519.pub ---"
    cat ~/.ssh/id_ed25519.pub
    echo
  }

  read -rp "Press ENTER to continue..."
}

# ============================================================
# VMWARE DETECTION
# ============================================================
setup_vmware() {
  if ! systemd-detect-virt --quiet --vm 2>/dev/null | grep -q vmware && \
     ! grep -qi "vmware" /sys/class/dmi/id/sys_vendor 2>/dev/null; then
    return
  fi

  step "VMware guest detected"
  log info "Installing open-vm-tools and gtkmm3..."

  if run_sudo pacman -S --needed --noconfirm open-vm-tools gtkmm3 &>/dev/null; then
    log ok "open-vm-tools + gtkmm3 installed"
  else
    log error "Failed to install open-vm-tools"
    return
  fi

  log info "Enabling VMware services..."
  run_sudo systemctl enable vmtoolsd.service
  run_sudo systemctl start  vmtoolsd.service
  log ok "vmtoolsd enabled"

  run_sudo systemctl enable vmware-vmblock-fuse.service
  run_sudo systemctl start  vmware-vmblock-fuse.service
  log ok "vmware-vmblock-fuse enabled"

  # Append vmware-user to bspwmrc (idempotent)
  BSPWMRC="$HOME/.config/bspwm/bspwmrc"
  if [[ -f "$BSPWMRC" ]]; then
    if ! grep -q "vmware-user" "$BSPWMRC"; then
      echo "" >> "$BSPWMRC"
      echo "# VMware clipboard & drag-drop" >> "$BSPWMRC"
      echo "pgrep vmware-user || vmware-user &" >> "$BSPWMRC"
      log ok "vmware-user added to bspwmrc"
    else
      log ok "vmware-user already in bspwmrc — skipping"
    fi
  else
    log warn "bspwmrc not found — will need to add 'pgrep vmware-user || vmware-user &' manually"
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
install_blackarch_tools
install_python
install_pentest_tools
install_pipx_tools
setup_services
setup_zsh
setup_dotfiles
setup_vmware
setup_custom_tools
setup_wordlists
setup_aliases
setup_root
setup_ssh

run_sudo dracut --regenerate-all --force

banner
log ok "OÑO"
