# cisco-openconnect-gnome-terminal-client

An openconnect launcher for GNOME: it opens the VPN session in a distinctly
coloured terminal window and shows tunnel state in the top bar via a tray
indicator.

## Why it exists

Where the VPN gateway is IPv4-only, openconnect negotiates no IPv6 route, so
the system's IPv6 default route stays pointed at the local ISP. Any service
behind the VPN that resolves to a dual-stack host is then reached from two
source addresses at once: the tunnel for IPv4, the local ISP for IPv6. When
that service is an identity provider, a login flow splits across both and
source-IP-bound authentication rejects it. The session script blackholes the
IPv6 default route while connected, forcing everything onto IPv4 through the
tunnel.

Cleanup is a trap on exit, backed by startup reconciliation for when the trap
never ran, and by the tray indicator removing the route when it stops the
tunnel.

## Install

    ./install.sh
    $EDITOR ~/.config/openconnect-gnome/config

Everything lands under `$HOME`: symlinks in `~/.local/bin`, a launcher in
`~/.local/share/applications`, and the palette in
`~/.local/share/org.gnome.Ptyxis/palettes`.

`./install.sh uninstall` removes all of it and leaves your config alone.

## Configuration

See `config.example`. `VPN_USER`, `VPN_GATEWAY` and `VPN_AUTHGROUP` are
required; the session refuses to start without them. `RUN_IN_BACKGROUND`
(default `yes`) daemonises openconnect once authentication succeeds, so the
terminal can close while the tunnel stays up. `BLACKHOLE_IPV6` can be set to
`no` where the gateway carries IPv6 properly.

## Tray indicator

The session starts the tray on connect and it stays for the life of the
session, showing connection status with a toggle and Quit. A dropped tunnel
leaves the indicator in place offering **Reconnect**, since a VPN dying
mid-session is exactly when a one-click way back matters. **Quit** stops the
tunnel and exits.

Ptyxis ignores the OSC 11 escape sequence that recolours other VTE terminals,
so its window colour comes from a dedicated profile applied via
`--tab-with-profile`, which is tab-only.
