#!/usr/bin/python3
"""Run: python3 check_game_captures.py — temporary files, no GUI or recorder launched."""
import json
from argparse import Namespace
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

from caelestia.utils import capture
from caelestia.subcommands import record
import capture_session
import game_profiles


class CaptureChecks(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.config = self.root / "config"
        self.config.mkdir()
        (self.config / "game-profiles.json").write_text(json.dumps({"profiles": {
            "steam-3527290": dict(name="PEAK", appClass="steam_app_3527290", isGame=True),
            "native": dict(name="Yerel Oyun", appClass="native-game", isGame=True),
        }}))
        for name, value in (("c_config_dir", self.config), ("config_dir", self.config), ("screenshots_dir", self.root / "Screenshots")):
            patcher = patch.object(capture, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_game_detection_and_safe_names(self):
        self.assertEqual(capture.game_name({"class": "steam_app_3527290"}), "PEAK")
        self.assertEqual(capture.game_name({"class": "native-game"}), "Yerel Oyun")
        self.assertEqual(capture.game_name({"class": "kitty", "title": "PEAK", "fullscreen": 2}), "")
        self.assertEqual(capture.game_name({}), "")
        folder = capture.destination(self.root, '../Tehlike/\\:*?"<>|\n', "screenshot_", ".png")
        self.assertEqual(folder.parent, self.root / "Tehlike")
        self.assertLessEqual(len(capture.clean_name("ü" * 200).encode()), 120)
        self.assertNotEqual(folder, capture.destination(self.root, "Tehlike", "screenshot_", ".png"))

    def test_every_photo_saves_and_copies_without_editor(self):
        source = self.root / "capture.png"
        source.write_bytes(b"captured image")
        for window, folder in (({"class": "steam_app_3527290"}, "PEAK"), ({"class": "app.zen_browser.zen", "fullscreen": 2}, "")):
            with patch.object(capture.subprocess, "run") as run:
                capture.edit_screenshot(source, window)
            args, kwargs = run.call_args
            self.assertEqual(args[0], ["wl-copy", "--type", "image/png"])
            self.assertTrue(kwargs["check"])
            saved = list((capture.screenshots_dir / folder).glob("*.png"))
            self.assertEqual(len(saved), 1)
            self.assertEqual(saved[0].read_bytes(), source.read_bytes())
        with patch.object(capture.subprocess, "run", side_effect=OSError("clipboard unavailable")):
            with self.assertRaises(OSError):
                capture.edit_screenshot(source, {"class": "kitty"})
        self.assertTrue(source.exists())
        self.assertEqual(len(list(capture.screenshots_dir.glob("*.png"))), 2)

    def test_source_matches_exact_window_and_rejects_invalid_region(self):
        source = {"kind": "window", "window": {"address": "0x123", "class": "kitty", "title": "same"}}
        listing = "9[HC>]kitty[HT>]same[HE>]290[HA>]10[HC>]kitty[HT>]same[HE>]291[HA>]"
        self.assertEqual(capture_session.selection(source, listing), "window:10")
        source["window"]["address"] = "0x999"
        with self.assertRaises(ValueError):
            capture_session.selection(source, listing)
        region = dict(kind="region", output="eDP-1", x=0, y=0, width=640, height=360)
        self.assertEqual(capture_session.selection(region, ""), "region:eDP-1@0,0,640,360")
        for value in (0, -1, True, 1.5, "640", 99999):
            with self.assertRaises(ValueError):
                capture_session.validate(region | {"width": value})

    def test_fullscreen_browser_is_not_a_game(self):
        clients = [{"class": "app.zen_browser.zen", "title": "Browser", "pid": 0, "fullscreen": 2}]
        with patch.object(game_profiles.subprocess, "run", return_value=Mock(stdout=json.dumps(clients))):
            self.assertFalse(game_profiles.running_windows()[0]["isGame"])

    def test_live_crop_scales_and_clamps_to_output(self):
        source = dict(kind="region", output="eDP-1", x=100, y=50, width=320, height=240)
        self.assertEqual(capture_session.crop_bounds(source, 3840, 2160, 1920, 1080), (200, 100, 3000, 1580))
        self.assertEqual(capture_session.crop_bounds(source | dict(x=3000, y=3000), 1920, 1080, 1920, 1080), (1918, 1078, 0, 0))

    def test_video_retains_starting_game_after_focus_changes_and_move_failure(self):
        video = self.root / "record/recording.mp4"
        metadata = video.with_suffix(".json")
        recordings = self.root / "Recordings"
        command = record.Command(Namespace(region=None, sound=False, clipboard=False))
        process = Mock()
        process.wait.side_effect = subprocess.TimeoutExpired("recorder", 1)
        with patch.object(record, "recording_path", video), patch.object(record, "recording_notif_path", self.root / "notifid"), \
             patch.object(record, "recordings_dir", recordings), patch.object(record, "game_name", return_value="PEAK") as game, \
             patch.object(record.hypr, "message", return_value=[dict(focused=True, name="TEST", refreshRate=60)]), \
             patch.object(record, "get_config", return_value={}), patch.object(record.subprocess, "Popen", return_value=process), \
             patch.object(record.subprocess, "run"), patch.object(record, "notify", return_value=""), \
             patch.object(record, "close_notification"), patch.object(command, "proc_running", return_value=False):
            command.start()
            self.assertEqual(json.loads(metadata.read_text()), {"game": "PEAK"})
            video.write_bytes(b"video data")
            game.return_value = "Another game"
            with patch.object(record.shutil, "move", side_effect=PermissionError("destination unavailable")):
                with self.assertRaises(PermissionError):
                    command.stop()
            self.assertTrue(video.exists())
            self.assertTrue(metadata.exists())
            command.stop()
            game.assert_called_once_with()
        saved = list(recordings.rglob("*.mp4"))
        self.assertEqual(len(saved), 1)
        self.assertEqual(saved[0].parent, recordings / "PEAK")
        self.assertEqual(saved[0].read_bytes(), b"video data")
        self.assertFalse(metadata.exists())


if __name__ == "__main__":
    unittest.main()
