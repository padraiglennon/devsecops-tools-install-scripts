#!/usr/bin/env bash
# install_gcp_cli.sh — install/upgrade Google Cloud CLI from the stable "latest"
# tarball, run its install.sh non-interactively, and symlink gcloud/gsutil/bq.
# Sources the shared lib for logging/plumbing; the SDK install logic stays local.
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/install_common.sh"
# shellcheck source=lib/install_common.sh
. "$_LIB"
ic_strict

IC_TOOL_NAME=gcloud
IC_TOOL_DESC="Google Cloud CLI (dl.google.com rapid channel)"

: "${INSTALL_DIR:=/usr/local/bin}"
GCLOUD_INSTALL_DIR="${GCLOUD_INSTALL_DIR:-/usr/local/google-cloud-sdk}"
ic_parse_args "$@"

ic_require curl tar sudo
command -v python3 >/dev/null 2>&1 || ic_warn "python3 not found; the gcloud CLI requires Python 3.8+ at runtime."

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)        GCLOUD_ARCH="x86_64" ;;
    arm64|aarch64) GCLOUD_ARCH="arm" ;;
    *)             ic_die "Unsupported architecture: $ARCH" ;;
esac
ic_info "Architecture: $GCLOUD_ARCH"

ic_mktemp
cd "$IC_TMP_DIR"

tarball="google-cloud-cli-linux-${GCLOUD_ARCH}.tar.gz"
ic_info "Downloading Google Cloud CLI..."
ic_download "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/${tarball}" "$tarball"

ic_info "Extracting installer..."
tar -xzf "$tarball" || ic_die "Failed to extract Google Cloud CLI."

if [[ -d "$GCLOUD_INSTALL_DIR" ]]; then
    ic_info "Removing existing SDK at ${GCLOUD_INSTALL_DIR}..."
    sudo rm -rf "$GCLOUD_INSTALL_DIR"
fi

ic_info "Installing Google Cloud SDK to ${GCLOUD_INSTALL_DIR} (sudo required)..."
sudo mv "${IC_TMP_DIR}/google-cloud-sdk" "$GCLOUD_INSTALL_DIR"

ic_info "Running gcloud installer (non-interactive)..."
sudo "${GCLOUD_INSTALL_DIR}/install.sh" \
    --quiet --usage-reporting=false --path-update=false --command-completion=false \
    || ic_die "gcloud install.sh failed."

ic_info "Linking gcloud binaries into ${INSTALL_DIR}..."
for bin in gcloud gsutil bq; do
    [[ -f "${GCLOUD_INSTALL_DIR}/bin/${bin}" ]] && sudo ln -sf "${GCLOUD_INSTALL_DIR}/bin/${bin}" "${INSTALL_DIR}/${bin}"
done

command -v gcloud >/dev/null 2>&1 || ic_die "gcloud command not found in PATH after install!"
ic_rule
gcloud --version
ic_rule
ic_info "gcloud CLI installed. Run 'gcloud init' to set up your account/project."
