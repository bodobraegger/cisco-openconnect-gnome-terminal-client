"""Unit tests for tray presentation logic. Runs headless."""

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "lib"))

from openconnect_gnome.presentation import (  # noqa: E402
    CONNECT_LABEL,
    DISCONNECT_LABEL,
    FALLBACK_ICON,
    IPV6_BLACKHOLED_LABEL,
    IPV6_OPEN_LABEL,
    OPEN_TERMINAL_LABEL,
    QUIT_LABEL,
    QUIT_LABEL_IDLE,
    choose_icon,
    action_labels,
    status_labels,
)
from openconnect_gnome.status import TunnelStatus  # noqa: E402

CONNECTED = TunnelStatus("tun0", "10.249.65.41", True, True)
CONNECTED_LEAKING = TunnelStatus("tun0", "10.249.65.41", True, False)
CONNECTING = TunnelStatus(None, None, True, False)
DISCONNECTED = TunnelStatus(None, None, False, False)


class ChooseIconTests(unittest.TestCase):
    def test_prefers_first_available_candidate(self):
        self.assertEqual(choose_icon(CONNECTED), "network-vpn-symbolic")

    def test_falls_back_when_preferred_icon_missing(self):
        available = {"network-vpn"}
        self.assertEqual(
            choose_icon(CONNECTED, icon_exists=available.__contains__), "network-vpn"
        )

    def test_uses_last_resort_when_theme_has_nothing(self):
        self.assertEqual(
            choose_icon(CONNECTED, icon_exists=lambda name: False), FALLBACK_ICON
        )

    def test_each_state_has_a_distinct_preferred_icon(self):
        icons = {
            choose_icon(state) for state in (CONNECTED, CONNECTING, DISCONNECTED)
        }
        self.assertEqual(len(icons), 3, f"states must be visually distinct: {icons}")


class StatusLabelTests(unittest.TestCase):
    def test_connected_reports_address_and_blackhole(self):
        self.assertEqual(
            status_labels(CONNECTED),
            ["Connected on tun0 (10.249.65.41)", IPV6_BLACKHOLED_LABEL],
        )

    def test_connected_without_blackhole_warns_about_bypass(self):
        self.assertEqual(status_labels(CONNECTED_LEAKING)[1], IPV6_OPEN_LABEL)

    def test_disconnected_shows_no_ipv6_line(self):
        self.assertEqual(status_labels(DISCONNECTED), ["Disconnected"])


class ActionLabelTests(unittest.TestCase):
    def test_offers_disconnect_while_running(self):
        self.assertEqual(action_labels(CONNECTED)[0], DISCONNECT_LABEL)

    def test_offers_disconnect_while_still_connecting(self):
        self.assertEqual(action_labels(CONNECTING)[0], DISCONNECT_LABEL)

    def test_offers_connect_when_nothing_running(self):
        self.assertEqual(action_labels(DISCONNECTED)[0], CONNECT_LABEL)

    def test_terminal_can_be_opened_in_every_state(self):
        for state in (CONNECTED, CONNECTING, DISCONNECTED):
            with self.subTest(state=state):
                self.assertIn(OPEN_TERMINAL_LABEL, action_labels(state))

    def test_quit_is_always_available(self):
        for state in (CONNECTED, CONNECTING, DISCONNECTED):
            with self.subTest(state=state):
                labels = action_labels(state)
                self.assertTrue(any(label.startswith("Quit") for label in labels))

    def test_quit_warns_that_the_tunnel_survives_while_connected(self):
        for state in (CONNECTED, CONNECTING):
            with self.subTest(state=state):
                self.assertIn(QUIT_LABEL, action_labels(state))
                self.assertIn("VPN stays up", QUIT_LABEL)

    def test_quit_does_not_warn_when_nothing_is_running(self):
        self.assertIn(QUIT_LABEL_IDLE, action_labels(DISCONNECTED))


if __name__ == "__main__":
    unittest.main(verbosity=2)
