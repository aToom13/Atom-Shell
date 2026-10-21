#!/usr/bin/env python3
"""Run with python3 ~/.config/hypr/scripts/check-desktop-assist.py; no live microphone/input."""
import importlib.util
import json
from pathlib import Path
import signal
import struct
import subprocess
import tempfile
from unittest.mock import patch
import wave

spec = importlib.util.spec_from_file_location('assist', Path(__file__).with_name('desktop-assist.py'))
assist = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assist)
spelling_spec = importlib.util.spec_from_file_location('spelling', Path(__file__).with_name('turkish-spelling.py'))
spelling = importlib.util.module_from_spec(spelling_spec)
spelling_spec.loader.exec_module(spelling)

assert spelling.accept('Şu an sesli yazmayla yazfım.', 'Şu an sesli yazmayla yazdım.') == 'Şu an sesli yazmayla yazdım.'
assert spelling.accept('bu gün hava cok guzel', 'Bugün hava çok güzel.') == 'Bugün hava çok güzel.'
contradiction = 'Yapacağım dedim ama yapmayacağım.'
assert spelling.accept(contradiction, contradiction) == contradiction
for before, after in (
    ('F12 rehberi açsın.', 'F10 rehberi açsın.'),
    ('Saat 14.30 gel.', 'Saat 15.30 gel.'),
    ('Ben bunu istemiyorum.', 'Ben bunu istiyorum.'),
    ('Ben bunu istemiyorum.', 'Ben bu istemiyorum.'),
    ('Ben bunu yazmadım.', 'Ben bunu yazdım.'),
    ('Dosyayı silme.', 'Dosyayı sil.'),
    ('Bu doğru değil.', 'Bu doğru.'),
    (contradiction, 'Yapacağım dedim ve yapacağım.'),
    ('Merhaba dünya.', 'Elbette, düzeltilmiş metin: Merhaba dünya.'),
):
    assert spelling.accept(before, after) == before, (before, after)

class Translation:
    hypotheses = [[chr(byte) for byte in 'Merhaba, dünya.'.encode('utf-8')] + ['</s>']]
class Translator:
    def translate_batch(self, inputs, **kwargs):
        assert inputs[0] == [chr(byte) for byte in 'düzelt: Merhaba dünya.'.encode('utf-8')] + ['</s>']
        return [Translation()]
assert spelling.correct('Merhaba dünya.', Translator()) == 'Merhaba, dünya.'
Translation.hypotheses = [['M', 'e']]
assert spelling.correct('Merhaba dünya.', Translator()) == 'Merhaba dünya.', 'Truncated correction accepted'

