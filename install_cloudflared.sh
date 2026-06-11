#!/usr/bin/env bash
# install_cloudflared.sh — install cloudflared via Cloudflare's apt repo, then
# run the tunnel using the token from ~/.envfiles/cloudflared.env.
# Sources the shared lib for logging; the GPG/apt/tunnel logic stays local.
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/install_common.sh"
# shellcheck source=lib/install_common.sh
. "$_LIB"
ic_strict

IC_TOOL_NAME=cloudflared
IC_TOOL_DESC="Cloudflare Tunnel daemon (pkg.cloudflare.com apt repo)"
ic_parse_args "$@"

ic_require curl sudo

# Add the Cloudflare GPG key.
sudo mkdir -p --mode=0755 /usr/share/keyrings
if [[ ! -f /usr/share/keyrings/cloudflare-main.gpg ]]; then
    ic_info "Adding Cloudflare GPG key..."
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
        | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
fi

# Add the apt repository.
if [[ ! -f /etc/apt/sources.list.d/cloudflared.list ]]; then
    ic_info "Adding Cloudflare apt repository..."
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' \
        | sudo tee /etc/apt/sources.list.d/cloudflared.list >/dev/null
fi

# Install cloudflared.
if ! command -v cloudflared >/dev/null 2>&1; then
    ic_info "Installing cloudflared..."
    sudo apt-get update && sudo apt-get install -y cloudflared
fi

# Run the tunnel.
[[ -r "$HOME/.envfiles/cloudflared.env" ]] || ic_die "Missing ~/.envfiles/cloudflared.env (needs CLOUDFLARE_TOKEN)."
# shellcheck source=/dev/null
source "$HOME/.envfiles/cloudflared.env"
[[ -n "${CLOUDFLARE_TOKEN:-}" ]] || ic_die "CLOUDFLARE_TOKEN not set in ~/.envfiles/cloudflared.env."

ic_info "Starting cloudflared tunnel..."
cloudflared tunnel run --token "${CLOUDFLARE_TOKEN}"
