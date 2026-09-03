"""Turns a TunnelStatus into the labels and icon the tray shows.

Separate from the GTK code so the display logic is testable without a display.
The tray is the only control surface: a connect/disconnect toggle and a Quit
that closes the tunnel and the indicator together.
"""

from __future__ import annotations

from .status import TunnelStatus

CONNECTED_ICONS = ("network-vpn-symbolic", "network-vpn", "network-transmit-receive")
CONNECTING_ICONS = ("network-vpn-acquiring-symbolic", "network-vpn", "network-idle")
DISCONNECTED_ICONS = (
    "network-vpn-disconnected-symbolic",
    "network-offline-symbolic",
    "network-offline",
)
FALLBACK_ICON = "network-workgroup"

CONNECT_LABEL = "Connect..."
DISCONNECT_LABEL = "Disconnect"
QUIT_LABEL = "Quit"

IPV6_BYPASS_WARNING = "Warning: IPv6 is open, traffic may bypass the tunnel"
IPV6_ORPHAN_WARNING = "Warning: IPv6 still blackholed with no tunnel"


def icon_candidates(status: TunnelStatus) -> tuple[str, ...]:
    if status.connected:
        return CONNECTED_ICONS
    if status.process_running:
        return CONNECTING_ICONS
    return DISCONNECTED_ICONS


def choose_icon(status: TunnelStatus, icon_exists=lambda name: True) -> str:
    """Pick the first icon the active theme actually provides.

    Icon names differ between themes, and AppIndicator silently shows nothing for
    a missing name, so the candidates are probed rather than assumed.
    """
    for name in icon_candidates(status):
        if icon_exists(name):
            return name
    return FALLBACK_ICON


def status_labels(status: TunnelStatus) -> list[str]:
    """The informational lines. Only states worth acting on get a second line."""
    labels = [status.summary()]
    if status.connected and not status.ipv6_blackholed:
        labels.append(IPV6_BYPASS_WARNING)
    elif not status.process_running and status.ipv6_blackholed:
        labels.append(IPV6_ORPHAN_WARNING)
    return labels


def action_labels(status: TunnelStatus) -> list[str]:
    """A connect/disconnect toggle, plus Quit, which stops the tunnel and exits."""
    toggle = DISCONNECT_LABEL if status.process_running else CONNECT_LABEL
    return [toggle, QUIT_LABEL]
