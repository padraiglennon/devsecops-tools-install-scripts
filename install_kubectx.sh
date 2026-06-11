#!/usr/bin/env bash
# install_kubectx.sh — install/upgrade kubectx + kubens (ahmetb/kubectx).
# Twist: two binaries from separate archives in one release; x86_64 not remapped.
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/install_common.sh"
# shellcheck source=lib/install_common.sh
. "$_LIB"
ic_strict

IC_TOOL_NAME=kubectx
IC_TOOL_DESC="Fast kube-context/namespace switchers: kubectx + kubens (ahmetb/kubectx)"
IC_REPO=ahmetb/kubectx
IC_MULTI=( kubectx kubens )
IC_ARCHIVE_TYPE=tar.gz
# shellcheck disable=SC2016  # template literal; expanded later by _ic_render
IC_ASSET_TMPL='${TOOL}_${VER_TAG}_${OS}_${ARCH}.tar.gz'
IC_OS_CASE=lower
declare -A ARCH_MAP=( [x86_64]=x86_64 [aarch64]=arm64 [armv7l]=armv7 )
# shellcheck disable=SC2016  # template literal; expanded later by _ic_render
IC_LOCATOR='top:${TOOL}'
IC_VERSION_CMD='--version'

: "${REQ_VERSION:=${KUBECTX_VERSION:-latest}}"
ic_parse_args "$@"
gh_binary_install
