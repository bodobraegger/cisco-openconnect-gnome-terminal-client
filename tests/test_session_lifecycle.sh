#!/bin/bash
# Drives bin/openconnect-session with sudo, pgrep and ip stubbed out, so the
# ordering of privileged operations is verified without touching the network.
# Ordering is the point: installing the blackhole after openconnect, or failing
# to clear an orphaned one first, are the mistakes that actually hurt.
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/harness.sh

WORKSPACE=$(mktemp -d)
trap 'rm -rf "$WORKSPACE"' EXIT
SESSION_SCRIPT="$PWD/bin/openconnect-session"

cat > "$WORKSPACE/stubs.sh" <<'STUBS'
sudo() {
    case "$1" in
        -v) return 0 ;;
        -n) shift
            case "$1" in
                true) return 0 ;;
                cat|tr|rm|kill) return 1 ;;
                *) echo "PRIV $*" ;;
            esac
            return 0 ;;
        openconnect)
            echo "PRIV openconnect-ran $*"
            # Background mode leaves a live process behind; record that so the
            # pgrep stub reports a tunnel that outlives this script.
            case "$*" in *--background*) touch "$STUB_STATE/running" ;; esac
            ;;
        *) echo "PRIV $*" ;;
    esac
    return 0
}
pgrep() {
    # Only the openconnect lookup is stubbed; path lookups (tray, session) must
    # report nothing so the code under test takes the "not running" branch.
    case "$*" in
        *vpn-tray-indicator*|*openconnect-session*) return 1 ;;
    esac
    [ -f "$STUB_STATE/running" ] && { echo 5555; return 0; }
    [ "${STUB_STALE:-no}" = yes ] && { echo 4242; return 0; }
    return 1
}
ip() {
    if [ "$1 $2 $3" = "-6 route show" ]; then
        [ "${STUB_LEFTOVER:-no}" = yes ] && echo "unreachable default dev lo metric 1 pref medium"
        return 0
    fi
    return 0
}
setsid() { echo "STUB setsid $*"; }
export -f sudo pgrep ip setsid
STUBS

write_config() {
    local dir="$WORKSPACE/$1/openconnect-gnome"
    mkdir -p "$dir"
    cat > "$dir/config"
}

run_session() {
    rm -rf "$WORKSPACE/state"; mkdir -p "$WORKSPACE/state"
    XDG_CONFIG_HOME="$WORKSPACE/$1" STUB_STALE=$2 STUB_LEFTOVER=$3 \
        STUB_STATE="$WORKSPACE/state" \
        bash -c "source '$WORKSPACE/stubs.sh'; source '$SESSION_SCRIPT'" </dev/null 2>&1
}

write_config good <<'CONF'
VPN_USER='someone@example.org'
VPN_GATEWAY='vpn.example.org/group'
VPN_AUTHGROUP='group'
BLACKHOLE_IPV6='yes'
RUN_IN_BACKGROUND='no'
CONF

write_config background <<'CONF'
VPN_USER='someone@example.org'
VPN_GATEWAY='vpn.example.org/group'
VPN_AUTHGROUP='group'
BLACKHOLE_IPV6='yes'
RUN_IN_BACKGROUND='yes'
CONF

write_config noblackhole <<'CONF'
VPN_USER='someone@example.org'
VPN_GATEWAY='vpn.example.org/group'
VPN_AUTHGROUP='group'
BLACKHOLE_IPV6='no'
RUN_IN_BACKGROUND='no'
CONF

write_config incomplete <<'CONF'
VPN_USER='someone@example.org'
CONF

echo "clean start:"
CLEAN=$(run_session good no no)
assert_ordered "blackhole installed before openconnect" "$CLEAN" "route replace" "openconnect-ran"
assert_ordered "blackhole withdrawn after openconnect" "$CLEAN" "openconnect-ran" "route del"
assert_not_contains "no tray started when the tunnel did not survive" "$CLEAN" "Tray indicator started"

echo "recovery from a previous hard kill:"
DIRTY=$(run_session good yes yes)
assert_contains "stale session killed" "$DIRTY" "Terminating stale openconnect session(s): 4242"
assert_ordered "orphaned blackhole cleared before reinstall" \
    "$DIRTY" "Removing IPv6 blackhole" "route replace"

echo "blackhole disabled:"
NOROUTE=$(run_session noblackhole no no)
assert_not_contains "no route touched" "$NOROUTE" "route replace"
assert_contains "openconnect still runs" "$NOROUTE" "openconnect-ran"

echo "background mode (window can close, tunnel survives):"
BACKGROUND=$(run_session background no no)
assert_contains "openconnect daemonises" "$BACKGROUND" "--background"
assert_contains "blackhole handed to the guardian" "$BACKGROUND" "guardian keeps the IPv6 blackhole"
assert_not_contains "blackhole not withdrawn while tunnel is up" "$BACKGROUND" "route del"
assert_contains "tells the user the window is closable" "$BACKGROUND" "window can be closed"
assert_contains "starts the tray indicator" "$BACKGROUND" "Tray indicator started"

echo "configuration errors:"
XDG_CONFIG_HOME="$WORKSPACE/missing" bash -c "source '$WORKSPACE/stubs.sh'; source '$SESSION_SCRIPT'" >/dev/null 2>&1
assert_equals "missing config exits 2" "$?" 2
XDG_CONFIG_HOME="$WORKSPACE/incomplete" bash -c "source '$WORKSPACE/stubs.sh'; source '$SESSION_SCRIPT'" >/dev/null 2>&1
assert_equals "incomplete config exits 3" "$?" 3

report
