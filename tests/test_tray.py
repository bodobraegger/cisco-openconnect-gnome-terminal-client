"""Tray parsing and display logic. No display, no root, no VPN required."""

import importlib.machinery
import importlib.util
import pathlib
import sys
import unittest

TRAY_PATH = pathlib.Path(__file__).resolve().parent.parent / "bin" / "vpn-tray-indicator"
spec = importlib.util.spec_from_loader(
    "vpn_tray", importlib.machinery.SourceFileLoader("vpn_tray", str(TRAY_PATH))
)
tray = importlib.util.module_from_spec(spec)
# dataclasses resolves field types through sys.modules, so the module has to be
# registered before it is executed.
sys.modules["vpn_tray"] = tray
spec.loader.exec_module(tray)

ADDR_WITH_TUNNEL = (
    "1: lo    inet 127.0.0.1/8 scope host lo\\       valid_lft forever\n"
    "3: wlp3s0    inet 192.168.0.87/24 scope global wlp3s0\\       valid_lft 5340sec\n"
    "9: tun0    inet 10.249.65.41/32 scope global tun0\\       valid_lft forever\n"
)
ADDR_NO_TUNNEL = "3: wlp3s0    inet 192.168.0.87/24 scope global wlp3s0\\   valid_lft 1sec\n"
ROUTE_BLACKHOLED = "unreachable default dev lo metric 1 pref medium\ndefault via fe80::1 dev wlp3s0 metric 600\n"
ROUTE_NORMAL = "default via fe80::1 dev wlp3s0 proto ra metric 600 pref medium\n"


class ParsingTests(unittest.TestCase):
    def test_finds_tunnel_among_other_interfaces(self):
        self.assertEqual(tray.parse_tunnel_address(ADDR_WITH_TUNNEL), ("tun0", "10.249.65.41"))

    def test_no_tunnel_present(self):
        self.assertEqual(tray.parse_tunnel_address(ADDR_NO_TUNNEL), (None, None))

    def test_ignores_ipv6_only_and_malformed_lines(self):
        for output in ("", "garbage\n", "9: tun0\n", "9: tun0  inet6 fe80::1/64 scope link\n"):
            with self.subTest(output=output):
                self.assertEqual(tray.parse_tunnel_address(output), (None, None))

    def test_does_not_match_interfaces_merely_containing_tun(self):
        self.assertEqual(
            tray.parse_tunnel_address("4: notun0    inet 10.0.0.1/24 scope global\n"), (None, None)
        )

    def test_detects_blackhole_only_at_the_right_metric(self):
        self.assertTrue(tray.parse_ipv6_blackhole(ROUTE_BLACKHOLED))
        self.assertFalse(tray.parse_ipv6_blackhole(ROUTE_NORMAL))
        self.assertFalse(tray.parse_ipv6_blackhole("unreachable default dev lo metric 600\n"))

    def test_finds_authgroup_in_a_config_file(self):
        config = "VPN_USER='u@example.org'\nVPN_GATEWAY='vpn.example.org/gess'\nVPN_AUTHGROUP='gess'\n"
        self.assertEqual(tray.parse_authgroup(config), "gess")

    def test_authgroup_is_none_without_a_match(self):
        self.assertIsNone(tray.parse_authgroup("VPN_USER='u@example.org'\n"))


class StatusTests(unittest.TestCase):
    def test_reads_a_connected_tunnel(self):
        responses = {
            tray.ADDRESS_QUERY: ADDR_WITH_TUNNEL,
            tray.PROCESS_QUERY: "39446\n",
            tray.IPV6_DEFAULT_ROUTE_QUERY: ROUTE_BLACKHOLED,
        }
        status = tray.read_tunnel_status(responses.__getitem__, lambda: "gess")
        self.assertTrue(status.connected)
        self.assertTrue(status.ipv6_blackholed)
        self.assertEqual(status.summary(), "Connected on\ntun0 (10.249.65.41)\nvia /gess")

    def test_connected_without_a_readable_config_omits_the_namespace(self):
        responses = {
            tray.ADDRESS_QUERY: ADDR_WITH_TUNNEL,
            tray.PROCESS_QUERY: "39446\n",
            tray.IPV6_DEFAULT_ROUTE_QUERY: ROUTE_BLACKHOLED,
        }
        status = tray.read_tunnel_status(responses.__getitem__, lambda: None)
        self.assertEqual(status.summary(), "Connected on\ntun0 (10.249.65.41)")

    def test_process_without_address_is_still_connecting(self):
        responses = {
            tray.ADDRESS_QUERY: ADDR_NO_TUNNEL,
            tray.PROCESS_QUERY: "39446\n",
            tray.IPV6_DEFAULT_ROUTE_QUERY: ROUTE_NORMAL,
        }
        status = tray.read_tunnel_status(responses.__getitem__, lambda: "gess")
        self.assertFalse(status.connected)
        self.assertEqual(status.summary(), "Connecting, no tunnel address yet")

    def test_stale_interface_without_a_process_is_disconnected(self):
        responses = {
            tray.ADDRESS_QUERY: ADDR_WITH_TUNNEL,
            tray.PROCESS_QUERY: "",
            tray.IPV6_DEFAULT_ROUTE_QUERY: ROUTE_NORMAL,
        }
        status = tray.read_tunnel_status(responses.__getitem__, lambda: "gess")
        self.assertEqual(status.summary(), "Disconnected")


class EqualityTests(unittest.TestCase):
    def test_identical_status_compares_equal(self):
        # VpnTrayIndicator.refresh() skips touching the UI when the new
        # status equals the last one, to stop the indicator flickering on
        # every poll while it's hovered. That guard depends on this holding.
        first = tray.TunnelStatus("tun0", "10.0.0.1", True, True, "gess")
        second = tray.TunnelStatus("tun0", "10.0.0.1", True, True, "gess")
        self.assertEqual(first, second)

    def test_status_with_a_different_field_compares_unequal(self):
        base = tray.TunnelStatus("tun0", "10.0.0.1", True, True, "gess")
        changed = tray.TunnelStatus("tun0", "10.0.0.2", True, True, "gess")
        self.assertNotEqual(base, changed)


class IconTests(unittest.TestCase):
    def test_states_are_visually_distinct(self):
        states = (
            tray.TunnelStatus("tun0", "10.0.0.1", True, True),
            tray.TunnelStatus(None, None, True, False),
            tray.TunnelStatus(None, None, False, False),
        )
        icons = {tray.choose_icon(s, lambda name: True) for s in states}
        self.assertEqual(len(icons), 3, f"states must differ: {icons}")

    def test_falls_back_when_the_theme_lacks_every_candidate(self):
        status = tray.TunnelStatus("tun0", "10.0.0.1", True, True)
        self.assertEqual(tray.choose_icon(status, lambda name: False), tray.FALLBACK_ICON)


class StopCommandTests(unittest.TestCase):
    def test_preferred_stop_is_the_passwordless_helper(self):
        self.assertEqual(tray.STOP_TUNNEL_COMMAND, ("sudo", "-n", tray.PRIVILEGED_STOP_HELPER))

    def test_fallback_stop_does_both_jobs_in_one_prompt(self):
        # Both actions in a single privileged call, otherwise the user
        # authenticates twice and a cancel can leave the route behind.
        joined = " ".join(tray.STOP_TUNNEL_FALLBACK_COMMAND)
        for expected in ("pkexec", "pkill", "route del"):
            self.assertIn(expected, joined)


if __name__ == "__main__":
    unittest.main(verbosity=2)
