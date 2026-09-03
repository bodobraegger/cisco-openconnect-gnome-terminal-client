#!/bin/bash
# Wires the session script, launcher, palette and tray into the user's session.
# Everything is installed per-user; nothing is written outside $HOME.
set -euo pipefail

readonly SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BIN_DIR="${BIN_DIR:-$HOME/.local/bin}" APPLICATIONS_DIR="${APPLICATIONS_DIR:-$HOME/.local/share/applications}"
readonly AUTOSTART_DIR="${AUTOSTART_DIR:-$HOME/.config/autostart}" PALETTE_DIR="${PALETTE_DIR:-$HOME/.local/share/org.gnome.Ptyxis/palettes}"
readonly CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/openconnect-gnome}"
readonly LAUNCHER_NAME='openconnect-gnome.desktop' TERMINAL_LAUNCHER_NAME='openconnect-gnome-terminal.desktop'
readonly AUTOSTART_NAME='openconnect-gnome-tray.desktop' SESSION_COMMAND='openconnect-session' TRAY_COMMAND='vpn-tray-indicator'
readonly WINDOW_TITLE='VPN' PALETTE_NAME='vpn-deep-blue' PTYXIS_PROFILE_LABEL='VPN'
readonly PTYXIS_SCHEMA='org.gnome.Ptyxis' PTYXIS_PROFILE_SCHEMA='org.gnome.Ptyxis.Profile' PTYXIS_PROFILE_PATH='/org/gnome/Ptyxis/Profiles'
readonly START_HELPER='/usr/local/sbin/vpn-start' STOP_HELPER='/usr/local/sbin/vpn-stop'
readonly SUDOERS_FILE='/etc/sudoers.d/vpn' IPV6_BLACKHOLE_METRIC=1 OPENCONNECT_PIDFILE='/run/openconnect-gnome.pid'
readonly PKILL_BINARY='/usr/bin/pkill' IP_BINARY='/usr/sbin/ip' OPENCONNECT_BINARY='/usr/sbin/openconnect'

# Ptyxis paints its own palette over VTE, so it ignores the OSC 11 sequence that
# recolours other VTE terminals. A dedicated profile bound to the palette is the
# only way to colour a Ptyxis window, selected with --tab-with-profile, which
# opens a window of its own when none is running.
provision_ptyxis_profile() {
    command -v gsettings >/dev/null 2>&1 || return 1
    local existing uuid label
    existing=$(gsettings get "$PTYXIS_SCHEMA" profile-uuids 2>/dev/null) || return 1
    # The list is rebuilt from the uuids found rather than by editing the raw
    # value, so an empty or unexpected representation cannot corrupt it.
    local -a uuids=()
    mapfile -t uuids < <(grep -oE "[0-9a-f]{32}" <<< "$existing")
    for uuid in "${uuids[@]}"; do
        # gsettings quotes strings; a stubbed or future version might not.
        label=$(gsettings get "$PTYXIS_PROFILE_SCHEMA:$PTYXIS_PROFILE_PATH/$uuid/" label 2>/dev/null | tr -d "'")
        [[ $label == "$PTYXIS_PROFILE_LABEL" ]] && { echo "$uuid"; return 0; }
    done
    uuid=$(uuidgen | tr -d -)
    uuids+=("$uuid")
    local joined
    printf -v joined "'%s', " "${uuids[@]}"
    gsettings set "$PTYXIS_SCHEMA" profile-uuids "[${joined%, }]"
    gsettings set "$PTYXIS_PROFILE_SCHEMA:$PTYXIS_PROFILE_PATH/$uuid/" label "$PTYXIS_PROFILE_LABEL"
    gsettings set "$PTYXIS_PROFILE_SCHEMA:$PTYXIS_PROFILE_PATH/$uuid/" palette "$PALETTE_NAME"
    echo "$uuid"
}

