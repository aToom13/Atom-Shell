#!/usr/bin/env python3
"""Offline QML checks. All power commands are replaced by a recording fixture."""
from collections import Counter
from pathlib import Path
import json
import os
import shutil
import subprocess
import sys
import tempfile

shell = Path(__file__).resolve().parent.parent
cases = [
    dict(name='unarmed', armed=False, expected='normal açılış'),
    dict(name='battery', battery=True, success=True, power=True),
    dict(name='low', percentage=49, success=True, power=True),
    dict(name='battery-low', battery=True, percentage=49, success=True, power=True),
    dict(name='battery-critical', battery=True, percentage=1, success=True, power=True),
    dict(name='battery-zero', battery=True, percentage=0, success=True, power=True),
    dict(name='battery-full', battery=True, percentage=100, success=True, power=True),
    dict(name='prompt-continue', battery=True, percentage=10, policy=True, manual=False, dialogAction='continue', success=True),
    dict(name='prompt-hibernate', battery=True, percentage=10, policy=True, manual=False, dialogAction='hibernate', preview=True, success=True),
    dict(name='reserve-force', battery=True, percentage=5, policy=True, manual=False, dialogAction='hibernate', preview=True, success=True),
    dict(name='charging-reserve', battery=False, percentage=0, policy=True, manual=False, success=True),
    dict(name='invalid-battery', percentage=-1, expected='Geçerli pil'),
    dict(name='invalid-overfull', percentage=101, expected='Geçerli pil'),
    dict(name='unsupported', support='no', expected='desteklemiyor'),
    dict(name='unavailable', support='na', expected='desteklemiyor'),
    dict(name='bad-reply', malformed=True, expected='sorgulanamadı'),
    dict(name='lock-timeout', autoLock=False, expected='Kilit onayı'),
    dict(name='unplug', autoLock=False, unplug=True, success=True, power=True),
    dict(name='invalid-during-lock', autoLock=False, unplug=True, dropCharge=True, expected='Pil koşulları'),
    dict(name='denied', expected='Access denied', power=True),
    dict(name='challenge', support='challenge', expected='Access denied', power=True),
    dict(name='success', success=True, power=True),
    dict(name='resume', success=True, resume=True, power=True),
    dict(name='missing-query', missingQuery=True, expected='zaman aşımına'),
    dict(name='missing-command', missingPower=True, expected='başlatılamadı'),
]
with tempfile.TemporaryDirectory(prefix='hibernation-check-') as directory:
    temporary = Path(directory)
    calls = temporary/'calls'
    fixture = temporary/'power.py'
    fixture.write_text("""from pathlib import Path
import sys,time
with Path(sys.argv[1]).open('a') as f: f.write(sys.argv[2]+'\\n')
time.sleep(.4)
if sys.argv[3] != 'success':
    sys.stderr.write('Access denied\\n')
    sys.exit(1)
""")
    for case in cases:
        reply = 'broken' if case.get('malformed') else json.dumps({'type':'s','data':[case.get('support','yes')]})
        case['query'] = ['/not-installed/hibernation-query'] if case.get('missingQuery') else [sys.executable,'-c',f'import time; time.sleep(.05); print({reply!r})']
        case['command'] = ['/not-installed/hibernation-power'] if case.get('missingPower') else [sys.executable,str(fixture),str(calls),case['name'],'success' if case.get('success') else 'deny']
    qml = '''import QtQuick
import Quickshell
import "modules" as Pilot

ShellRoot {
    id: root
    property var cases: CASES
    property int index: -1
    property var current
    property double started
    property bool autoLock: true
    property int previewActions: 0
    property string previewStage: ""
    property int failures: 0

    function check(ok, message) {
        if (!ok) { failures++; console.error("HIBERNATION_CHECK_FAIL: " + message); }
    }
    function next() {
        index++;
        if (index === cases.length) {
            console.log(failures ? "HIBERNATION_CHECK_FAILED" : "HIBERNATION_CHECK_PASS");
            Qt.quit();
            return;
        }
        current = cases[index];
        controller.closeDialog();
        controller.forcing = false;
        controller.forceRequested = false;
        controller.prompted = false;
        controller.policyEnabled = false;
        controller.armed = current.armed ?? true;
        controller.onBattery = current.battery ?? false;
        controller.batteryAvailable = true;
        controller.measuredBatteryPercentage = current.percentage ?? 90;
        controller.prompted = current.prompted ?? false;
        controller.error = "";
        controller.availability = "na";
        autoLock = current.autoLock ?? true;
        fakeLock.locked = false;
        fakeLock.secure = false;
        controller.checkCommand = current.query;
        controller.powerCommand = current.command;
        controller.policyEnabled = current.policy ?? false;
        started = Date.now();
        if (current.manual !== false) {
            controller.request();
            controller.request();
        }
        poke.restart();
    }
    QtObject {
        id: fakeLock
        property bool locked: false
        property bool secure: false
        signal secureStateChanged()
        onSecureChanged: secureStateChanged()
        onLockedChanged: {
            if (locked && root.autoLock)
                Qt.callLater(() => { if (locked) secure = true; });
        }
    }
    Pilot.HibernationController {
        id: controller
        sessionLock: fakeLock
        batteryAvailable: true
        onBattery: false
        measuredBatteryPercentage: 90
        policyEnabled: false
        onDialogActionPreviewed: stage => {
            root.previewActions++;
            root.previewStage = stage;
        }
    }
    Timer {
        id: poke
        interval: 150
        onTriggered: {
            if (root.current.dialogAction) {
                root.check(controller.dialogVisible, root.current.name + " dialog missing");
                root.check(controller.dialogStage === (root.current.name === "reserve-force" ? "reserve" : "prompt"), root.current.name + " dialog stage mismatch");
                if (root.current.dialogAction === "continue") {
                    controller.dialogContinue();
                } else {
                    controller.dialogPreviewOnly = true;
                    controller.dialogHibernate();
                    root.check(root.previewStage === (root.current.name === "reserve-force" ? "reserve" : "prompt"), root.current.name + " preview action mismatch");
                }
            }
            if (root.current.unplug) {
                controller.onBattery = true;
                if (root.current.dropCharge) controller.measuredBatteryPercentage = -1;
                fakeLock.secure = true;
            } else if (root.current.resume) {
                controller.resumed();
                root.check(controller.busy, "resume released busy before process exit");
                controller.request();
            } else if (root.current.manual !== false) controller.request();
        }
    }
    Timer {
        interval: 25
        running: true
        repeat: true
        onTriggered: {
            if (!root.current || Date.now() - root.started < 650) return;
            if (controller.busy && Date.now() - root.started < 6500) return;
            root.check(!controller.busy, root.current.name + " stuck busy");
            if (root.current.success)
                root.check(!controller.error, root.current.name + ": " + controller.error);
            else
                root.check(controller.error.toLowerCase().includes(root.current.expected.toLowerCase()), root.current.name + ": " + controller.error);
            console.log("CASE_DONE " + root.current.name);
            root.next();
        }
    }
    Component.onCompleted: {
        check(controller.displayPercentageAt(0.1, true) === 5, "display 5% must match real 10%");
        check(controller.displayPercentageAt(0.05, true) === 0, "reserve must display 0% at 5% measured");
        check(controller.displayPercentageAt(0.1, false) === 5, "charging must retain the battery reserve");
        check(controller.displayPercentageAt(0.04, false) === 0, "charging below reserve must display 0%");
        next();
    }
}
'''.replace('CASES',json.dumps(cases,ensure_ascii=False))
    handle, filename = tempfile.mkstemp(prefix='HibernationCheck', suffix='.qml', dir=shell)
    try:
        with os.fdopen(handle,'w') as f:
            f.write(qml)
        platform = 'wayland' if os.environ.get('WAYLAND_DISPLAY') else 'offscreen'
        environment = dict(os.environ, QT_QPA_PLATFORM=platform, QT_QUICK_BACKEND='software')
        expected = Counter()
        if '--menu-only' not in sys.argv:
            result = subprocess.run([shutil.which('quickshell'),'--no-color','-p',filename],
                                    capture_output=True,text=True,env=environment,timeout=55)
            output = result.stdout+result.stderr
            print(output)
            assert result.returncode == 0 and 'HIBERNATION_CHECK_PASS' in output, result.returncode
            assert 'HIBERNATION_CHECK_FAIL' not in output
            actual = Counter(calls.read_text().splitlines()) if calls.exists() else Counter()
            expected = Counter(case['name'] for case in cases if case.get('power'))
            assert actual == expected, (actual,expected)
            print(f'PASS: {len(cases)} cases; exactly {sum(actual.values())} fake power calls; no real power commands')
        menu = '''import QtQuick
import QtQuick.Window
import Quickshell
import "modules" as Pilot
import "modules/session" as Session
import "modules/osd" as Osd
import "components" as Components
import qs.services as QsServices
ShellRoot {
    id: root
    property var button
    property var gif
    property var gifFocus
    property var arrow
    property real savedHeight
    property int failures: 0
    function check(ok, message) {
        if (!ok) { failures++; console.error("MENU_CHECK_FAIL: " + message); }
    }
    function descendants(item) {
        let all = [item];
        for (const child of item.children) all = all.concat(descendants(child));
        return all;
    }
    Component.onCompleted: {
        const component = Qt.createComponent(SHELL_URL);
        check(component.status === Component.Ready, "shell compile: " + component.errorString());
        check(QsServices.BatteryEstimator.displayPercentageAt(0.05, true) === 0, "reserve does not display as 0%");
        check(Math.abs(QsServices.BatteryEstimator.displayPercentageAt(1, true) - 1) < 0.000001, "full battery does not display as 100%");
        check(Math.abs(QsServices.BatteryEstimator.displayPercentageAt(0.1, false) - 0.05 / 0.95) < 0.000001, "charging display should retain reserve");
        check(QsServices.BatteryEstimator.displayPercentageAt(0.04, false) === 0, "charging below reserve must display 0%");
    }
    QtObject {
        id: fakeLock
        property bool locked: false
        property bool secure: false
        signal secureStateChanged()
        onSecureChanged: secureStateChanged()
        onLockedChanged: if (locked) secure = true
    }
    Pilot.HibernationController {
        id: controller
        sessionLock: fakeLock
        batteryAvailable: true
        armed: false
        policyEnabled: false
        onBattery: false
        measuredBatteryPercentage: 90
        checkCommand: QUERY
        powerCommand: POWER
    }
    Components.ScreenState { id: screenState; modelData: Quickshell.screens[0] }
    Window {
        title: "Hibernation arayüz testi (güç işlemi yok)"
        visible: false
        width: 400
        height: 800
        Osd.Wrapper {
            id: osd
            screen: Quickshell.screens[0]
            screenState: screenState
            sidebarOrSessionVisible: true
        }
        Session.Content {
            id: menu
            x: 240
            screenState: screenState
            hibernation: controller
            Component.onCompleted: {
                // The test must never expose real logout, shutdown or reboot actions.
                for (const item of root.descendants(menu)) {
                    if (item.command !== undefined && item.objectName !== "hibernateButton") {
                        item.command = [];
                        item.action = () => {};
                    }
                }
            }
        }
    }
    SequentialAnimation {
        running: true
        PauseAnimation { duration: 1200 }
        ScriptAction { script: {
            root.button = root.descendants(menu).find(item => item.objectName === "hibernateButton");
            root.gif = root.descendants(menu).find(item => item.objectName === "hibernateGif");
            root.gifFocus = root.descendants(menu).find(item => item.objectName === "hibernateGifFocus");
            root.arrow = root.descendants(menu).find(item => item.objectName === "hibernateArrow");
            root.check(!!root.button && !!root.gif, "missing GIF/button");
            root.savedHeight = menu.implicitHeight;
            root.check(root.button.disabled, "unarmed button enabled");
            root.check(root.button.icon === "bedtime"
                && root.button.width === root.button.KeyNavigation.up.width
                && root.button.height === root.button.KeyNavigation.up.height
                && root.button.font.pointSize === root.button.KeyNavigation.up.font.pointSize,
                "hibernate icon/button scale differs from session buttons");
            screenState.osd = true;
            screenState.session = false;
            const normalOsd = osd.shouldBeActive;
            screenState.session = true;
            root.check(!osd.shouldBeActive, "OSD overlaps session menu");
            screenState.session = false;
            root.check(osd.shouldBeActive === normalOsd, "OSD remains suppressed after menu closes");
            screenState.session = true;
            root.button.exec();
            root.gifFocus.forceActiveFocus();
        } }
        PauseAnimation { duration: 1200 }
        ScriptAction { script: {
            root.check(root.button.opacity === 1 && root.gif.visible && root.gif.playing, "focus stopped GIF or hid popup");
            root.check(root.gifFocus.KeyNavigation.left === root.button && root.button.KeyNavigation.right === root.gifFocus,
                "left/right navigation missing");
            root.arrow.clicked();
            root.check(root.button.activeFocus, "arrow did not focus hibernate");
            const buttonPoint = root.button.mapToItem(menu, root.button.width, 0);
            const gifPoint = root.gif.mapToItem(menu, 0, 0);
            root.check(buttonPoint.x < gifPoint.x, "popup is not left of GIF");
            root.check(menu.hibernationPopupRect.width > root.button.width, "popup input region misses gap");
            root.check(root.button.KeyNavigation.up && root.button.KeyNavigation.down, "keyboard neighbors missing");
            root.button.KeyNavigation.up.forceActiveFocus();
        } }
        PauseAnimation { duration: 1200 }
        ScriptAction { script: {
            root.check(root.button.opacity === 0 && root.gif.visible && root.gif.playing, "popup did not close or GIF stopped");
            root.check(menu.hibernationPopupRect.width === 0, "closed popup still takes input");
            root.check(menu.implicitHeight === root.savedHeight, "menu height changed");
            controller.armed = true;
            controller.availability = "yes";
        } }
        PauseAnimation { duration: 50 }
        ScriptAction { script: {
            root.check(!root.button.disabled, "ready button disabled");
            root.button.exec();
            root.button.exec();
        } }
        PauseAnimation { duration: 1000 }
        ScriptAction { script: {
            root.check(!controller.busy && controller.error.includes("Access denied"), "request error missing");
            console.log(root.failures ? "MENU_CHECK_FAILED" : "MENU_CHECK_PASS");
            Qt.quit();
        } }
    }
}
'''.replace('QUERY',json.dumps(next(case['query'] for case in cases if case['name'] == 'denied'))).replace('POWER',json.dumps([sys.executable,str(fixture),str(calls),'menu','deny'])).replace('SHELL_URL',json.dumps((shell/'shell.qml').as_uri()))
        Path(filename).write_text(menu)
        environment = dict(os.environ, QT_QPA_PLATFORM='wayland', QT_QUICK_BACKEND='software')
        result = subprocess.run([shutil.which('quickshell'),'--no-color','-p',filename],
                                capture_output=True,text=True,env=environment,timeout=15)
        output = result.stdout+result.stderr
        print(output)
        assert result.returncode == 0 and 'MENU_CHECK_PASS' in output
        assert 'MENU_CHECK_FAIL' not in output
        expected['menu'] = 1
        assert Counter(calls.read_text().splitlines()) == expected
        print('PASS: left popup, continuous GIF, icon scale, OSD exclusion/recovery, focus, input region, navigation, disabled state, fixed height, one fake request')
    finally:
        Path(filename).unlink(missing_ok=True)
