"""Turns a TunnelStatus into the labels and icon the tray shows.

Separate from the GTK code so the display logic is testable without a display.
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

IPV6_BLACKHOLED_LABEL = "IPv6 blackholed (traffic forced through tunnel)"
IPV6_OPEN_LABEL = "IPv6 open (traffic may bypass tunnel)"


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
    """The non-clickable informational lines at the top of the menu."""
    labels = [status.summary()]
    if status.connected:
        labels.append(
            IPV6_BLACKHOLED_LABEL if status.ipv6_blackholed else IPV6_OPEN_LABEL
        )
    return labels


def action_labels(status: TunnelStatus) -> list[str]:
    """The clickable actions, which depend on whether anything is running."""
    if status.process_running:
        return [DISCONNECT_LABEL, QUIT_LABEL]
    return [CONNECT_LABEL, QUIT_LABEL]
