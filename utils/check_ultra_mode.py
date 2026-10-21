#!/usr/bin/python3
"""Run with python3 check_ultra_mode.py; uses temporary files, never real hardware."""
import importlib.util
import json
from pathlib import Path
import tempfile


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def check_hardware():
    module = load('ultra_power')
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        module.STATE = root / 'state.json'
        before = {'cpu': 64_000_000, 'gpu': 1350, 'usb': 300_000, 'brightness': 15, 'keyboard': 2}
        desired = {'cpu': 6_000_000, 'gpu': 600, 'usb': 10_000, 'brightness': 10, 'keyboard': 0}
        for name, value in before.items():
            (root / name).mkdir()
            (root / name / 'value').write_text(str(value))
        (root / 'brightness/max_brightness').write_text('100')
        module.targets = lambda: {str(root / name / 'value'): dict(before=value, applied=desired[name], kind=name)
                                  for name, value in before.items()}
        def values():
            return {name: module.read_value(root / name / 'value') for name in before}
        module.execute('enable')
        assert values() == desired
        # Re-enabling and reapplying must not replace the original restore snapshot.
        module.execute('enable')
        (root / 'cpu/value').write_text('64000000')
        assert module.execute('status')['issues']
        module.execute('reapply')
        assert values() == desired
        module.execute('dim')
        assert values()['brightness'] == 5
        module.execute('undim')
        assert values()['brightness'] == 10
        module.execute('dim')
        module.execute('disable')
        assert values() == before, 'exit while dimmed must restore original brightness'
        module.execute('enable')
        (root / 'brightness/value').write_text('22')
        (root / 'keyboard/value').write_text('1')
        module.execute('disable')
        assert values() == before | {'brightness': 22, 'keyboard': 1}, 'preserve manual changes'
        # A hardware failure after earlier successful writes must roll them back.
        for name, value in before.items():
            (root / name / 'value').write_text(str(value))
        original_write = module.write_value
        def fail_once(path, value):
            if str(path).endswith('/usb/value') and value == desired['usb']:
                raise OSError('injected device failure')
            original_write(path, value)
        module.write_value = fail_once
        try:
            module.execute('enable')
        except OSError:
            pass
        else:
            raise AssertionError('failure was swallowed')
        assert values() == before
        assert not json.loads(module.STATE.read_text())['active']
        try:
            module.execute('arbitrary-command')
        except ValueError:
            pass
        else:
            raise AssertionError('unknown command accepted')


def check_user_session():
    import sys
    sys.path.insert(0, str(Path(__file__).parent))
    module = load('game_mode')
    events = []
    quotas = {'arch-update.service': 2**64 - 1, 'psd-resync.service': 100_000}
    module.quota = lambda unit: quotas[unit]
    def set_quota(unit, value):
        events.append(('quota', unit, value)); quotas[unit] = value
    module.set_quota = set_quota
    module.hardware = lambda action: events.append(('hardware', action))
    module.write = lambda *args: None
    module.run = lambda *args: 'b false' if args[0] == 'busctl' else ''
    session = {'ultra': {'quotas': dict(quotas), 'bluetoothWasOn': True, 'bluetoothChanged': False}}
    module.enable_ultra(session)
    assert quotas == {'arch-update.service': 250_000, 'psd-resync.service': 100_000}
    assert session['ultra']['bluetoothChanged']
    module.restore_ultra(session)
    assert quotas == {'arch-update.service': 2**64 - 1, 'psd-resync.service': 100_000}
    # User-changed quotas are not overwritten on exit.
    module.enable_ultra(session)
    quotas['arch-update.service'] = 500_000
    module.restore_ultra(session)
    assert quotas['arch-update.service'] == 500_000
    assert not module.ULTRA['inhibitIdle'] and not module.ULTRA['inhibitSleep']
    assert module.ULTRA['powerProfile'] == 'power-saver'
    assert not module.ULTRA['muteNotifications']


def check_quota_commands():
    module = load('game_mode')
    calls = []
    unit = module.BACKGROUND_UNITS[0]
    module.run = lambda *args: calls.append(args)
    for value, assignment in [(250_000, 'CPUQuota=25%'), (2**64 - 1, 'CPUQuota=')]:
        module.quota = lambda _: value
        module.set_quota(unit, value)
        assert calls[-1] == ('systemctl', '--user', 'set-property', '--runtime', unit, assignment)
    try:
        module.set_quota('unrelated.service', 250_000)
    except ValueError:
        pass
    else:
        raise AssertionError('unexpected service accepted')


if __name__ == '__main__':
    check_hardware()
    check_user_session()
    check_quota_commands()
    print('PASS: hardware limits, dimming, restore, manual overrides, failure rollback, command validation, background quotas')