install_all() {
    mkdir -p "$BIN_DIR" "$APPLICATIONS_DIR" "$PALETTE_DIR" "$CONFIG_DIR"
    ln -sf "$SOURCE_DIR/bin/$SESSION_COMMAND" "$BIN_DIR/$SESSION_COMMAND"
    ln -sf "$SOURCE_DIR/bin/$TRAY_COMMAND" "$BIN_DIR/$TRAY_COMMAND"
    local terminal_command needs_terminal=false
    if command -v ptyxis >/dev/null 2>&1; then
        local profile_uuid='' window_flag='--new-window'
        profile_uuid=$(provision_ptyxis_profile) ||
            echo "Could not create a Ptyxis profile, window will use default colours" >&2
        if [[ -n $profile_uuid ]]; then
            window_flag="--tab-with-profile=$profile_uuid"
            echo "Ptyxis profile: $profile_uuid ($PALETTE_NAME)"
        fi
        terminal_command="ptyxis $window_flag --title=$WINDOW_TITLE -x $BIN_DIR/$SESSION_COMMAND"
    else
        # No Ptyxis: let the desktop environment supply a terminal.
        terminal_command="$BIN_DIR/$SESSION_COMMAND"
        needs_terminal=true
        echo "Ptyxis not found, falling back to Terminal=true"
    fi
    sed -e "s|@TERMINAL_COMMAND@|$terminal_command|g" -e "s|@NEEDS_TERMINAL@|$needs_terminal|g" \
        -e "s|@BIN_DIR@|$BIN_DIR|g" "$SOURCE_DIR/share/applications/$LAUNCHER_NAME.in" \
        > "$APPLICATIONS_DIR/$LAUNCHER_NAME"

    # The Open Terminal feature and login autostart were removed; clear any
    # entries an older install left behind.
    rm -f "$APPLICATIONS_DIR/$TERMINAL_LAUNCHER_NAME" "$AUTOSTART_DIR/$AUTOSTART_NAME"
    install -m 644 "$SOURCE_DIR/share/palettes/vpn-deep-blue.palette" "$PALETTE_DIR/"

    if [[ ! -e $CONFIG_DIR/config ]]; then
        install -m 600 "$SOURCE_DIR/config.example" "$CONFIG_DIR/config"
        echo "Wrote starter config to $CONFIG_DIR/config, edit it before connecting"
    else
        echo "Kept existing config at $CONFIG_DIR/config"
    fi
    command -v update-desktop-database >/dev/null 2>&1 &&
        update-desktop-database "$APPLICATIONS_DIR" 2>/dev/null
    echo "Installed. The tray appears when a VPN session starts."
}

# Prints the commands that install the root-owned helpers plus a NOPASSWD rule
# for them, so connecting and disconnecting stop prompting. Printed rather than
# run: this is the one part that needs root, and you should read it first.
print_helper_commands() {
    # shellcheck source=/dev/null
    source "$CONFIG_DIR/config" 2>/dev/null || { echo "No config at $CONFIG_DIR/config" >&2; exit 1; }
    : "${BLACKHOLE_IPV6:=yes}" "${RUN_IN_BACKGROUND:=yes}"

    local blackhole_lines='' background_flags=''
    [[ $BLACKHOLE_IPV6 == yes ]] && blackhole_lines="$IP_BINARY -6 route del unreachable default metric $IPV6_BLACKHOLE_METRIC 2>/dev/null
$IP_BINARY -6 route replace unreachable default metric $IPV6_BLACKHOLE_METRIC"
    [[ $RUN_IN_BACKGROUND == yes ]] &&
        background_flags="--background --pid-file $OPENCONNECT_PIDFILE"

    cat <<COMMANDS
sudo tee $START_HELPER >/dev/null <<'HELPER'
#!/bin/sh
# Generated by install.sh helpers. Takes no arguments by design.
$PKILL_BINARY -x openconnect 2>/dev/null
$blackhole_lines
exec $OPENCONNECT_BINARY -u $VPN_USER --useragent=AnyConnect -g $VPN_AUTHGROUP \\
  --no-external-auth $background_flags $VPN_GATEWAY
HELPER

sudo tee $STOP_HELPER >/dev/null <<'HELPER'
#!/bin/sh
$PKILL_BINARY -x openconnect
$IP_BINARY -6 route del unreachable default metric $IPV6_BLACKHOLE_METRIC 2>/dev/null
exit 0
HELPER

sudo chmod 755 $START_HELPER $STOP_HELPER
sudo tee $SUDOERS_FILE >/dev/null <<'RULE'
$USER ALL=(root) NOPASSWD: $START_HELPER, $STOP_HELPER
RULE
sudo chmod 440 $SUDOERS_FILE
sudo visudo -c
COMMANDS
}

uninstall_all() {
    rm -f "$BIN_DIR/$SESSION_COMMAND" "$BIN_DIR/$TRAY_COMMAND"
    rm -f "$APPLICATIONS_DIR/$LAUNCHER_NAME" "$APPLICATIONS_DIR/$TERMINAL_LAUNCHER_NAME" \
        "$AUTOSTART_DIR/$AUTOSTART_NAME"
    rm -f "$PALETTE_DIR/vpn-deep-blue.palette"
    echo "Removed. Configuration at $CONFIG_DIR was left in place."
}

case "${1:-install}" in
    install)   install_all ;;
    uninstall) uninstall_all ;;
    helpers)   print_helper_commands ;;
    *)         echo "Usage: $0 [install|uninstall|helpers]" >&2; exit 64 ;;
esac
