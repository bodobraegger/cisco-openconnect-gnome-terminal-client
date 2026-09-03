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

# Stub ptyxis and gsettings so the test is deterministic on any host and never
# writes to the real dconf database.
FAKE_BIN="$WORKSPACE/fakebin"
mkdir -p "$FAKE_BIN"
printf '#!/bin/sh\nexit 0\n' > "$FAKE_BIN/ptyxis"
cat > "$FAKE_BIN/gsettings" <<'GSETTINGS'
#!/bin/bash
STORE="$WORKSPACE/gsettings-store"
touch "$STORE"
case "$1" in
    get) grep -m1 "^$2 $3 " "$STORE" | cut -d' ' -f3- || echo "@as []" ;;
    set) sed -i "\|^$2 $3 |d" "$STORE"; echo "$2 $3 $4" >> "$STORE" ;;
esac
exit 0
GSETTINGS
chmod +x "$FAKE_BIN/ptyxis" "$FAKE_BIN/gsettings"
export WORKSPACE
export PATH="$FAKE_BIN:$PATH"

echo "install:"
INSTALL_OUTPUT=$(./install.sh install 2>&1)
assert_contains "detects ptyxis" "$INSTALL_OUTPUT" "Launcher will use: ptyxis"
assert_contains "provisions a Ptyxis profile" "$INSTALL_OUTPUT" "Ptyxis profile:"
PROFILE_UUID=$(echo "$INSTALL_OUTPUT" | grep -oE 'Ptyxis profile: [0-9a-f]{32}' | grep -oE '[0-9a-f]{32}')

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
assert_contains "launcher selects the VPN profile" \
    "$LAUNCHER" "--tab-with-profile=$PROFILE_UUID"

echo "profile provisioning is idempotent:"
SECOND_OUTPUT=$(./install.sh install 2>&1)
SECOND_UUID=$(echo "$SECOND_OUTPUT" | grep -oE 'Ptyxis profile: [0-9a-f]{32}' | grep -oE '[0-9a-f]{32}')
assert_equals "reuses the existing profile" "$SECOND_UUID" "$PROFILE_UUID"
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
