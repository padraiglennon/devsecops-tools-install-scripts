#!/usr/bin/env bash
# install_az_cli.sh — install/upgrade Azure CLI via Microsoft's official
# convenience script (adds MS apt repo, installs azure-cli). Sources the shared
# lib for logging/plumbing; the MS-installer invocation stays local.
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/install_common.sh"
# shellcheck source=lib/install_common.sh
. "$_LIB"
ic_strict

IC_TOOL_NAME=az
IC_TOOL_DESC="Azure CLI (Microsoft InstallAzureCLIDeb convenience script)"

INSTALL_SCRIPT_URL="${INSTALL_SCRIPT_URL:-https://aka.ms/InstallAzureCLIDeb}"
ic_parse_args "$@"

ic_require curl sudo
command -v apt-get >/dev/null 2>&1 \
    || ic_die "This installer supports Debian/Ubuntu (apt) only. See https://learn.microsoft.com/cli/azure/install-azure-cli"

ARCH=$(uname -m)
case "$ARCH" in
    x86_64|arm64|aarch64) ic_info "Architecture: $ARCH" ;;
    *)                    ic_die "Unsupported architecture: $ARCH" ;;
esac

ic_mktemp
cd "$IC_TMP_DIR"

ic_info "Downloading Azure CLI installer..."
ic_download "$INSTALL_SCRIPT_URL" "install_azure_cli.sh"

ic_info "Running Azure CLI installer (sudo required)..."
sudo bash install_azure_cli.sh || ic_die "Azure CLI installation failed."

command -v az >/dev/null 2>&1 || ic_die "az command not found in PATH after install!"
ic_rule
az version
ic_rule
ic_info "Azure CLI installed. Run 'az login' to authenticate."
