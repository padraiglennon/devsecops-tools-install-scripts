#!/usr/bin/env bash
# install_docker.sh — install/upgrade Docker CE via Docker's official apt repo on
# Ubuntu/Debian (incl. WSL 2). Sources the shared lib for logging/flags; the
# GPG/apt/repo/group logic stays local.
#
# Installs: docker-ce, docker-ce-cli, containerd.io, the buildx and compose
# plugins. Adds the invoking user to the `docker` group so the daemon is usable
# without sudo (log out / back in, or `newgrp docker`, to pick up the group).
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/install_common.sh"
# shellcheck source=lib/install_common.sh
. "$_LIB"
ic_strict

IC_TOOL_NAME=docker
IC_TOOL_DESC="Docker CE container engine (docker.com apt repo)"
IC_HELP_EXTRA="
Installs docker-ce + cli, containerd.io, buildx and compose plugins, then adds
you to the 'docker' group. On WSL without systemd, start the daemon with
'sudo service docker start'."
ic_parse_args "$@"

ic_require curl gpg sudo

# --- Detect distro (Docker's repo path differs for ubuntu vs debian) ---------
if ! grep -qiE 'ubuntu|debian' /etc/os-release 2>/dev/null; then
    ic_die "This script targets Ubuntu/Debian (apt). Unsupported host."
fi
# shellcheck source=/dev/null
. /etc/os-release
DISTRO_ID="${ID:-ubuntu}"          # ubuntu | debian
case "$DISTRO_ID" in
    ubuntu|debian) ;;
    # Derivatives (e.g. Linux Mint) set ID_LIKE; map them to their base.
    *) case "${ID_LIKE:-}" in
           *ubuntu*) DISTRO_ID=ubuntu ;;
           *debian*) DISTRO_ID=debian ;;
           *) ic_die "Unrecognised Debian/Ubuntu derivative: ${ID:-unknown}." ;;
       esac ;;
esac
# Codename: VERSION_CODENAME on most, UBUNTU_CODENAME as a fallback.
CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
[[ -n "$CODENAME" ]] || ic_die "Could not determine distro codename from /etc/os-release."

ARCH=$(dpkg --print-architecture)

KEYRING="/etc/apt/keyrings/docker.asc"
SOURCES="/etc/apt/sources.list.d/docker.list"
REPO_URL="https://download.docker.com/linux/${DISTRO_ID}"

# --- Add Docker's GPG key ----------------------------------------------------
sudo install -m 0755 -d /etc/apt/keyrings
if [[ ! -f "$KEYRING" ]]; then
    ic_info "Adding Docker GPG key..."
    curl -fsSL "${REPO_URL}/gpg" | sudo tee "$KEYRING" >/dev/null
    sudo chmod a+r "$KEYRING"
fi

# --- Add the apt repository (overwrite so re-runs converge) ------------------
ic_info "Configuring Docker apt repository (${DISTRO_ID} ${CODENAME})..."
echo "deb [arch=${ARCH} signed-by=${KEYRING}] ${REPO_URL} ${CODENAME} stable" \
    | sudo tee "$SOURCES" >/dev/null
sudo chmod 0644 "$SOURCES"

# --- Install / upgrade -------------------------------------------------------
PKGS=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
ic_info "Updating apt indexes..."
sudo apt-get update -qq
if dpkg -s docker-ce >/dev/null 2>&1; then
    ic_info "docker-ce already installed — upgrading if a newer version is available..."
    sudo apt-get install --only-upgrade -y "${PKGS[@]}"
else
    ic_info "Installing Docker CE..."
    sudo apt-get install -y "${PKGS[@]}"
fi

# --- Add invoking user to the docker group -----------------------------------
TARGET_USER="${SUDO_USER:-$USER}"
if [[ "$TARGET_USER" != "root" ]]; then
    if ! id -nG "$TARGET_USER" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
        ic_info "Adding ${TARGET_USER} to the 'docker' group..."
        sudo usermod -aG docker "$TARGET_USER"
        ic_warn "Group change takes effect on next login (or run: newgrp docker)."
    fi
fi

# --- Verify ------------------------------------------------------------------
ic_rule
docker --version
docker compose version 2>/dev/null || true
ic_rule
ic_info "Docker CE installation complete."
ic_info "On WSL without systemd, start the daemon with: sudo service docker start"
