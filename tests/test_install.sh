#!/bin/bash
# Drives install.sh against a throwaway prefix with ptyxis and gsettings stubbed,
# so it never touches the real dconf database or depends on the host's terminals.
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/harness.sh

WORKSPACE=$(mktemp -d)
trap 'rm -rf "$WORKSPACE"' EXIT

export BIN_DIR="$WORKSPACE/bin" APPLICATIONS_DIR="$WORKSPACE/app"
export AUTOSTART_DIR="$WORKSPACE/auto" PALETTE_DIR="$WORKSPACE/pal" CONFIG_DIR="$WORKSPACE/cfg"
export WORKSPACE

FAKE_BIN="$WORKSPACE/fakebin"; mkdir -p "$FAKE_BIN"
printf '#!/bin/sh\nexit 0\n' > "$FAKE_BIN/ptyxis"
cat > "$FAKE_BIN/gsettings" <<'GSETTINGS'
#!/bin/bash
STORE="$WORKSPACE/gsettings-store"; touch "$STORE"
case "$1" in
    get) if grep -q "^$2 $3 " "$STORE"; then grep -m1 "^$2 $3 " "$STORE" | cut -d' ' -f3-; else echo "@as []"; fi ;;
    set) sed -i "\|^$2 $3 |d" "$STORE"; echo "$2 $3 '$4'" >> "$STORE" ;;
esac
GSETTINGS
chmod +x "$FAKE_BIN/ptyxis" "$FAKE_BIN/gsettings"
export PATH="$FAKE_BIN:$PATH"

echo "install:"
OUTPUT=$(./install.sh install 2>&1)
UUID=$(grep -oE 'Ptyxis profile: [0-9a-f]{32}' <<< "$OUTPUT" | grep -oE '[0-9a-f]{32}')
assert_equals "provisions a Ptyxis profile" "$([ -n "$UUID" ] && echo yes || echo no)" yes
assert_equals "session symlink resolves to the repo" \
    "$(readlink -f "$BIN_DIR/openconnect-session")" "$PWD/bin/openconnect-session"
assert_equals "tray symlink installed" \
    "$([ -L "$BIN_DIR/vpn-tray-indicator" ] && echo yes || echo no)" yes
assert_equals "palette installed" \
    "$([ -f "$PALETTE_DIR/vpn-deep-blue.palette" ] && echo yes || echo no)" yes
assert_equals "config created private" "$(stat -c '%a' "$CONFIG_DIR/config")" 600
assert_equals "no autostart entry, the session starts the tray" \
    "$([ -e "$AUTOSTART_DIR/openconnect-gnome-tray.desktop" ] && echo yes || echo no)" no

LAUNCHER=$(cat "$APPLICATIONS_DIR/openconnect-gnome.desktop")
assert_not_contains "no unrendered placeholder" "$LAUNCHER" "@"
assert_contains "launcher runs the session" "$LAUNCHER" "$BIN_DIR/openconnect-session"
assert_contains "launcher applies the VPN profile" "$LAUNCHER" "--tab-with-profile=$UUID"

echo "reinstall:"
echo "# edited" >> "$CONFIG_DIR/config"
SECOND=$(./install.sh install 2>&1)
assert_contains "keeps an existing config" "$SECOND" "Kept existing config"
assert_contains "hand edit survives" "$(cat "$CONFIG_DIR/config")" "# edited"
assert_equals "reuses the same profile" \
    "$(grep -oE '[0-9a-f]{32}' <<< "$SECOND" | head -1)" "$UUID"

echo "uninstall:"
./install.sh uninstall >/dev/null 2>&1
assert_equals "launcher removed" \
    "$([ -e "$APPLICATIONS_DIR/openconnect-gnome.desktop" ] && echo yes || echo no)" no
assert_equals "config deliberately preserved" \
    "$([ -f "$CONFIG_DIR/config" ] && echo yes || echo no)" yes

./install.sh nonsense >/dev/null 2>&1
assert_equals "unknown subcommand exits 64" "$?" 64

report
