#!/bin/bash
# Exercises install.sh against a throwaway prefix, never touching the real session.
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/harness.sh

WORKSPACE=$(mktemp -d)
trap 'rm -rf "$WORKSPACE"' EXIT

export BIN_DIR="$WORKSPACE/bin"
export APPLICATIONS_DIR="$WORKSPACE/applications"
export AUTOSTART_DIR="$WORKSPACE/autostart"
export PALETTE_DIR="$WORKSPACE/palettes"
export CONFIG_DIR="$WORKSPACE/config"

echo "install:"
INSTALL_OUTPUT=$(./install.sh install 2>&1)

assert_equals "session command is a symlink" \
    "$([ -L "$BIN_DIR/openconnect-session" ] && echo yes || echo no)" yes
assert_equals "symlink resolves to the repo script" \
    "$(readlink -f "$BIN_DIR/openconnect-session")" "$PWD/bin/openconnect-session"
assert_equals "tray command is installed" \
    "$([ -L "$BIN_DIR/vpn-tray-indicator" ] && echo yes || echo no)" yes
assert_equals "palette is installed" \
    "$([ -f "$PALETTE_DIR/vpn-deep-blue.palette" ] && echo yes || echo no)" yes

LAUNCHER=$(cat "$APPLICATIONS_DIR/openconnect-gnome.desktop")
assert_not_contains "no unrendered placeholder in launcher" "$LAUNCHER" "@"
assert_contains "launcher execs the installed session command" \
    "$LAUNCHER" "$BIN_DIR/openconnect-session"
assert_contains "launcher declares an application" "$LAUNCHER" "Type=Application"

AUTOSTART=$(cat "$AUTOSTART_DIR/openconnect-gnome-tray.desktop")
assert_not_contains "no unrendered placeholder in autostart" "$AUTOSTART" "@"
assert_contains "autostart runs the tray" "$AUTOSTART" "$BIN_DIR/vpn-tray-indicator"

assert_equals "starter config created" \
    "$([ -f "$CONFIG_DIR/config" ] && echo yes || echo no)" yes
assert_equals "config is not world readable" \
    "$(stat -c '%a' "$CONFIG_DIR/config")" 600

echo "reinstall over an edited config:"
echo "# edited by hand" >> "$CONFIG_DIR/config"
REINSTALL_OUTPUT=$(./install.sh install 2>&1)
assert_contains "existing config is kept" "$REINSTALL_OUTPUT" "Kept existing config"
assert_contains "hand edit survives reinstall" \
    "$(cat "$CONFIG_DIR/config")" "# edited by hand"

echo "uninstall:"
./install.sh uninstall >/dev/null 2>&1
assert_equals "session command removed" \
    "$([ -e "$BIN_DIR/openconnect-session" ] && echo yes || echo no)" no
assert_equals "launcher removed" \
    "$([ -e "$APPLICATIONS_DIR/openconnect-gnome.desktop" ] && echo yes || echo no)" no
assert_equals "palette removed" \
    "$([ -e "$PALETTE_DIR/vpn-deep-blue.palette" ] && echo yes || echo no)" no
assert_equals "config deliberately preserved" \
    "$([ -f "$CONFIG_DIR/config" ] && echo yes || echo no)" yes

echo "bad usage:"
./install.sh nonsense >/dev/null 2>&1
assert_equals "unknown subcommand exits 64" "$?" 64

report
