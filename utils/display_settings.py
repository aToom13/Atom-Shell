#!/usr/bin/env python3
"""Hyprland display preview; independent systemd guard restores unconfirmed changes."""
import fcntl
import json
import math
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time
import uuid

RUNTIME = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')) / 'atomshell-display'
CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'caelestia/monitor-overrides.tsv'
TIMEOUT = 15


def run(*args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=8, check=True)
    return result.stdout.strip()


def monitors():
    return json.loads(run('hyprctl', 'monitors', 'all', '-j'))


def atomic(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def status():
    try:
        return json.loads((RUNTIME / 'status.json').read_text())
    except FileNotFoundError:
        return {'phase': 'idle'}


def publish(value):
    atomic(RUNTIME / 'status.json', json.dumps(value, ensure_ascii=False))


def snapshot(items):
    return [dict(name=m['name'], mode=f"{m['width']}x{m['height']}@{m['refreshRate']:.3f}" if not m.get('disabled') else 'preferred',
                 x=m.get('x', 0), y=m.get('y', 0), scale=m.get('scale', 1) or 1,
                 transform=m.get('transform', 0), enabled=not m.get('disabled', False),
                 mirror='' if m.get('mirrorOf', 'none') in ('none', '') else m['mirrorOf']) for m in items]


def validate(items, connected):
    known = {m['name']: m for m in connected}
    if not isinstance(items, list) or not items or len(items) != len(known):
        raise ValueError('Ekran listesi değişti. Yenileyip tekrar deneyin.')
    names = [m.get('name') for m in items if isinstance(m, dict)]
    if len(names) != len(items) or len(set(names)) != len(names) or set(names) != set(known):
        raise ValueError('Geçersiz veya bağlantısı kesilmiş ekran.')
    for item in items:
        name = item['name']
        if not re.fullmatch(r'[A-Za-z0-9_.:-]{1,128}', name):
            raise ValueError('Geçersiz ekran adı.')
        if type(item.get('enabled')) is not bool or type(item.get('transform')) is not int or not 0 <= item['transform'] <= 7:
            raise ValueError('Geçersiz ekran durumu veya döndürme.')
        scale = item.get('scale')
        if type(scale) not in (int, float) or not math.isfinite(scale) or not 0.5 <= scale <= 3:
            raise ValueError('Ölçek 0,5 ile 3 arasında olmalı.')
        if any(type(item.get(axis)) is not int or abs(item[axis]) > 32768 for axis in ('x', 'y')):
            raise ValueError('Geçersiz ekran konumu.')
        mode = item.get('mode', '')
        if not isinstance(mode, str) or not re.fullmatch(r'\d{2,5}x\d{2,5}@\d{1,4}(?:\.\d{1,6})?', mode):
            raise ValueError('Geçersiz çözünürlük veya yenileme hızı.')
        if item['enabled']:
            w, h, hz = re.split('[x@]', mode)
            available = known[name].get('availableModes', [])
            if available and not any(v.startswith(f'{w}x{h}@') and abs(float(v.split('@')[1].removesuffix('Hz')) - float(hz)) < .06 for v in available):
                raise ValueError(f'{name}: Seçilen ekran modu desteklenmiyor.')
        mirror = item.get('mirror')
        if not isinstance(mirror, str) or mirror and (mirror not in known or mirror == name):
            raise ValueError('Geçersiz yansıtma hedefi.')
    active = {m['name']: m for m in items if m['enabled']}
    if not active or not any(not m['mirror'] for m in active.values()):
        raise ValueError('En az bir bağımsız ekran açık kalmalı.')
    if any(m['mirror'] and (m['mirror'] not in active or active[m['mirror']]['mirror']) for m in active.values()):
        raise ValueError('Yansıtma hedefi açık ve bağımsız bir ekran olmalı.')
    return items


def apply(items):
    # Enable sources first, mirrors next, disable unused outputs last.
    ordered = sorted(items, key=lambda m: (not m['enabled'], bool(m['mirror'])))
    statements = []
    for m in ordered:
        values = dict(output=m['name'], mode=m['mode'], position=f"{m['x']}x{m['y']}",
                      scale=m['scale'], transform=m['transform'], disabled=not m['enabled'], mirror=m['mirror'])
        fields = ','.join(key + '=' + json.dumps(value, ensure_ascii=True) for key, value in values.items())
        statements.append('hl.monitor({' + fields + '})')
    run('hyprctl', 'eval', ';'.join(statements))


def verify(items):
    current = {m['name']: m for m in monitors()}
    if set(current) != {m['name'] for m in items}:
        raise ValueError('Ekran bağlantısı değişti; önceki ayarlara dönülüyor.')
    for item in items:
        m = current[item['name']]
        if bool(m.get('disabled')) == item['enabled']:
            raise ValueError(f"{item['name']}: Ekran durumu uygulanamadı.")
        if not item['enabled']:
            continue
        mirror = '' if m.get('mirrorOf', 'none') in ('none', '') else m['mirrorOf']
        if abs(m.get('scale', 1) - item['scale']) > .02 or m.get('transform', 0) != item['transform'] or mirror != item['mirror']:
            raise ValueError(f"{item['name']}: Ölçek, döndürme veya yansıtma uygulanamadı.")
        if not item['mirror'] and (abs(m['x'] - item['x']) > 1 or abs(m['y'] - item['y']) > 1):
            raise ValueError(f"{item['name']}: Ekran konumu uygulanamadı.")
        w, h, hz = re.split('[x@]', item['mode'])
        if sorted((m['width'], m['height'])) != sorted((int(w), int(h))) or abs(m['refreshRate'] - float(hz)) > .1:
            raise ValueError(f"{item['name']}: Çözünürlük veya yenileme hızı uygulanamadı.")


def save(items):
    names = {m['name'] for m in items}
    previous = CONFIG.read_text().splitlines() if CONFIG.exists() else []
    lines = [line for line in previous if line.split('\t')[0] not in names]
    lines += ['\t'.join(map(str, (m['name'], m['mode'], f"{m['x']}x{m['y']}", m['scale'], m['transform'], int(m['enabled']), m['mirror']))) for m in items]
    atomic(CONFIG, '\n'.join(lines) + '\n')


def rollback(before):
    names = {m['name'] for m in monitors()}
    remaining = [m for m in before if m['name'] in names]
    for m in remaining:
        if m['mirror'] not in names:
            m['mirror'] = ''
    if remaining and not any(m['enabled'] and not m['mirror'] for m in remaining):
        remaining[0].update(enabled=True, mirror='', mode='preferred', scale=1, x=0, y=0)
    apply(remaining)


def guard(token, items):
    with (RUNTIME / 'lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        before = []
        changed = False
        state = dict(token=token, phase='applying', deadline=0, message='Ekran ayarları uygulanıyor…')
        decision = RUNTIME / (token + '.decision')
        def interrupted(*_):
            raise RuntimeError('Deneme kesildi; önceki ayarlara dönüldü.')
        signal.signal(signal.SIGTERM, interrupted)
        signal.signal(signal.SIGINT, interrupted)
        try:
            publish(state)
            connected = monitors()
            items = validate(items, connected)
            before = snapshot(connected)
            changed = True
            apply(items)
            time.sleep(.7)
            verify(items)
            state.update(phase='pending', deadline=time.time() + TIMEOUT, message='Bu ekran ayarları kalsın mı?')
            publish(state)
            while time.time() < state['deadline']:
                if decision.exists():
                    if decision.read_text() == 'confirm':
                        verify(items)
                        save(items)
                        changed = False
                        state.update(phase='saved', message='Ekran ayarları kaydedildi.')
                        return
                    break
                time.sleep(.15)
            rollback(before)
            changed = False
            state.update(phase='reverted', message='Önceki ekran ayarlarına dönüldü.')
        except Exception as error:
            message = str(error)
            if changed:
                try:
                    rollback(before)
                except Exception as restore_error:
                    message += '\nGeri alma hatası: ' + str(restore_error)
            state.update(phase='error', message=message)
        finally:
            decision.unlink(missing_ok=True)
            publish(state)


def main(args):
    RUNTIME.mkdir(mode=0o700, parents=True, exist_ok=True)
    if args == ['status']:
        return status()
    if len(args) == 2 and args[0] == 'guard' and re.fullmatch('[a-f0-9]{32}', args[1]):
        request = RUNTIME / (args[1] + '.json')
        try:
            guard(args[1], json.loads(request.read_text()))
        finally:
            request.unlink(missing_ok=True)
        return status()
    if len(args) == 2 and args[0] == 'preview':
        items = validate(json.loads(args[1]), monitors())
        if status().get('phase') in ('applying', 'pending'):
            raise ValueError('Önce mevcut ekran denemesini onaylayın veya geri alın.')
        token = uuid.uuid4().hex
        request = RUNTIME / (token + '.json')
        atomic(request, json.dumps(items))
        try:
            run('systemd-run', '--user', '--collect', '--quiet', '--unit=atomshell-display-' + token,
                sys.executable, str(Path(__file__).resolve()), 'guard', token)
        except Exception:
            request.unlink(missing_ok=True)
            raise
        for _ in range(40):
            value = status()
            if value.get('token') == token:
                return value
            time.sleep(.1)
        raise RuntimeError('Ekran denemesi başlatılamadı; çalışan denemeyi kontrol edin.')
    if len(args) == 2 and args[0] in ('confirm', 'revert'):
        value = status()
        if value.get('phase') != 'pending' or value.get('token') != args[1] or time.time() >= value['deadline']:
            raise ValueError('Ekran denemesinin süresi doldu.')
        atomic(RUNTIME / (args[1] + '.decision'), args[0])
        return value
    raise ValueError('Geçersiz ekran ayarı komutu.')


if __name__ == '__main__':
    try:
        print(json.dumps(main(sys.argv[1:]), ensure_ascii=False))
    except Exception as error:
        print(json.dumps({'phase': 'error', 'message': str(error)}, ensure_ascii=False))
        sys.exit(1)
