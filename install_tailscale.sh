#!/usr/bin/env bash
# install_tailscale.sh - install/upgrade the Tailscale client via Tailscale's
# apt repo (pkgs.tailscale.com). Derived from https://tailscale.com/install.sh,
# reduced to the Debian/Ubuntu keyring path. Sources the shared lib for
# logging/plumbing; the apt logic stays local. Does not run `tailscale up`:
# login is interactive and would block a batch run.
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/install_common.sh"
# shellcheck source=lib/install_common.sh
. "$_LIB"
ic_strict

IC_TOOL_NAME=tailscale
IC_TOOL_DESC="Tailscale client (pkgs.tailscale.com apt repo)"
IC_HELP_EXTRA="  TRACK=stable|unstable selects the release track (default: stable)."

KEYRING=/usr/share/keyrings/tailscale-archive-keyring.gpg
SOURCES_LIST=/etc/apt/sources.list.d/tailscale.list

: "${TRACK:=stable}"
: "${REQ_VERSION:=${TAILSCALE_VERSION:-latest}}"
: "${DRY_RUN:=${TAILSCALE_DRY_RUN:-false}}"
ic_parse_args "$@"

[[ "$TRACK" == stable || "$TRACK" == unstable ]] || ic_die "Unsupported track: $TRACK (use stable or unstable)."
ic_require curl sudo
command -v apt-get >/dev/null 2>&1 \
    || ic_die "This installer supports Debian/Ubuntu (apt) only. See https://tailscale.com/download/linux"

[[ -r /etc/os-release ]] || ic_die "Cannot read /etc/os-release."
# Subshells keep the os-release variables out of this shell.
# shellcheck source=/dev/null
OS_ID=$(. /etc/os-release && echo "$ID")
# shellcheck source=/dev/null
CODENAME=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")
case "$OS_ID" in
    ubuntu|debian|raspbian) ;;
    *) ic_die "Unsupported distro: $OS_ID (ubuntu, debian and raspbian only)." ;;
esac
[[ -n "$CODENAME" ]] || ic_die "Cannot determine the release codename from /etc/os-release."

REPO_URL="https://pkgs.tailscale.com/$TRACK/$OS_ID/$CODENAME"
PACKAGE=tailscale
[[ "$REQ_VERSION" == latest ]] || PACKAGE="tailscale=$(ic_strip_v "$REQ_VERSION")"

# The package server reports whether it carries this distro release.
ic_curl -fsSL "$REPO_URL/installer-supported" 2>/dev/null | grep -q OK \
    || ic_die "Tailscale has no $TRACK packages for $OS_ID $CODENAME."

CURRENT=$(tailscale version 2>/dev/null | head -n1 || true)
ic_info "Installed: ${CURRENT:-none}. Requested: $REQ_VERSION ($TRACK track, $OS_ID $CODENAME)."

if [[ "$DRY_RUN" == "true" ]]; then
    ic_info "[DRY-RUN] would add $REPO_URL to $SOURCES_LIST and apt-get install $PACKAGE"
    exit 0
fi

ic_info "Adding Tailscale GPG key and apt repository..."
sudo mkdir -p --mode=0755 /usr/share/keyrings
ic_curl -fsSL "$REPO_URL.noarmor.gpg" | sudo tee "$KEYRING" >/dev/null
ic_curl -fsSL "$REPO_URL.tailscale-keyring.list" | sudo tee "$SOURCES_LIST" >/dev/null
sudo chmod 0644 "$KEYRING" "$SOURCES_LIST"

ic_info "Installing $PACKAGE..."
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update
sudo apt-get install -y --allow-downgrades "$PACKAGE" tailscale-archive-keyring

# The package starts tailscaled under systemd. WSL without systemd has no
# service manager, so the daemon must be started by hand there.
if [[ -d /run/systemd/system ]]; then
    systemctl is-active --quiet tailscaled || sudo systemctl enable --now tailscaled
else
    ic_warn "systemd is not running. Start the daemon manually: sudo tailscaled"
fi

command -v tailscale >/dev/null 2>&1 || ic_die "tailscale command not found in PATH after install!"
ic_rule
tailscale version
ic_rule
ic_info "Tailscale installed. Run 'sudo tailscale up' to log in."
