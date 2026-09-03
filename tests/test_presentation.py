"""Unit tests for tray presentation logic. Runs headless."""

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "lib"))

from openconnect_gnome.presentation import (  # noqa: E402
    CONNECT_LABEL,
    FALLBACK_ICON,
    IPV6_BYPASS_WARNING,
    DISCONNECT_LABEL,
    IPV6_ORPHAN_WARNING,
    QUIT_LABEL,
    action_labels,
    choose_icon,
    status_labels,
)
from openconnect_gnome.status import TunnelStatus  # noqa: E402

CONNECTED = TunnelStatus("tun0", "10.249.65.41", True, True)
CONNECTED_LEAKING = TunnelStatus("tun0", "10.249.65.41", True, False)
CONNECTING = TunnelStatus(None, None, True, False)
DISCONNECTED = TunnelStatus(None, None, False, False)
ORPHANED_BLACKHOLE = TunnelStatus(None, None, False, True)


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
        icons = {choose_icon(s) for s in (CONNECTED, CONNECTING, DISCONNECTED)}
        self.assertEqual(len(icons), 3, f"states must be visually distinct: {icons}")


class StatusLabelTests(unittest.TestCase):
    def test_healthy_connection_needs_only_one_line(self):
        self.assertEqual(status_labels(CONNECTED), ["Connected on tun0 (10.249.65.41)"])

    def test_warns_when_connected_but_ipv6_is_open(self):
        self.assertEqual(status_labels(CONNECTED_LEAKING)[1], IPV6_BYPASS_WARNING)

    def test_warns_when_blackhole_outlived_the_tunnel(self):
        self.assertEqual(status_labels(ORPHANED_BLACKHOLE)[1], IPV6_ORPHAN_WARNING)

    def test_plain_disconnected_state_is_a_single_line(self):
        self.assertEqual(status_labels(DISCONNECTED), ["Disconnected"])

    def test_connecting_is_reported_distinctly(self):
        self.assertEqual(status_labels(CONNECTING)[0], "Connecting, no tunnel address yet")


class ActionLabelTests(unittest.TestCase):
    def test_toggle_offers_disconnect_while_connected(self):
        self.assertEqual(action_labels(CONNECTED)[0], DISCONNECT_LABEL)

    def test_toggle_offers_disconnect_while_still_connecting(self):
        self.assertEqual(action_labels(CONNECTING)[0], DISCONNECT_LABEL)

    def test_toggle_offers_connect_when_nothing_running(self):
        self.assertEqual(action_labels(DISCONNECTED)[0], CONNECT_LABEL)

    def test_quit_is_offered_in_every_state(self):
        for state in (CONNECTED, CONNECTING, DISCONNECTED, ORPHANED_BLACKHOLE):
            with self.subTest(state=state):
                self.assertEqual(action_labels(state)[1], QUIT_LABEL)

    def test_exactly_two_actions_in_every_state(self):
        for state in (CONNECTED, CONNECTING, DISCONNECTED, ORPHANED_BLACKHOLE):
            with self.subTest(state=state):
                self.assertEqual(len(action_labels(state)), 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
