"""Reads VPN tunnel state from the running system.

Kept free of GTK so it can be exercised without a display, and split into a pure
parser plus a thin command runner so the parsing is testable without a tunnel.
"""

from __future__ import annotations

import subprocess
from dataclasses import dataclass

TUNNEL_INTERFACE_PREFIX = "tun"
OPENCONNECT_PROCESS_NAME = "openconnect"
IPV6_BLACKHOLE_METRIC = 1

ADDRESS_QUERY = ("ip", "-o", "-4", "addr", "show")
PROCESS_QUERY = ("pgrep", "-x", OPENCONNECT_PROCESS_NAME)
IPV6_DEFAULT_ROUTE_QUERY = ("ip", "-6", "route", "show", "default")


@dataclass(frozen=True)
class TunnelStatus:
    """A point-in-time view of the tunnel."""

    interface: str | None
    address: str | None
    process_running: bool
    ipv6_blackholed: bool

    @property
    def connected(self) -> bool:
        return self.process_running and self.address is not None

    def summary(self) -> str:
        if self.connected:
            return f"Connected on {self.interface} ({self.address})"
        if self.process_running:
            return "Connecting, no tunnel address yet"
        return "Disconnected"


def parse_tunnel_address(ip_output: str) -> tuple[str | None, str | None]:
    """Extract the first tunnel interface and its IPv4 address from `ip -o -4 addr show`.

    Each line looks like:
        7: tun0    inet 10.249.65.41/32 scope global tun0\\       valid_lft ...
    """
    for line in ip_output.splitlines():
        fields = line.split()
        if len(fields) < 4:
            continue
        interface = fields[1]
        if not interface.startswith(TUNNEL_INTERFACE_PREFIX):
            continue
        if fields[2] != "inet":
            continue
        return interface, fields[3].split("/")[0]
    return None, None


def parse_ipv6_blackhole(route_output: str, metric: int = IPV6_BLACKHOLE_METRIC) -> bool:
    """Detect the blackhole route the session script installs while connected."""
    for line in route_output.splitlines():
        if line.startswith("unreachable") and f"metric {metric}" in line:
            return True
    return False


def _run(command: tuple[str, ...]) -> str:
    try:
        completed = subprocess.run(
            command, capture_output=True, text=True, check=False, timeout=5
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return completed.stdout


def read_tunnel_status(run_command=_run) -> TunnelStatus:
    interface, address = parse_tunnel_address(run_command(ADDRESS_QUERY))
    process_running = bool(run_command(PROCESS_QUERY).strip())
    blackholed = parse_ipv6_blackhole(run_command(IPV6_DEFAULT_ROUTE_QUERY))
    return TunnelStatus(
        interface=interface,
        address=address,
        process_running=process_running,
        ipv6_blackholed=blackholed,
    )
