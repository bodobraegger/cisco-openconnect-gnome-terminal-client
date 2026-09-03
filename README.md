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

Ptyxis paints its own palette over VTE, so it **ignores** the OSC 11 escape
sequence that recolours other VTE terminals. The only way to colour a Ptyxis
window is a profile bound to a palette, selected with `--tab-with-profile`,
which opens a window of its own when no Ptyxis window is running.

The installer therefore provisions a profile labelled `VPN` using the
`vpn-deep-blue` palette, reusing an existing one if it finds it, and points the
launcher at it. The session script still emits OSC 11 as well, which is what
colours the window in other VTE terminals.

## Background mode

With `RUN_IN_BACKGROUND='yes'` (the default) openconnect daemonises once
authentication succeeds. The terminal window can then be closed while the tunnel
stays up, and the tray indicator becomes the session's only face.

This works because the blackhole is owned by the guardian, not the terminal. On
exit the session script checks whether an openconnect process is still alive and
leaves the route in place if so, which also closes a race in foreground mode
where Ctrl-C could otherwise withdraw the route before the tunnel had gone.

Set it to `no` to keep the tunnel tied to the terminal window instead.

## Tray indicator

The tray is the only control surface, and it carries exactly one action for the
current state:

| State | Shows | Action |
| --- | --- | --- |
| Connected | `Connected on tun0 (10.249.65.41)` | **Quit VPN** |
| Connecting | `Connecting, no tunnel address yet` | **Quit VPN** |
| Disconnected | `Disconnected` | **Connect...** |

There is deliberately no action that quits the indicator alone. A tunnel running
with no window and no tray icon is invisible, which is the state this tray
exists to prevent. **Quit VPN** stops the tunnel through `pkexec`; the guardian
then withdraws the blackhole, so stopping from the tray still ends with the
network restored.

A second line appears only when something needs attention: IPv6 open while
connected, or a blackhole still installed after the tunnel has gone. After any
action the menu refreshes once a second for a few seconds, so it never sits on a
stale `Connected`.

Requires the `AppIndicator3` typelib and, on GNOME, an AppIndicator extension.

## Tests

    ./tests/run-all.sh

No display, no root, and no VPN required.
