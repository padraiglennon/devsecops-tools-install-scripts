#!/usr/bin/env bash
# install_awscli.sh — install/upgrade AWS CLI v2 via Amazon's official zip
# installer (not GitHub releases). Sources the shared lib for logging/plumbing;
# the AWS-installer invocation stays local.
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/install_common.sh"
# shellcheck source=lib/install_common.sh
. "$_LIB"
ic_strict

IC_TOOL_NAME=aws
IC_TOOL_DESC="AWS CLI v2 (amazonaws.com official installer)"

: "${INSTALL_DIR:=/usr/local/bin}"
ic_parse_args "$@"

ic_require curl unzip sudo

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)        AWS_ARCH="x86_64" ;;
    arm64|aarch64) AWS_ARCH="aarch64" ;;
    *)             ic_die "Unsupported architecture: $ARCH" ;;
esac
ic_info "Architecture: $AWS_ARCH"

ic_mktemp
cd "$IC_TMP_DIR"

ic_info "Downloading AWS CLI v2 installer..."
ic_download "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" "awscliv2.zip"

ic_info "Extracting installer..."
unzip -q awscliv2.zip || ic_die "Failed to unzip AWS CLI."

ic_info "Running AWS CLI installer (sudo required)..."
if command -v aws >/dev/null 2>&1; then
    sudo ./aws/install --bin-dir "$INSTALL_DIR" --install-dir /usr/local/aws-cli --update
else
    sudo ./aws/install --bin-dir "$INSTALL_DIR" --install-dir /usr/local/aws-cli
fi

command -v aws >/dev/null 2>&1 || ic_die "aws command not found in PATH after install!"
ic_rule
aws --version
ic_rule
ic_info "AWS CLI installed. Run 'aws configure' to set up credentials."
