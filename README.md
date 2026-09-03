# cisco-openconnect-gnome-terminal-client

An openconnect launcher for GNOME. It opens the VPN session in a distinctly
coloured terminal window, shows tunnel state in the top bar, and guarantees the
network is left the way it was found.

## Why it exists

`openconnect` on the command line works, but two things go wrong in practice.

**IPv6 escapes the tunnel.** Where the VPN gateway is IPv4-only, openconnect
negotiates no IPv6 route, so the system's IPv6 default route stays pointed at
the local ISP. Any service behind the VPN that resolves to a dual-stack host is
then reached from the wrong source address. When that host is an identity
provider, a login flow starts from the tunnel and finishes from the local ISP,
and source-IP-bound authentication rejects it. The session script blackholes the
IPv6 default route while connected, which forces everything onto IPv4 through
the tunnel.

**Cleanup gets skipped.** A blackhole route left behind after the VPN drops
means no IPv6 at all, with nothing obvious to point at. Cleanup here does not
depend on a single trap firing.

## How cleanup is guaranteed

Three layers, because no single one covers every exit:

| Exit path | Covered by |
| --- | --- |
| Normal exit, Ctrl-C, `kill`, closing the terminal | `trap ... EXIT INT TERM HUP QUIT` |
| `kill -9`, crash | Detached guardian process |
| Power loss, guardian also killed | Startup reconciliation on next launch |

The guardian is detached with `setsid`, so it survives the terminal's process
group being torn down, and withdraws the route once no `openconnect` remains. It
watches with `pgrep -x`, an exact match on the process name, so it can never
match its own command line. It is addressed by pidfile rather than `pkill -f`,
because a command-line pattern also matches unrelated processes that merely
mention the tag, up to and including the shell that launched the script.

If a long session outlives the sudo timestamp, cleanup is handed to the
guardian, which already runs as root, rather than blocking exit on a password
prompt.

## Install

    ./install.sh
    $EDITOR ~/.config/openconnect-gnome/config

Everything lands under `$HOME`: symlinks in `~/.local/bin`, a launcher in
`~/.local/share/applications`, a tray autostart entry in `~/.config/autostart`,
and the palette in `~/.local/share/org.gnome.Ptyxis/palettes`.

`./install.sh uninstall` removes all of it and leaves your config alone.

## Configuration

See `config.example`. `VPN_USER`, `VPN_GATEWAY` and `VPN_AUTHGROUP` are
required; the session refuses to start without them. `TERMINAL_BACKGROUND_COLOR`
is an OSC 11 colour spec, and `BLACKHOLE_IPV6` can be set to `no` where the
gateway carries IPv6 properly.

## Terminal colour

The window is coloured with an OSC 11 escape sequence and restored with OSC 111
on exit. This works in any VTE-based terminal and cannot leave a recoloured
profile behind if the session dies.

A Ptyxis palette is installed as well, but note that Ptyxis applies a profile
only to a tab (`--tab-with-profile`), never to a new window, so the palette is
useful only if you prefer running the session in a tab.

## Tray indicator

Polls tunnel state and shows connected, connecting, or disconnected, along with
whether IPv6 is currently blackholed. Connect launches the installed desktop
entry, so the launcher command lives in exactly one place. Disconnect goes
through `pkexec`; the guardian then withdraws the blackhole, so a tray-initiated
disconnect still ends with the network restored.

Requires the `AppIndicator3` typelib and, on GNOME, an AppIndicator extension.

## Tests

    ./tests/run-all.sh

No display, no root, and no VPN required.
