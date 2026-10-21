#!/usr/bin/python3 -I
"""Fixed, reversible Ultra power controls. Install a root-owned copy in libexec."""
import fcntl
import json
import os
from pathlib import Path
import sys

STATE = Path('/run/caelestia-ultra-power.json')


def read_value(path):
    return int(Path(path).read_text().strip())


def write_value(path, value):
    Path(path).write_text(str(int(value)))
    if read_value(path) != value:
        raise RuntimeError(f'Hardware rejected {path} = {value}')


def save(state):
    temporary = STATE.with_suffix('.tmp')
    with temporary.open('w') as stream:
        os.chmod(temporary, 0o600)
        json.dump(state, stream)
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(STATE)


def targets():
    result = {}

    def add(path, value, kind):
        if path.exists():
            result[str(path)] = dict(before=read_value(path), applied=value, kind=kind)

    for zone in Path('/sys/class/powercap').glob('intel-rapl*'):
        if 'mmio' in zone.name:
            continue  # Firmware rewrites MMIO limits; use the independent MSR package limits.
        name = zone / 'name'
        if name.exists() and name.read_text().strip().startswith('package-'):
            for index, limit in ((0, 6_000_000), (1, 8_000_000)):
                path = zone / f'constraint_{index}_power_limit_uw'
                if path.exists():
                    add(path, min(read_value(path), limit), 'cpu')
    if not result:
        path = Path('/sys/devices/system/cpu/intel_pstate/max_perf_pct')
        if path.exists():
            add(path, min(read_value(path), 25), 'cpu')
    if not result:
        raise RuntimeError('No supported CPU power limit found')
    for card in Path('/sys/class/drm').glob('card[0-9]*'):
        for name in ('gt_boost_freq_mhz', 'gt_max_freq_mhz'):
            path = card / name
            if path.exists():
                add(path, min(read_value(path), 600), 'gpu')
    for device in Path('/sys/bus/usb/devices').iterdir():
        path = device / 'power/autosuspend_delay_ms'
        control = device / 'power/control'
        if not path.exists() or not control.exists() or control.read_text().strip() != 'auto':
            continue
        interfaces = list(device.glob(f'{device.name}:*/bInterfaceClass'))
        classes = {p.read_text().strip() for p in interfaces}
        adb = any((p.parent / 'bInterfaceSubClass').read_text().strip() == '42' for p in interfaces)
        if classes & {'01', '03', '06'} or adb:
            continue  # Keep audio, input devices and phone transports untouched.
        value = read_value(path)
        if value >= 0:
            add(path, min(value, 10_000), 'usb')
    for device in Path('/sys/class/backlight').iterdir():
        maximum = read_value(device / 'max_brightness')
        add(device / 'brightness', min(read_value(device / 'brightness'), max(1, maximum // 10)), 'brightness')
    for device in Path('/sys/class/leds').glob('*kbd_backlight'):
        add(device / 'brightness', 0, 'keyboard')
    return result


def undim(state):
    dim = state.get('dim')
    if not dim:
        return
    if Path(dim['path']).exists() and read_value(dim['path']) == dim['applied']:
        write_value(dim['path'], dim['before'])
    state.pop('dim', None)
    save(state)


def restore(state):
    errors = []
    try:
        undim(state)
    except Exception as error:
        errors.append(str(error))
    # Reverse order also raises the GPU ceiling before restoring its boost clock.
    for path, item in reversed(list(state.get('values', {}).items())):
        try:
            if Path(path).exists() and read_value(path) == item['applied']:
                write_value(path, item['before'])
        except Exception as error:
            errors.append(str(error))
    if errors:
        raise RuntimeError('; '.join(errors))
    state['active'] = False
    save(state)


def execute(action):
    if action not in ('enable', 'disable', 'reapply', 'status', 'dim', 'undim'):
        raise ValueError('Unknown action')
    state = json.loads(STATE.read_text()) if STATE.exists() else dict(active=False)
    if action == 'enable' and not state['active']:
        state = dict(active=True, values=targets())
        save(state)  # Journal before the first hardware write.
        try:
            for path, item in state['values'].items():
                write_value(path, item['applied'])
        except Exception as failure:
            try:
                restore(state)
            except Exception as rollback:
                raise RuntimeError(f'{failure}; restore failed: {rollback}') from failure
            raise
    elif action == 'disable' and state['active']:
        restore(state)
    elif action == 'reapply' and state['active']:
        for path, item in state['values'].items():
            if item['kind'] in ('cpu', 'gpu', 'usb') and Path(path).exists():
                write_value(path, item['applied'])
    elif action == 'dim' and state['active'] and not state.get('dim'):
        for path, item in state['values'].items():
            if item['kind'] == 'brightness':
                maximum = read_value(Path(path).parent / 'max_brightness')
                state['dim'] = dict(path=path, before=read_value(path), applied=min(read_value(path), max(1, maximum // 20)))
                save(state)
                write_value(path, state['dim']['applied'])
                break
    elif action == 'undim':
        undim(state)
    current = {path: read_value(path) for path in state.get('values', {}) if Path(path).exists()}
    issues = [path for path, item in state.get('values', {}).items()
              if state['active'] and item['kind'] in ('cpu', 'gpu', 'usb')
              and path in current and current[path] != item['applied']]
    return dict(ok=True, active=state['active'], dimmed=bool(state.get('dim')), values=state.get('values', {}), current=current, issues=issues)


def main():
    if os.geteuid() != 0 or len(sys.argv) != 2:
        raise SystemExit('Run the installed helper through sudo with exactly one action')
    with STATE.with_suffix('.lock').open('w') as lock:
        os.chmod(lock.name, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            result = execute(sys.argv[1])
        except Exception as error:
            result = dict(ok=False, error=str(error))
        print(json.dumps(result))
        return 0 if result['ok'] else 1


if __name__ == '__main__':
    sys.exit(main())
