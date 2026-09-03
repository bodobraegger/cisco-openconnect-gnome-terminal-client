"""Unit tests for tunnel status parsing. No display, no root, no tunnel required."""

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "lib"))

from openconnect_gnome.status import (  # noqa: E402
    ADDRESS_QUERY,
    IPV6_DEFAULT_ROUTE_QUERY,
    PROCESS_QUERY,
    TunnelStatus,
    parse_ipv6_blackhole,
    parse_tunnel_address,
    read_tunnel_status,
)

CONNECTED_ADDR_OUTPUT = (
    "1: lo    inet 127.0.0.1/8 scope host lo\\       valid_lft forever\n"
    "3: wlp3s0    inet 192.168.0.87/24 brd 192.168.0.255 scope global dynamic "
    "noprefixroute wlp3s0\\       valid_lft 5340sec\n"
    "9: tun0    inet 10.249.65.41/32 scope global tun0\\       valid_lft forever\n"
)
NO_TUNNEL_ADDR_OUTPUT = (
    "1: lo    inet 127.0.0.1/8 scope host lo\\       valid_lft forever\n"
    "3: wlp3s0    inet 192.168.0.87/24 scope global wlp3s0\\       valid_lft 5340sec\n"
)
BLACKHOLED_ROUTE_OUTPUT = (
    "unreachable default dev lo metric 1 pref medium\n"
    "default via fe80::10:18ff:fec2:bb8c dev wlp3s0 proto ra metric 600 pref medium\n"
)
PLAIN_ROUTE_OUTPUT = (
    "default via fe80::10:18ff:fec2:bb8c dev wlp3s0 proto ra metric 600 pref medium\n"
)


class ParseTunnelAddressTests(unittest.TestCase):
    def test_finds_tunnel_among_other_interfaces(self):
        self.assertEqual(
            parse_tunnel_address(CONNECTED_ADDR_OUTPUT), ("tun0", "10.249.65.41")
        )

    def test_returns_none_when_no_tunnel_present(self):
        self.assertEqual(parse_tunnel_address(NO_TUNNEL_ADDR_OUTPUT), (None, None))

    def test_ignores_non_inet_lines(self):
        self.assertEqual(
            parse_tunnel_address("9: tun0    inet6 fe80::1/64 scope link\n"),
            (None, None),
        )

    def test_tolerates_empty_and_short_lines(self):
        for output in ("", "\n", "garbage\n", "9: tun0\n"):
            with self.subTest(output=output):
                self.assertEqual(parse_tunnel_address(output), (None, None))

    def test_does_not_match_interfaces_merely_containing_tun(self):
        self.assertEqual(
            parse_tunnel_address("4: notun0    inet 10.0.0.1/24 scope global\n"),
            (None, None),
        )


class ParseBlackholeTests(unittest.TestCase):
    def test_detects_blackhole_route(self):
        self.assertTrue(parse_ipv6_blackhole(BLACKHOLED_ROUTE_OUTPUT))

    def test_absent_when_only_normal_default(self):
        self.assertFalse(parse_ipv6_blackhole(PLAIN_ROUTE_OUTPUT))

    def test_metric_must_match(self):
        self.assertFalse(
            parse_ipv6_blackhole("unreachable default dev lo metric 600 pref medium\n")
        )


class ReadTunnelStatusTests(unittest.TestCase):
    @staticmethod
    def _runner(addr_output, pgrep_output, route_output):
        responses = {
            ADDRESS_QUERY: addr_output,
            PROCESS_QUERY: pgrep_output,
            IPV6_DEFAULT_ROUTE_QUERY: route_output,
        }
        return lambda command: responses[command]

    def test_fully_connected(self):
        status = read_tunnel_status(
            self._runner(CONNECTED_ADDR_OUTPUT, "39446\n", BLACKHOLED_ROUTE_OUTPUT)
        )
        self.assertTrue(status.connected)
        self.assertTrue(status.ipv6_blackholed)
        self.assertEqual(status.summary(), "Connected on tun0 (10.249.65.41)")

    def test_process_up_but_no_address_is_connecting(self):
        status = read_tunnel_status(
            self._runner(NO_TUNNEL_ADDR_OUTPUT, "39446\n", PLAIN_ROUTE_OUTPUT)
        )
        self.assertFalse(status.connected)
        self.assertTrue(status.process_running)
        self.assertEqual(status.summary(), "Connecting, no tunnel address yet")

    def test_stale_interface_without_process_is_disconnected(self):
        status = read_tunnel_status(
            self._runner(CONNECTED_ADDR_OUTPUT, "", PLAIN_ROUTE_OUTPUT)
        )
        self.assertFalse(status.connected)
        self.assertEqual(status.summary(), "Disconnected")

    def test_status_is_immutable(self):
        status = TunnelStatus(None, None, False, False)
        with self.assertRaises(Exception):
            status.interface = "tun9"


if __name__ == "__main__":
    unittest.main(verbosity=2)
