#!/usr/bin/python3
"""Live check: python3 check_capture_controls.py (records a short desktop video)."""
import json
from pathlib import Path
import subprocess
import time


def call(method, *args):
    value = subprocess.check_output(['qs', 'ipc', '-c', 'caelestia', 'call', 'picker', method, *args], text=True)
    return json.loads(value) if value.strip() else None


def wait(predicate, timeout=20):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        state = call('status')
        assert not state['error'], state['error']
        if predicate(state):
            return state
        time.sleep(.05)
    raise AssertionError(state)


def key(modifier, direction):
    subprocess.run(['wtype', '-M', 'logo', '-M', modifier, '-k', direction, '-m', modifier, '-m', 'logo'], check=True)


def windows():
    return {w['address']: (w['at'], w['size']) for w in json.loads(subprocess.check_output(['hyprctl', 'clients', '-j']))}


def main():
    initial = call('status')
    assert not any(initial[k] for k in ('open', 'recording', 'busy')), 'Close capture / finish your recording first.'
    monitor = next(m for m in json.loads(subprocess.check_output(['hyprctl', 'monitors', '-j'])) if m['focused'])
    source = dict(kind='region', output=monitor['name'], x=100, y=200, width=320, height=240, sound=True)
    parts = Path.home() / ".local/state/caelestia/capture-parts"
    previous_parts = set(parts.glob("*.mp4"))
    owned = False
    try:
        call('record', json.dumps(source)); owned = True
        wait(lambda s: s['recording'] and not s['busy'])
        time.sleep(2)
        call('openFreeze')
        wait(lambda s: s['open'] and s['paused'])
        desktop = windows()
        key('shift', 'Right')
        wait(lambda s: not s['paused'] and s['source']['x'] == 110)
        key('alt', 'Right')
        wait(lambda s: s['source']['width'] == 330)
        assert windows() == desktop, 'Desktop window moved instead of capture selection'
        for _ in range(20):
            call('adjust', '40', '0', 'false')
            time.sleep(.045)
        wait(lambda s: s['source']['x'] == 910)
        time.sleep(1)
        # Same shortcut returns from live movement to paused controls.
        call('openFreeze')
        wait(lambda s: s['open'] and s['paused'])
        call('openFreeze')
        wait(lambda s: not s['open'] and not s['paused'])
        time.sleep(2)
        assert len(set(parts.glob('*.mp4')) - previous_parts) == 1, 'Movement restarted the video stream'
        call('stop'); owned = False
        state = wait(lambda s: not s['busy'] and not s['recording'])
        info = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', state['saved']]))
        assert {s['codec_type'] for s in info['streams']} == {'audio', 'video'}
        assert float(info['format']['duration']) >= 5
        subprocess.run(['ffmpeg', '-v', 'error', '-i', state['saved'], '-f', 'null', '-'], check=True)
        print('PASS: keys, desktop isolation, one continuous stream, pause/resume, sound, video decode:', state['saved'])
    finally:
        if owned:
            call('stop')


if __name__ == '__main__':
    main()
