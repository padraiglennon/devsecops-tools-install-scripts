#!/usr/bin/env bash
# install_github_cli.sh — install/upgrade gh (cli/cli) from GitHub releases.
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/install_common.sh"
# shellcheck source=lib/install_common.sh
. "$_LIB"
ic_strict

IC_TOOL_NAME=gh
IC_TOOL_DESC="GitHub CLI (cli/cli)"
IC_REPO=cli/cli
IC_ARCHIVE_TYPE=tar.gz
# shellcheck disable=SC2016  # template literal; expanded later by _ic_render
IC_ASSET_TMPL='gh_${VER}_${OS}_${ARCH}.tar.gz'
IC_OS_CASE=lower
declare -A ARCH_MAP=( [x86_64]=amd64 [aarch64]=arm64 [armv7l]=armv6 )
IC_LOCATOR='subdir:gh_${VER}_${OS}_${ARCH}/bin/gh'
IC_VERSION_CMD='--version'

: "${REQ_VERSION:=${GH_VERSION:-latest}}"
ic_parse_args "$@"
gh_binary_install
