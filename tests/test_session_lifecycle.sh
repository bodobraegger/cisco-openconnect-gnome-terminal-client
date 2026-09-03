#!/bin/bash
# Drives bin/openconnect-session with sudo, pgrep, ip and setsid stubbed, so the
# ordering of privileged operations is checked without touching the network.
# Ordering is the point: installing the blackhole after openconnect, or failing to
# clear an orphaned one first, are the mistakes that actually hurt.
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/harness.sh

WORKSPACE=$(mktemp -d)
trap 'rm -rf "$WORKSPACE"' EXIT
SESSION="$PWD/bin/openconnect-session"

cat > "$WORKSPACE/stubs.sh" <<'STUBS'
sudo() {
    case "$1" in
        -v) return 0 ;;
        openconnect)
            echo "PRIV openconnect-ran $*"
            case "$*" in *--background*) touch "$STUB_STATE/running" ;; esac ;;
        *) echo "PRIV $*" ;;
    esac
    return 0
}
pgrep() {
    # Only the openconnect lookup is stubbed; path lookups must report nothing so
    # the code under test takes its "not running" branch.
    case "$*" in *vpn-tray-indicator*) return 1 ;; esac
    [ -f "$STUB_STATE/running" ] && { echo 5555; return 0; }
    [ "${STUB_STALE:-no}" = yes ] && { echo 4242; return 0; }
    return 1
}
ip() {
    [ "$1 $2 $3" = "-6 route show" ] && {
        [ "${STUB_LEFTOVER:-no}" = yes ] && echo "unreachable default dev lo metric 1 pref medium"
        return 0
    }
    return 0
}
setsid() { echo "STUB setsid $*"; }
export -f sudo pgrep ip setsid
STUBS

write_config() {
    mkdir -p "$WORKSPACE/$1/openconnect-gnome"
    cat > "$WORKSPACE/$1/openconnect-gnome/config"
}
run_session() {
    rm -rf "$WORKSPACE/state"; mkdir -p "$WORKSPACE/state"
    XDG_CONFIG_HOME="$WORKSPACE/$1" STUB_STALE=$2 STUB_LEFTOVER=$3 STUB_STATE="$WORKSPACE/state" \
        bash -c "source '$WORKSPACE/stubs.sh'; source '$SESSION'" </dev/null 2>&1
}

printf "VPN_USER='u'\nVPN_GATEWAY='g'\nVPN_AUTHGROUP='a'\nRUN_IN_BACKGROUND='no'\n" | write_config foreground
printf "VPN_USER='u'\nVPN_GATEWAY='g'\nVPN_AUTHGROUP='a'\nRUN_IN_BACKGROUND='yes'\n" | write_config background
printf "VPN_USER='u'\n" | write_config incomplete

echo "foreground:"
FG=$(run_session foreground no no)
assert_ordered "blackhole installed before openconnect" "$FG" "route replace" "openconnect-ran"
assert_ordered "blackhole withdrawn after openconnect" "$FG" "openconnect-ran" "route del"

echo "recovery from a previous hard kill:"
DIRTY=$(run_session foreground yes yes)
assert_contains "stale session killed" "$DIRTY" "Terminating stale openconnect session(s): 4242"
assert_ordered "orphan cleared before reinstall" "$DIRTY" "Removing IPv6 blackhole" "route replace"

echo "background:"
BG=$(run_session background no no)
assert_contains "openconnect daemonises" "$BG" "--background"
assert_not_contains "blackhole kept while the tunnel is up" "$BG" "route del"
assert_contains "tray started" "$BG" "Tray indicator started"
assert_contains "window declared closable" "$BG" "window can be closed"

echo "configuration errors:"
XDG_CONFIG_HOME="$WORKSPACE/missing" bash -c "source '$WORKSPACE/stubs.sh'; source '$SESSION'" >/dev/null 2>&1
assert_equals "missing config exits 2" "$?" 2
XDG_CONFIG_HOME="$WORKSPACE/incomplete" bash -c "source '$WORKSPACE/stubs.sh'; source '$SESSION'" >/dev/null 2>&1
assert_equals "incomplete config exits 3" "$?" 3

report
