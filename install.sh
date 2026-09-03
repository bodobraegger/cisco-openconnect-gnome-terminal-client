#!/bin/bash
# Wires the session script, launcher, palette and tray into the user's session.
# Everything is installed per-user; nothing is written outside $HOME.
set -euo pipefail

readonly SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

readonly BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
readonly APPLICATIONS_DIR="${APPLICATIONS_DIR:-$HOME/.local/share/applications}"
readonly AUTOSTART_DIR="${AUTOSTART_DIR:-$HOME/.config/autostart}"
readonly PALETTE_DIR="${PALETTE_DIR:-$HOME/.local/share/org.gnome.Ptyxis/palettes}"
readonly CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/openconnect-gnome}"

readonly LAUNCHER_NAME='openconnect-gnome.desktop'
readonly TERMINAL_LAUNCHER_NAME='openconnect-gnome-terminal.desktop'
readonly AUTOSTART_NAME='openconnect-gnome-tray.desktop'
readonly SESSION_COMMAND='openconnect-session'
readonly TRAY_COMMAND='vpn-tray-indicator'
readonly WINDOW_TITLE='VPN'
readonly PALETTE_NAME='vpn-deep-blue'
readonly PTYXIS_PROFILE_LABEL='VPN'
readonly PTYXIS_SCHEMA='org.gnome.Ptyxis'
readonly PTYXIS_PROFILE_SCHEMA='org.gnome.Ptyxis.Profile'
readonly PTYXIS_PROFILE_PATH='/org/gnome/Ptyxis/Profiles'

# Terminals that can run a command in a fresh window, most preferred first.
readonly SUPPORTED_TERMINALS=(ptyxis gnome-terminal konsole xfce4-terminal kitty xterm)

# Ptyxis paints its own palette over VTE, so it ignores the OSC 11 sequence that
# recolours other VTE terminals. A dedicated profile bound to the palette is the
# only way to colour a Ptyxis window, and a profile can only be selected with
# --tab-with-profile, which opens a window of its own when none is running.
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
        if [[ $label == "$PTYXIS_PROFILE_LABEL" ]]; then
            echo "$uuid"
            return 0
        fi
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

terminal_command_for() {
    local terminal=$1 session_path=$2 profile_uuid=${3:-}
    case $terminal in
        ptyxis)
            if [[ -n $profile_uuid ]]; then
                echo "ptyxis --tab-with-profile=$profile_uuid --title=$WINDOW_TITLE -x $session_path"
            else
                echo "ptyxis --new-window --title=$WINDOW_TITLE -x $session_path"
            fi
            ;;
        gnome-terminal)  echo "gnome-terminal --title=$WINDOW_TITLE -- $session_path" ;;
        konsole)         echo "konsole -p tabtitle=$WINDOW_TITLE -e $session_path" ;;
        xfce4-terminal)  echo "xfce4-terminal --title=$WINDOW_TITLE -x $session_path" ;;
        kitty)           echo "kitty --title $WINDOW_TITLE $session_path" ;;
        xterm)           echo "xterm -T $WINDOW_TITLE -e $session_path" ;;
        *)               return 1 ;;
    esac
}

detect_terminal() {
    local terminal
    for terminal in "${SUPPORTED_TERMINALS[@]}"; do
        if command -v "$terminal" >/dev/null 2>&1; then
            echo "$terminal"
            return 0
        fi
    done
    return 1
}

render_template() {
    local template=$1 destination=$2 terminal_command=$3 needs_terminal=$4
    sed -e "s|@TERMINAL_COMMAND@|$terminal_command|g" \
        -e "s|@NEEDS_TERMINAL@|$needs_terminal|g" \
        -e "s|@BIN_DIR@|$BIN_DIR|g" \
        "$template" > "$destination"
}

install_all() {
    mkdir -p "$BIN_DIR" "$APPLICATIONS_DIR" "$AUTOSTART_DIR" "$PALETTE_DIR" "$CONFIG_DIR"

    ln -sf "$SOURCE_DIR/bin/$SESSION_COMMAND" "$BIN_DIR/$SESSION_COMMAND"
    ln -sf "$SOURCE_DIR/bin/$TRAY_COMMAND" "$BIN_DIR/$TRAY_COMMAND"

    local terminal terminal_command needs_terminal profile_uuid=''
    if terminal=$(detect_terminal); then
        if [[ $terminal == ptyxis ]]; then
            profile_uuid=$(provision_ptyxis_profile) ||
                echo "Could not create a Ptyxis profile, window will use default colours" >&2
            [[ -n $profile_uuid ]] && echo "Ptyxis profile: $profile_uuid ($PALETTE_NAME)"
        fi
        terminal_command=$(terminal_command_for "$terminal" "$BIN_DIR/$SESSION_COMMAND" "$profile_uuid")
        needs_terminal=false
        echo "Launcher will use: $terminal"
    else
        # No known terminal: let the desktop environment supply one.
        terminal_command="$BIN_DIR/$SESSION_COMMAND"
        needs_terminal=true
        echo "No supported terminal found, falling back to Terminal=true"
    fi

    render_template "$SOURCE_DIR/share/applications/$LAUNCHER_NAME.in" \
        "$APPLICATIONS_DIR/$LAUNCHER_NAME" "$terminal_command" "$needs_terminal"

    # A plain shell in the same profile, so the tray can open a VPN-coloured
    # terminal without starting a second session.
    local shell_command
    if [[ $terminal == ptyxis && -n $profile_uuid ]]; then
        shell_command="ptyxis --tab-with-profile=$profile_uuid --title=$WINDOW_TITLE"
    else
        shell_command="${terminal_command%% -x *}"
    fi
    render_template "$SOURCE_DIR/share/applications/$TERMINAL_LAUNCHER_NAME.in" \
        "$APPLICATIONS_DIR/$TERMINAL_LAUNCHER_NAME" "$shell_command" "$needs_terminal"
    render_template "$SOURCE_DIR/share/autostart/$AUTOSTART_NAME.in" \
        "$AUTOSTART_DIR/$AUTOSTART_NAME" "$terminal_command" "$needs_terminal"

    install -m 644 "$SOURCE_DIR/share/palettes/vpn-deep-blue.palette" "$PALETTE_DIR/"

    if [[ ! -e $CONFIG_DIR/config ]]; then
        install -m 600 "$SOURCE_DIR/config.example" "$CONFIG_DIR/config"
        echo "Wrote starter config to $CONFIG_DIR/config, edit it before connecting"
    else
        echo "Kept existing config at $CONFIG_DIR/config"
    fi

    command -v update-desktop-database >/dev/null 2>&1 &&
        update-desktop-database "$APPLICATIONS_DIR" 2>/dev/null

    echo "Installed. Start the tray now with: $BIN_DIR/$TRAY_COMMAND &"
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
    *)         echo "Usage: $0 [install|uninstall]" >&2; exit 64 ;;
esac
