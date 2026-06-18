#!/bin/bash
#
# update_all.sh — run every install_*.sh in ~/bin in a single pass.
#
# Sudo model: we prime the sudo timestamp once (one password prompt), then a
# background keep-alive refreshes it so each child script's own sudo calls
# succeed unattended. Most scripts call sudo internally and MUST run bare;
# the few that hard-require root (EUID 0) are invoked via sudo instead.
#
# Usage:
#   update_all.sh                 # update everything
#   update_all.sh --only trivy,yq # only the named tools
#   update_all.sh --skip chrome   # everything except the named tools
#   update_all.sh --list          # show what would run, then exit
#   update_all.sh --dry-run       # go through the motions without executing

set -u

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$(basename "${BASH_SOURCE[0]}")"   # this orchestrator, so we never run ourselves

# Scripts that hard-require root (they check EUID and drop privileges via
# $SUDO_USER). These get invoked as `sudo ./script`; all others run bare.
declare -A RUN_AS_ROOT=(
    [install_go.sh]=1
    [install_python3_version.sh]=1
)

# Non-installer helpers we never want in a blanket update run. The orchestrator
# itself ($SELF) is excluded unconditionally in is_excluded, so a future rename
# can't reintroduce the self-recursion.
EXCLUDE=()

# --- argument parsing ------------------------------------------------------
ONLY=""
SKIP=""
LIST_ONLY=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --only)    ONLY="${2:-}"; shift 2 ;;
        --skip)    SKIP="${2:-}"; shift 2 ;;
        --list)    LIST_ONLY=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help)
            grep '^#' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' | head -n 20
            exit 0
            ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

in_csv() { # in_csv <needle> <comma,list> — match against script name or tool stem
    local needle="$1" list="$2" item
    IFS=',' read -ra parts <<< "$list"
    for item in "${parts[@]}"; do
        item="${item// /}"
        [[ -z "$item" ]] && continue
        [[ "$needle" == "$item" ]] && return 0
        [[ "$needle" == "install_${item}.sh" ]] && return 0
        [[ "$needle" == "install_${item}" ]] && return 0
    done
    return 1
}

is_excluded() {
    local s="$1" e
    [[ "$s" == "$SELF" ]] && return 0   # never run ourselves (infinite recursion)
    for e in "${EXCLUDE[@]}"; do [[ "$s" == "$e" ]] && return 0; done
    return 1
}

# --- build the run list ----------------------------------------------------
SCRIPTS=()
for path in "$BIN_DIR"/install_*.sh; do
    [[ -e "$path" ]] || continue
    s="$(basename "$path")"
    is_excluded "$s" && continue
    [[ -n "$ONLY" ]] && ! in_csv "$s" "$ONLY" && continue
    [[ -n "$SKIP" ]] &&   in_csv "$s" "$SKIP" && continue
    SCRIPTS+=("$s")
done

if [[ ${#SCRIPTS[@]} -eq 0 ]]; then
    echo "No scripts selected." >&2
    exit 1
fi

if [[ $LIST_ONLY -eq 1 ]]; then
    echo "Would run ${#SCRIPTS[@]} script(s):"
    for s in "${SCRIPTS[@]}"; do
        mode="bare"; [[ -n "${RUN_AS_ROOT[$s]:-}" ]] && mode="sudo"
        printf '  %-32s [%s]\n' "$s" "$mode"
    done
    exit 0
fi

# --- prime sudo + keep-alive ----------------------------------------------
KEEPALIVE_PID=""
INTERRUPTED=0
cleanup() {
    [[ -n "$KEEPALIVE_PID" ]] && kill "$KEEPALIVE_PID" 2>/dev/null
}
# Ctrl-C reaches the whole process group, so the running child dies too. Flag
# the interrupt and re-raise with the default disposition so we exit 130 and
# stop the run loop, instead of recording it as a per-script failure and
# marching on to the next tool.
on_interrupt() {
    INTERRUPTED=1
    echo >&2
    echo "Interrupted - stopping." >&2
    cleanup
    trap - INT
    kill -INT "$$"
}
trap cleanup EXIT
trap on_interrupt INT TERM

if [[ $DRY_RUN -eq 0 ]]; then
    echo "Priming sudo (one prompt for the whole run)..."
    if ! sudo -v; then
        echo "Could not obtain sudo; aborting." >&2
        exit 1
    fi
    # Refresh the sudo timestamp every 50s until this script exits.
    ( while true; do sudo -n true 2>/dev/null; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
    KEEPALIVE_PID=$!
fi

# --- run -------------------------------------------------------------------
declare -a OK=() FAILED=() SKIPPED=()
START=$SECONDS

for s in "${SCRIPTS[@]}"; do
    path="$BIN_DIR/$s"
    mode="bare"; [[ -n "${RUN_AS_ROOT[$s]:-}" ]] && mode="sudo"

    echo
    echo "============================================================"
    echo ">>> $s  [$mode]"
    echo "============================================================"

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "(dry-run) would execute: ${mode/bare/}${mode:+ }$path"
        SKIPPED+=("$s")
        continue
    fi

    if [[ "$mode" == "sudo" ]]; then
        sudo "$path"
    else
        "$path"
    fi

    rc=$?
    # A child killed by SIGINT/SIGTERM exits 130/143. Treat that as "the user
    # wants out", not a tool failure: stop the whole run immediately.
    if [[ $INTERRUPTED -eq 1 || $rc -eq 130 || $rc -eq 143 ]]; then
        echo >&2
        echo "Interrupted during $s - stopping." >&2
        cleanup
        exit 130
    fi
    if [[ $rc -eq 0 ]]; then
        OK+=("$s")
    else
        FAILED+=("$s (exit $rc)")
    fi
done

# --- summary ---------------------------------------------------------------
ELAPSED=$((SECONDS - START))
echo
echo "============================================================"
echo "Summary  (${ELAPSED}s)"
echo "============================================================"
echo "  Succeeded: ${#OK[@]}"
for s in "${OK[@]}"; do echo "    ✓ $s"; done
if [[ ${#SKIPPED[@]} -gt 0 ]]; then
    echo "  Skipped (dry-run): ${#SKIPPED[@]}"
fi
if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo "  Failed: ${#FAILED[@]}"
    for s in "${FAILED[@]}"; do echo "    ✗ $s"; done
    exit 1
fi
echo
echo "All selected scripts completed successfully."
