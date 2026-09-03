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
        openconnect) echo "PRIV openconnect-ran" ;;
        *) echo "PRIV $*" ;;
    esac
    return 0
}
pgrep() { [ "${STUB_STALE:-no}" = yes ] && { echo 4242; return 0; }; return 1; }
ip() {
    if [ "$1 $2 $3" = "-6 route show" ]; then
        [ "${STUB_LEFTOVER:-no}" = yes ] && echo "unreachable default dev lo metric 1 pref medium"
        return 0
    fi
    return 0
}
export -f sudo pgrep ip
STUBS

write_config() {
    local dir="$WORKSPACE/$1/openconnect-gnome"
    mkdir -p "$dir"
    cat > "$dir/config"
}

run_session() {
    XDG_CONFIG_HOME="$WORKSPACE/$1" STUB_STALE=$2 STUB_LEFTOVER=$3 \
        bash -c "source '$WORKSPACE/stubs.sh'; source '$SESSION_SCRIPT'" </dev/null 2>&1
}

write_config good <<'CONF'
VPN_USER='someone@example.org'
VPN_GATEWAY='vpn.example.org/group'
VPN_AUTHGROUP='group'
BLACKHOLE_IPV6='yes'
CONF

write_config noblackhole <<'CONF'
VPN_USER='someone@example.org'
VPN_GATEWAY='vpn.example.org/group'
VPN_AUTHGROUP='group'
BLACKHOLE_IPV6='no'
CONF

write_config incomplete <<'CONF'
VPN_USER='someone@example.org'
CONF

echo "clean start:"
CLEAN=$(run_session good no no)
assert_ordered "blackhole installed before openconnect" "$CLEAN" "route replace" "openconnect-ran"
assert_ordered "blackhole withdrawn after openconnect" "$CLEAN" "openconnect-ran" "route del"

echo "recovery from a previous hard kill:"
DIRTY=$(run_session good yes yes)
assert_contains "stale session killed" "$DIRTY" "Terminating stale openconnect session(s): 4242"
assert_ordered "orphaned blackhole cleared before reinstall" \
    "$DIRTY" "Removing IPv6 blackhole" "route replace"

echo "blackhole disabled:"
NOROUTE=$(run_session noblackhole no no)
assert_not_contains "no route touched" "$NOROUTE" "route replace"
assert_contains "openconnect still runs" "$NOROUTE" "openconnect-ran"

echo "configuration errors:"
XDG_CONFIG_HOME="$WORKSPACE/missing" bash -c "source '$WORKSPACE/stubs.sh'; source '$SESSION_SCRIPT'" >/dev/null 2>&1
assert_equals "missing config exits 2" "$?" 2
XDG_CONFIG_HOME="$WORKSPACE/incomplete" bash -c "source '$WORKSPACE/stubs.sh'; source '$SESSION_SCRIPT'" >/dev/null 2>&1
assert_equals "incomplete config exits 3" "$?" 3

report