with tempfile.TemporaryDirectory() as temporary:
    directory = Path(temporary)
    engine = directory/'engine'
    model = directory/'model'
    engine.touch(); model.touch()
    vad = directory/'vad.bin'
    engine_commands = []
    clipboard, signals, calls = [], {}, []
    cancel = [False]
    natural = [False]
    fail = [False]
    amplitude = [2000]
    spelling_python, spelling_model = directory/'python', directory/'spelling-model.bin'
    spelling_fail, spelling_timeout, spelling_cancel = [False], [False], [False]

    class Child:
        def __init__(self, command, **kwargs):
            self.command = command
            self.returncode = None
            if command[0] == 'pw-record':
                assert command[command.index('--target')+1] == 'easyeffects_source', 'Dictation bypassed EasyEffects'
                with wave.open(command[-1], 'wb') as out:
                    out.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
                    out.writeframes(struct.pack('<1000h', *([amplitude[0]]*1000)))
            elif command[0] != str(spelling_python):
                engine_commands.append(command)
                Path(command[command.index('-of')+1] + '.txt').write_text('Merhaba\nTürkçe test.\x1b\x7f')
        def communicate(self, **kwargs):
            if spelling_timeout[0] and self.returncode is None:
                raise subprocess.TimeoutExpired(self.command, 20)
            if spelling_cancel[0]:
                signals[signal.SIGUSR2](signal.SIGUSR2, None)
            if self.returncode is None:
                self.returncode = 1 if spelling_fail[0] else 0
            return ('Merhaba, Türkçe test.', '')
        def wait(self, **kwargs):
            if cancel[0] and self.command[0] == 'pw-record':
                signals[signal.SIGUSR2](signal.SIGUSR2, None)
            elif self.command[0] == 'pw-record' and not natural[0]:
                signals[signal.SIGUSR1](signal.SIGUSR1, None)
            self.returncode = 1 if self.command[0] == 'pw-record' or fail[0] else 0
            return self.returncode
        def poll(self): return self.returncode
        def send_signal(self, event): calls.append(event)
        def terminate(self): self.returncode = -15
        def kill(self): self.returncode = -9

    with patch.multiple(assist, RUNTIME=directory, ENGINE=engine, MODEL=model, VAD_MODEL=vad, RECOVERY=directory/"recovery", SPELLING_PYTHON=spelling_python, SPELLING_MODEL=spelling_model), \
         patch.object(assist, 'window', return_value={'address':'0x1'}), \
         patch.object(assist, 'run', return_value='[{"name":"eDP-1","focused":true}]'), \
         patch.object(assist, 'copy_text', side_effect=clipboard.append), \
         patch.object(assist, 'paste_if_focused', return_value=False), \
         patch.object(assist, 'notice'), \
         patch.object(assist.signal, 'signal', side_effect=lambda event, fn: signals.update({event:fn})), \
         patch.object(assist.subprocess, 'Popen', side_effect=Child):
        assist.main(['stt'])
        assert clipboard == ['Merhaba Türkçe test.'], 'Speech must not insert a newline/Return'
        assert '--vad' not in engine_commands[-1], 'Missing VAD model must not break dictation'
        assert engine_commands[-1][engine_commands[-1].index('-l')+1] == 'tr'
        assert '--prompt' in engine_commands[-1] and '-sns' in engine_commands[-1]
        amplitude[0] = 50
        assist.main(['stt'])
        assert len(clipboard) == 2, 'Quiet speech was discarded before recognition'
        clipboard.pop(); amplitude[0] = 2000
        vad.touch()
        natural[0] = True
        assist.main(['stt'])
        assert '--vad' in engine_commands[-1] and str(vad) in engine_commands[-1]
        assert len(clipboard) == 2, 'pw-record sample-limit status 1 rejected a valid WAV'
        clipboard.pop(); natural[0] = False
        assert json.loads((directory/'stt.json').read_text())['phase'] == 'done'
        assert not list(directory.glob('speech-*')), 'Temporary audio/transcripts leaked'
        cancel[0] = True
        assist.main(['stt'])
        assert len(clipboard) == 1 and json.loads((directory/'stt.json').read_text())['phase'] == 'idle'
        cancel[0] = False; fail[0] = True
        try: assist.main(['stt'])
        except ValueError: pass
        else: raise AssertionError('Engine failure ignored')
        assert len(clipboard) == 1 and json.loads((directory/'stt.json').read_text())['phase'] == 'error'
        assert len(list((directory/'recovery').glob('*.wav'))) == 1, 'Failed recognition lost the recording'
        assert not list(directory.glob('speech-*'))
        fail[0] = False
        spelling_python.touch(); spelling_model.touch()
        assist.main(['stt'])
        assert clipboard[-1] == 'Merhaba, Türkçe test.'
        spelling_fail[0] = True
        assist.main(['stt'])
        assert clipboard[-1] == 'Merhaba Türkçe test.', 'Spelling failure lost the raw transcription'
        spelling_fail[0] = False; spelling_timeout[0] = True
        assist.main(['stt'])
        assert clipboard[-1] == 'Merhaba Türkçe test.', 'Spelling timeout lost the raw transcription'
        spelling_timeout[0] = False; spelling_cancel[0] = True
        before = len(clipboard)
        assist.main(['stt'])
        assert len(clipboard) == before and json.loads((directory/'stt.json').read_text())['phase'] == 'idle'

    with patch.object(assist, 'window', return_value={'address':'other'}), patch.object(assist, 'run') as run:
        assert not assist.paste_if_focused({'address':'initial'})
        run.assert_not_called()
    with patch.object(assist, 'window', return_value={'address':'same'}), patch.object(assist, 'run', return_value='true') as run:
        assert not assist.paste_if_focused({'address':'same'})
        assert run.call_count == 1, 'Locked screen must not receive pasted text'
    with patch.object(assist, 'window', return_value={'address':'same'}), patch.object(assist, 'run', return_value='false') as run:
        assert assist.paste_if_focused({'address':'same','class':'kitty'})
        assert run.call_args.args[0:2] == ('ydotool','key') and '42:1' in run.call_args.args
        assert not any(str(arg).startswith('28:') for arg in run.call_args.args), 'Never send Enter'

    with patch.object(assist, 'RUNTIME', directory), patch.object(assist, 'copy_text') as copy, \
         patch.object(assist, 'notice'), patch.object(assist.subprocess, 'run', return_value=subprocess.CompletedProcess([],1,'')), \
         patch.object(assist, 'run') as run:
        assist.ocr(); copy.assert_not_called(); run.assert_not_called()
    with patch.object(assist, 'RUNTIME', directory), patch.object(assist, 'copy_text') as copy, \
         patch.object(assist, 'notice'), patch.object(assist.subprocess, 'run', return_value=subprocess.CompletedProcess([],0,'0,0 100x100\n')), \
         patch.object(assist, 'run', side_effect=['','Türkçe OCR\n']) as run:
        assist.ocr(); copy.assert_called_once_with('Türkçe OCR')
        assert run.call_args.args[:2] == ('python3', str(Path(__file__).with_name('screen-ocr.py')))
        assert not list(directory.glob('ocr-*'))
    with patch.object(assist, 'run', return_value='    first\nsecond\n'), patch.object(assist, 'copy_text') as copy, patch.object(assist, 'notice'):
        assist.ocr_image('image.png')
        copy.assert_called_once_with('    first\nsecond')

    capture = directory/'ocr-123-456.png'
    capture.touch()
    with patch.object(assist, 'RUNTIME', directory), patch.object(assist, 'ocr_image') as read:
        assist.main(['ocr-image',str(capture)])
        read.assert_called_once_with(capture)
        assert not capture.exists(), 'OCR screenshot was retained'
    capture.touch()
    with patch.object(assist, 'RUNTIME', directory), patch.object(assist, 'ocr_image', side_effect=ValueError('test')), patch.object(assist, 'notice'):
        try: assist.main(['ocr-image',str(capture)])
        except ValueError: pass
        else: raise AssertionError('OCR failure ignored')
        assert not capture.exists(), 'Failed OCR screenshot was retained'
    unrelated=directory/'private.png'
    unrelated.touch()
    with patch.object(assist, 'RUNTIME', directory):
        try: assist.main(['ocr-image',str(unrelated)])
        except ValueError: pass
        else: raise AssertionError('Unrelated image accepted for deletion')
        assert unrelated.exists()
        capture.symlink_to(unrelated)
        try: assist.main(['ocr-image',str(capture)])
        except ValueError: pass
        else: raise AssertionError('OCR symlink accepted')
        assert unrelated.exists()

print('PASS: quiet speech, STT lifecycle, spelling guards/failure/timeout/cancel, cleanup, focus/lock protection, paste without Enter, OCR')
