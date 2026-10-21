#!/usr/bin/python3
"""Run: python3 check_game_mode.py — isolated, no compositor mutations."""
import copy
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import game_mode as mode
import game_profiles as profiles
import game_launch as launch
import game_capture as capture


class GameModeChecks(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        self.runtime = mode.targets(mode.DEFAULTS | dict(allowTearing=True, hideBorders=True, vrr="always"))
        self.runtime.update({"decoration:active_opacity": 0.83, "decoration:inactive_opacity": 0.67,
                             "general:gaps_in": "3 5 7 9", "general:gaps_out": "11 13 15 17",
                             "decoration:rounding": 19, "animations:enabled": True})
        self.power = "power-saver"
        self.rules = None
        mocks = [patch.object(mode, "CONFIG", root / "game-mode.json"),
                 patch.object(mode, "STATE", root / "game-mode-session.json"),
                 patch.object(profiles, "CONFIG_DIR", root),
                 patch.object(profiles, "PROFILE_FILE", root / "game-profiles.json"),
                 patch.object(profiles, "STATE_DIR", root),
                 patch.object(mode, "option", side_effect=lambda key: self.runtime[key]),
                 patch.object(mode, "apply", side_effect=self.runtime.update),
                 patch.object(mode, "profile", side_effect=lambda: self.power),
                 patch.object(mode, "set_profile", side_effect=lambda value: setattr(self, "power", value)),
                 patch.object(mode, "window_rule", side_effect=lambda prefs=None: setattr(self, "rules", prefs)),
                 patch.object(profiles, "running_windows", return_value=[]),
                 patch.object(profiles, "capabilities", return_value=dict(gamescope=True, frameGeneration=False, maxMultiplier=3)),
                 patch.dict(os.environ, HYPRLAND_INSTANCE_SIGNATURE="test-compositor")]
        for mock in mocks:
            mock.start()
            self.addCleanup(mock.stop)

    def test_exact_restore_and_reapply_preserves_snapshot(self):
        before = dict(self.runtime)
        active = mode.execute("enable", "true")
        self.assertTrue(active["ok"], active)
        original = copy.deepcopy(active["session"])
        self.runtime["animations:enabled"] = True
        self.assertTrue(mode.execute("reapply")["ok"])
        self.assertEqual(mode.read(mode.STATE, {}), original)
        result = mode.execute("disable")
        self.assertTrue(result["ok"], result)
        self.assertFalse(result["session"]["active"])
        self.assertEqual(self.runtime, before)
        self.assertEqual(self.power, "power-saver")
        self.assertTrue(result["session"]["previousDnd"])
        self.assertIsNone(self.rules)

    def test_partial_apply_rolls_back(self):
        before = dict(self.runtime)
        calls = 0
        def fail_once(values):
            nonlocal calls
            calls += 1
            self.runtime.update(values)
            if calls == 1:
                raise RuntimeError("simulated partial apply")
        with patch.object(mode, "apply", side_effect=fail_once):
            result = mode.execute("enable", "false")
        self.assertFalse(result["ok"])
        self.assertFalse(result["session"]["active"])
        self.assertEqual(self.runtime, before)
        self.assertEqual(self.power, "power-saver")

    def test_failed_restore_keeps_journal_for_retry(self):
        before = dict(self.runtime)
        self.assertTrue(mode.execute("enable", "false")["ok"])
        with patch.object(mode, "apply", side_effect=RuntimeError("compositor unavailable")):
            result = mode.execute("disable")
        self.assertFalse(result["ok"])
        self.assertTrue(result["session"]["active"])
        self.assertEqual(result["session"]["previousOptions"]["general:gaps_in"], before["general:gaps_in"])
        self.assertTrue(mode.execute("disable")["ok"])
        self.assertEqual(self.runtime, before)

    def test_status_checks_hyprland_even_without_power_change(self):
        mode.execute("configure", json.dumps({"powerProfile": "keep"}))
        mode.execute("enable", "false")
        self.runtime["animations:enabled"] = True
        with patch.object(mode, "profile", side_effect=RuntimeError("no power service")):
            result = mode.execute("status")
        self.assertFalse(result["ok"])
        self.assertIn("animations:enabled", result["error"])

    def test_profile_settings_are_isolated(self):
        key = "app-1234567890abcdef"
        profiles.save(dict(selected=key, profiles={key: dict(key=key, name="Game", render=dict(profiles.RENDER_DEFAULTS))}))
        result = mode.execute("configure", json.dumps({"vrr": "fullscreen", "opaqueShell": False}))
        self.assertTrue(result["ok"])
        self.assertEqual(result["profileName"], "Game")
        self.assertFalse(mode.CONFIG.exists())
        profiles.execute("select", "")
        self.assertEqual(mode.execute("status")["settings"]["vrr"], "keep")
        profiles.execute("select", key)
        self.assertEqual(mode.execute("status")["settings"]["vrr"], "fullscreen")
        self.assertFalse(mode.execute("status")["settings"]["opaqueShell"])

    def test_trust_boundary_validation(self):
        for invalid in ({"inhibitIdle": "false"}, {"vrr": "typo"}, {"powerProfile": "turbo"}, {"unknown": True}):
            with self.assertRaises(ValueError):
                mode.settings(invalid)
        for invalid in ({"fps": -1}, {"fps": True}, {"resolution": "$(touch /tmp/x)"}, {"frameGeneration": 5}):
            with self.assertRaises(ValueError):
                profiles.rendering(invalid)
        with self.assertRaises(ValueError):
            profiles.launch_options("../../other")

    def test_scaling_argv_and_missing_dependencies(self):
        profile = {"render": profiles.RENDER_DEFAULTS | dict(scaler="fsr", fps=60)}
        caps = dict(gamescope=True, frameGeneration=False)
        original = ["/game path/game", "title;$(touch /tmp/never)"]
        argv, env = launch.command(profile, original, caps, "1920x1080")
        self.assertEqual(argv[-2:], original)
        self.assertEqual(argv[argv.index("--") + 1], "/usr/bin/env")
        self.assertIn("fsr", argv)
        self.assertIn("1280", argv)
        self.assertIn("1920", argv)
        self.assertEqual(env["DISABLE_LSFGVK"], "1")
        with self.assertRaises(ValueError):
            launch.command(profile, original, caps | dict(gamescope=False), "1920x1080")
        profile["render"]["frameGeneration"] = 2
        with self.assertRaises(ValueError):
            launch.command(profile, original, caps, "1920x1080")

    def test_kettle_frame_generation_and_compositor_isolation(self):
        profile = {"key": "test-cube", "render": profiles.RENDER_DEFAULTS | dict(frameGeneration=2)}
        caps = dict(gamescope=True, frameGeneration=True, frameGenerationEngine="kettle")
        with patch.dict(os.environ, DISABLE_KETTLE_FG="1"):
            argv, env = launch.command(profile, ["game"], caps, "1920x1080")
        self.assertEqual(argv, ["game"])
        self.assertEqual(env["KETTLE_FG_CONFIG"], str(profiles.framegen_config_path("test-cube")))
        self.assertNotIn("DISABLE_KETTLE_FG", env)
        self.assertEqual(env["DISABLE_LSFGVK"], "1")
        profile["render"]["scaler"] = "fsr"
        argv, env = launch.command(profile, ["game"], caps, "1920x1080")
        self.assertEqual(env["DISABLE_KETTLE_FG"], "1")
        self.assertIn("KETTLE_FG_CONFIG=" + str(profiles.framegen_config_path("test-cube")), argv)
        self.assertNotIn("DISABLE_KETTLE_FG=1", argv)
        profile["render"]["frameGeneration"] = 4
        with self.assertRaises(ValueError):
            launch.command(profile, ["game"], caps, "1920x1080")

    def test_opengl_capture_injects_only_into_sdl_compositor(self):
        profile = {"key": "test-cube", "render": profiles.RENDER_DEFAULTS | dict(frameGeneration=2)}
        caps = dict(gamescope=True, frameGeneration=True, frameGenerationEngine="kettle")
        original = ["/game path/game", "literal;$(text)"]
        with patch.dict(os.environ, PROTON_USE_WINED3D="1", DISABLE_KETTLE_FG="1"):
            argv, env = launch.command(profile, original, caps, "1920x1080")
        self.assertEqual(argv[0], "gamescope")
        self.assertEqual(argv[argv.index("--backend") + 1], "sdl")
        self.assertEqual(argv[-2:], original)
        self.assertIn("DISABLE_KETTLE_FG=1", argv)
        self.assertNotIn("DISABLE_KETTLE_FG", env)
        self.assertEqual(env["KETTLE_FG_CONFIG"], str(profiles.framegen_config_path("test-cube")))
        profile["render"]["frameGenerationSource"] = "compositor"
        with self.assertRaises(ValueError):
            launch.command(profile, original, caps | dict(gamescope=False), "1920x1080")
        with self.assertRaises(ValueError):
            profiles.rendering(dict(frameGenerationSource="invalid"))

    def test_live_frame_generation_preferences_and_latency_guard(self):
        profile = dict(key="test-cube", name="Test", render=profiles.RENDER_DEFAULTS | dict(frameGeneration=2))
        profiles.save(dict(selected="test-cube", profiles={"test-cube": profile}))
        profiles.execute("configure", '{"frameGeneration": 1}')
        text = profiles.framegen_config_path("test-cube").read_text()
        self.assertIn("multiplier = 1\n", text)
        self.assertIn("min_fps = 25\n", text)
        self.assertIn("latency = normal\n", text)
        self.assertIn("preserve_images = false\n", text)
        caps = dict(gamescope=True, frameGeneration=True, frameGenerationEngine="kettle")
        with patch.dict(os.environ, KETTLE_FG_MULTIPLIER="3", KETTLE_FG_MIN_FPS="0", KETTLE_FG_LATENCY="normal"):
            _, env = launch.command(profile, ["game"], caps, "1920x1080")
        self.assertNotIn("KETTLE_FG_MULTIPLIER", env)
        self.assertNotIn("KETTLE_FG_MIN_FPS", env)
        self.assertNotIn("KETTLE_FG_LATENCY", env)
        with self.assertRaises(ValueError):
            profiles.rendering(dict(frameGenerationMinFps=-1))
        with self.assertRaises(ValueError):
            profiles.rendering(dict(frameGenerationLatency="typo"))
        profiles.execute("configure", '{"frameGeneration": 0}')
        text = profiles.framegen_config_path("test-cube").read_text()
        self.assertIn("multiplier = auto\n", text)
        self.assertTrue(profiles.frame_generation_active(0))
        _, env = launch.command(profile, ["game"], caps, "1920x1080")
        self.assertIn("KETTLE_FG_CONFIG", env)
        argv, env = capture.command(profile, [dict(key="test-cube", address="0x123abc", monitor=0)], caps, [dict(id=0, refreshRate=60)])
        self.assertEqual(argv[0], "qs")
        self.assertIn("KETTLE_FG_CONFIG", env)
        profiles.execute("configure", '{"frameGenerationLatency": "low"}')
        self.assertIn("latency = low\n", profiles.framegen_config_path("test-cube").read_text())

    def test_capture_uses_running_window_without_game_or_launcher_changes(self):
        key = "app-1234567890abcdef"
        profile = dict(key=key, render=profiles.RENDER_DEFAULTS | dict(frameGeneration=2))
        window = dict(key=key, address="0x123abc", name="literal;$(text)", monitor=2)
        caps = dict(frameGeneration=True, frameGenerationEngine="kettle", gamescope=False)
        with patch.dict(os.environ, KETTLE_FG_MULTIPLIER="3", KETTLE_FG_DUMP="/old/debug", DISABLE_KETTLE_FG="1"):
            argv, env = capture.command(profile, [window], caps, [dict(id=0, refreshRate=144), dict(id=2, refreshRate=60.033)])
        self.assertEqual(argv[0], "qs")
        self.assertNotIn(window["name"], argv)
        self.assertNotIn("gamescope", argv)
        self.assertEqual(env["CAELESTIA_CAPTURE_ADDRESS"], window["address"])
        self.assertEqual(env["QSG_RHI_BACKEND"], "vulkan")
        self.assertEqual(env["KETTLE_FG_REFRESH"], "60.033")
        self.assertEqual(env["KETTLE_FG_CONFIG"], str(profiles.framegen_config_path(key)))
        self.assertNotIn("KETTLE_FG_MULTIPLIER", env)
        self.assertNotIn("KETTLE_FG_DUMP", env)
        self.assertNotIn("DISABLE_KETTLE_FG", env)
        with self.assertRaises(ValueError):
            capture.command(profile, [], caps)
        with self.assertRaises(ValueError):
            capture.command(profile, [window | dict(address="$(command)")], caps)
        with self.assertRaises(ValueError):
            capture.command(profile | dict(render=dict(frameGeneration=1)), [window], caps)
        with self.assertRaises(ValueError):
            capture.command(profile, [window], caps | dict(frameGenerationEngine="lsfg"))
        with self.assertRaises(ValueError):
            capture.command(profile, [window], caps, [dict(id=2, refreshRate=float('nan'))])

    def test_hud_preferences_validate_and_persist_per_application(self):
        old_render = {key: value for key, value in profiles.RENDER_DEFAULTS.items() if not key.startswith("hud")}
        profile = dict(key="test-cube", name="Test", render=old_render)
        profiles.save(dict(selected="test-cube", profiles={"test-cube": profile}))
        status = profiles.execute("status")["profile"]["render"]
        self.assertTrue(status["hudFps"])
        self.assertEqual(status["hudPosition"], "top-right")
        update = dict(hudCpu=True, hudRam=True, hudTemperature=True, hudPosition="bottom-left", hudFontSize=22, hudMargin=40)
        profiles.execute("configure", json.dumps(update))
        stored = profiles.selected()["render"]
        for key, value in update.items():
            self.assertEqual(stored[key], value)
        for invalid in (dict(hudPosition="center"), dict(hudFontSize=11), dict(hudMargin=201), dict(hudCpu="true"), dict(hudMargin=True)):
            with self.assertRaises(ValueError):
                profiles.rendering(invalid)

    def test_frame_generation_stays_on_when_source_fps_falls(self):
        qml = Path(__file__).resolve().parents[1].joinpath("services/GameProfiles.qml").read_text()
        report = qml[qml.index("    function reportGameFps("):qml.index("    function testCube(")]
        report = report.replace("fps: real", "fps").replace("): void", ")")
        start = qml[qml.index("    function startCapture("):qml.index("    function stopCapture(")].replace("): void", ")")
        checks = r'''
const assert = require("node:assert/strict");
const vm = require("node:vm");
function qsTr(text) { return { arg(value) { return qsTr(text.replace(/%\d/, String(value))); }, toString() { return text; } }; }
const root = {captureRunning: false, selected: "game", stopCapture() { this.captureRunning = false; }};
const context = {root, qsTr, Toaster: {toast() {}}, Toast: {Warning: 1}};
vm.runInNewContext(REPORT, context);
context.reportGameFps(60);
assert.equal(root.lastGameFps, 60);
assert.equal(root.lastGameFpsProfile, "game");
Object.assign(root, {captureRunning: true, captureInfo: {active: true, ready: true}, captureSuspended: false,
    captureBaselineFps: 60, captureStartedAt: Date.now() - 5000, captureSlowSamples: 0});
context.reportGameFps(30);
context.reportGameFps(30);
assert.equal(root.captureRunning, true);
context.reportGameFps(59);
assert.equal(root.captureSlowSamples, 0);
context.reportGameFps(30);
root.captureInfo.active = false;
context.reportGameFps(0);
assert.equal(root.captureSlowSamples, 0);
assert.equal(root.captureRunning, true);
root.captureInfo.active = true;
context.reportGameFps(30); context.reportGameFps(30); context.reportGameFps(30);
assert.equal(root.captureRunning, true);
assert.match(String(root.captureWarning), /60.*30/);
const preflight = {profile: {}, busy: false, testRunning: false, captureRunning: false, error: "",
    selected: "game", lastGameFpsProfile: "game", lastGameFpsAt: Date.now(), lastGameFps: 60,
    qsTr, Hypr: {focusedMonitor: {lastIpcObject: {refreshRate: 60}}},
    capturer: {exec() { throw Error("Already filling the display; capture should not start"); }}};
vm.runInNewContext(START, preflight);
preflight.startCapture();
assert.match(String(preflight.error), /60 FPS.*60 Hz/);
'''.replace("REPORT", json.dumps(report)).replace("START", json.dumps(start))
        subprocess.run(["node", "-e", checks], check=True, capture_output=True, text=True)


    def test_qml_game_mode_wiring_covers_blur_background_dnd_and_idle(self):
        root = Path(__file__).resolve().parents[1]

        def read(relative):
            return (root / relative).read_text()

        service = read("services/GameMode.qml")
        for name, setting in (("disableBlur", "disableShellBlur"), ("pauseWallpaper", "pauseWallpaper"),
                              ("pauseVisualisers", "pauseVisualisers"), ("pauseMediaArtwork", "pauseMediaArtwork"),
                              ("pauseMediaShapes", "pauseMediaShapes"), ("hideDesktopClock", "hideDesktopClock"),
                              ("muteNotifications", "muteNotifications"), ("inhibitIdle", "inhibitIdle"),
                              ("inhibitSleep", "inhibitSleep")):
            condition = "enabled" if name in ("muteNotifications", "inhibitIdle", "inhibitSleep") else r"!!session\.active"
            self.assertRegex(service, rf"readonly property bool {name}: {condition} && !!activeSettings\.{setting}")

        integrations = {
            "modules/bar/components/workspaces/Workspaces.qml": "GameMode.disableBlur",
            "modules/nexus/common/AnimatedLogo.qml": "GameMode.disableBlur",
            "services/Colours.qml": "GameMode.disableBlur",
            "modules/background/DesktopClock.qml": "GameMode.disableBlur",
            "modules/background/Wallpaper.qml": "GameMode.pauseWallpaper",
            "modules/background/Visualiser.qml": "GameMode.pauseVisualisers",
            "components/widgets/CoverArt.qml": "GameMode.pauseMediaArtwork",
            "modules/dashboard/media/BackgroundShapes.qml": "GameMode.pauseMediaShapes",
            "modules/background/Background.qml": "GameMode.hideDesktopClock",
            "services/Notifs.qml": "GameMode.muteNotifications",
            "services/IdleInhibitor.qml": "GameMode.inhibitIdle",
        }
        for path, needle in integrations.items():
            self.assertIn(needle, read(path), path)
        self.assertIn("inhibitor.running = true", service)
        self.assertIn("stopInhibitor()", service)

        page = read("modules/nexus/pages/services/GameModePage.qml")
        for option in ("disableBlur", "disableShellBlur", "pauseWallpaper", "pauseVisualisers",
                       "pauseMediaArtwork", "pauseMediaShapes", "muteNotifications", "inhibitIdle", "inhibitSleep"):
            self.assertIn(f'["{option}"', page)

        panel = read("modules/utilities/cards/GameModePanel.qml")
        self.assertIn('multiplier = "auto" if prefs["frameGeneration"] == 0', read("utils/game_profiles.py"))
        self.assertIn("GameProfiles.windows.filter", panel)
        self.assertNotIn("GameProfiles.profiles.filter", panel)
        self.assertIn("model: [1, 0, 2, 3]", panel)
        self.assertIn("artifactHint", panel)
        capture_shell = read("utils/capture/shell.qml")
        self.assertIn("readonly property bool overlayVisible: active && !moving && !appPopupVisible", capture_shell)
        self.assertIn("visible: root.overlayVisible", capture_shell)
        self.assertIn("moveTimer.restart()", capture_shell)
        self.assertIn("function onRawEvent(event: HyprlandEvent)", capture_shell)
        self.assertIn("Hyprland.refreshToplevels()", capture_shell)
        self.assertIn("function checkGeometry(): void", capture_shell)
        self.assertIn("interval: 66", capture_shell)
        self.assertIn("state.osd", read("services/GameProfiles.qml"))
        profiles_qml = read("services/GameProfiles.qml")
        self.assertIn("captureStatsTimedOut", profiles_qml)
        self.assertIn("Canlı yakalama başlatılamadı", profiles_qml)
        self.assertIn("İstatistik bekleniyor", panel)


if __name__ == "__main__":
    unittest.main()
