#!/usr/bin/env python3
"""ThinkPad dictation and selected-area OCR; entirely local."""
import array
import fcntl
import json
import os
from pathlib import Path
import re
import signal
import shutil
import subprocess
import sys
import tempfile
import time
import wave

HOME = Path.home()
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "desktop-assist"
RECOVERY = HOME / ".local/state/desktop-assist/recovery"
ENGINE = HOME / ".local/share/desktop-assist/whisper.cpp/build-vulkan/bin/whisper-cli"
CPU_ENGINE = HOME / ".local/share/desktop-assist/whisper.cpp/build/bin/whisper-cli"
MODEL = HOME / ".local/share/dikte/models/whisper/ggml-large-v3-turbo-q5_0.bin"
VAD_MODEL = HOME / ".local/share/desktop-assist/ggml-silero-v6.2.0.bin"
SPELLING_PYTHON = HOME / ".local/share/desktop-assist/corrector-env/bin/python"
SPELLING_MODEL = HOME / ".local/share/desktop-assist/byt5-int8/model.bin"
SPEECH_PROMPT = "Türkçe konuşma; düzgün yazım ve noktalama. Klavye kısayolları, pencere yerleşimi, sesli yazma, Hyprland, F10, F11, F12."
os.environ.setdefault("YDOTOOL_SOCKET", str(RUNTIME.parent / ".ydotool_socket"))


def run(*command, **kwargs):
    return subprocess.run(command, capture_output=True, text=True, check=True, timeout=30, **kwargs).stdout


def notice(title, message=""):
    subprocess.run(["notify-send", "-a", "Klavye araçları", "-t", "4500", title, message], check=False, timeout=5)


def state(phase, **details):
    content = {"phase": phase, "pid": os.getpid(), **details}
    with tempfile.NamedTemporaryFile(mode="w", dir=RUNTIME, delete=False) as file:
        json.dump(content, file)
    Path(file.name).replace(RUNTIME / "stt.json")


def control(cancel=False):
    try:
        current = json.loads((RUNTIME / "stt.json").read_text())
        pid = int(current["pid"])
        command = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
        if str(Path(__file__).resolve()).encode() not in command or b"stt" not in command:
            return
        if current["phase"] == "recording" or cancel and current["phase"] == "processing":
            os.kill(pid, signal.SIGUSR2 if cancel else signal.SIGUSR1)
    except (OSError, ValueError, KeyError):
        pass


def window():
    try:
        return json.loads(run("hyprctl", "-j", "activewindow"))
    except (OSError, ValueError, subprocess.SubprocessError):
        return {}


def copy_text(text):
    subprocess.run(["wl-copy", "--type", "text/plain;charset=utf-8"], input=text, text=True, check=True, timeout=5)


def paste_if_focused(target):
    try:
        if not target.get("address") or window().get("address") != target["address"]:
            return False
        if run("atomshell", "ipc", "call", "lock", "isLocked").strip() != "false":
            return False
        terminal = re.search(r"kitty|foot|alacritty|wezterm|ghostty|konsole|terminal", target.get("class", ""), re.I)
        keys = ["29:1", "42:1", "47:1", "47:0", "42:0", "29:0"] if terminal else ["29:1", "47:1", "47:0", "29:0"]
        run("ydotool", "key", "--key-delay", "20", *keys)
        return True
    except (OSError, subprocess.SubprocessError):
        return False


def dictation():
    if not ENGINE.is_file() or not MODEL.is_file():
        raise ValueError("Yerel Whisper motoru veya modeli bulunamadı.")
    target = window()
    monitors = json.loads(run("hyprctl", "-j", "monitors"))
    screen = next((monitor["name"] for monitor in monitors if monitor.get("focused")), "")
    cancelled = False
    child = None

    def stop(signum, _frame):
        nonlocal cancelled
        cancelled = cancelled or signum in (signal.SIGUSR2, signal.SIGTERM, signal.SIGINT)
        if child and child.poll() is None:
            child.send_signal(signal.SIGINT if not cancelled else signal.SIGTERM)

    for event in (signal.SIGUSR1, signal.SIGUSR2, signal.SIGTERM, signal.SIGINT):
        signal.signal(event, stop)
    try:
        with tempfile.TemporaryDirectory(prefix="speech-", dir=RUNTIME) as directory:
            audio = Path(directory) / "speech.wav"
            try:
                with (Path(directory) / "record.log").open("w") as errors:
                    child = subprocess.Popen(["pw-record", "--target", "easyeffects_source", "--rate", "16000", "--channels", "1", "--format", "s16", "--sample-count", "4800000", str(audio)], stdout=subprocess.DEVNULL, stderr=errors)
                    state("recording", screen=screen, started=time.time())
                    code = child.wait(timeout=310)
                if cancelled:
                    state("idle")
                    return
                # pw-record also returns 1 for normal stop/sample-limit completion; validate its WAV.
                if code not in (0, 1, -signal.SIGINT, 128 + signal.SIGINT) or not audio.exists():
                    raise ValueError("Mikrofon kaydı alınamadı. EasyEffects mikrofon çıkışını kontrol edin.")
                with wave.open(str(audio)) as stream:
                    samples = array.array("h", stream.readframes(stream.getnframes()))
                if not samples and (Path(directory) / "record.log").read_text().strip():
                    raise ValueError("Mikrofon kaydı alınamadı. EasyEffects mikrofon çıkışını kontrol edin.")
                # Quiet speech must reach VAD/Whisper; an absolute loudness gate discarded valid recordings.
                if not any(samples):
                    state("done", message="Ses algılanmadı", screen=screen)
                    return
                state("processing", screen=screen)
                output = Path(directory) / "transcript"
                vad = ["--vad", "--vad-model", str(VAD_MODEL), "--vad-speech-pad-ms", "200"] if VAD_MODEL.is_file() else []
                with (Path(directory) / "whisper.log").open("w") as log:
                    for engine in (ENGINE, CPU_ENGINE):
                        child = subprocess.Popen([str(engine), "-m", str(MODEL), "-f", str(audio), "-l", "tr", "-t", "4", "--prompt", SPEECH_PROMPT, "-sns", *vad, "-otxt", "-of", str(output), "-nt"], stdout=log, stderr=log)
                        code = child.wait(timeout=300)
                        if code == 0 or cancelled:
                            break
                if cancelled:
                    state("idle")
                    return
                if code:
                    raise ValueError("Whisper sesi çözemedi.")
                # Dictation never emits Return: multiline speech must not execute terminal commands.
                text = " ".join(output.with_suffix(".txt").read_text().split())
                text = "".join(character for character in text if ord(character) >= 32 and ord(character) != 127)
                if not text or text in ("[BLANK_AUDIO]", "[SILENCE]"):
                    state("done", message="Konuşma algılanmadı", screen=screen)
                    return
                if SPELLING_MODEL.is_file() and SPELLING_PYTHON.is_file():
                    state("processing", screen=screen, correcting=True, message="Türkçe yazım düzeltiliyor…")
                    try:
                        child = subprocess.Popen([str(SPELLING_PYTHON), str(Path(__file__).with_name("turkish-spelling.py"))],
                                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
                        candidate, _ = child.communicate(input=text, timeout=20)
                        if child.returncode == 0 and candidate.strip() and not any(ord(c) < 32 or ord(c) == 127 for c in candidate):
                            text = " ".join(candidate.split())
                    except subprocess.TimeoutExpired:
                        child.kill()
                        child.communicate()
                    except (OSError, subprocess.SubprocessError):
                        pass  # Keep the raw transcription if spelling correction fails.
                    if cancelled:
                        state("idle")
                        return
                copy_text(text)
                pasted = paste_if_focused(target)
                state("done", message="Metin yapıştırıldı" if pasted else "Metin panoya kopyalandı", screen=screen)
            except (OSError, ValueError, subprocess.SubprocessError, wave.Error):
                if not cancelled and audio.exists() and audio.stat().st_size > 44:
                    RECOVERY.mkdir(mode=0o700, parents=True, exist_ok=True)
                    recovery = RECOVERY / f"speech-{time.time_ns()}.wav"
                    shutil.copyfile(audio, recovery)
                    recovery.chmod(0o600)
                    notice("Dikte tamamlanamadı", f"Ses kaydı korundu: {recovery}")
                raise
    finally:
        if child and child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()


def ocr_image(image):
    text = run("python3", str(Path(__file__).with_name("screen-ocr.py")), str(image)).rstrip("\r\n")
    if text.strip():
        copy_text(text)
        notice("Yazı panoya kopyalandı", "Ctrl+V ile yapıştırabilirsiniz.")
    else:
        notice("Seçilen alanda yazı bulunamadı")


def ocr():
    selection = subprocess.run(["slurp", "-d", "-b", "#10101499", "-c", "#b8c4ffff", "-s", "#b8c4ff12", "-w", "2"], capture_output=True, text=True, timeout=300)
    if selection.returncode:
        return
    geometry = selection.stdout.strip()
    if not re.fullmatch(r"-?\d+,-?\d+ \d+x\d+", geometry):
        raise ValueError("Geçersiz ekran alanı.")
    with tempfile.TemporaryDirectory(prefix="ocr-", dir=RUNTIME) as directory:
        image = str(Path(directory) / "area.png")
        run("grim", "-g", geometry, image)
        ocr_image(image)


def main(args):
    if not args or not (len(args) == 1 and args[0] in ("init", "stt", "stop", "cancel", "ocr") or len(args) == 2 and args[0] == "ocr-image"):
        raise ValueError("Kullanım: desktop-assist.py init|stt|stop|cancel|ocr veya ocr-image görüntü.png")
    RUNTIME.mkdir(mode=0o700, parents=True, exist_ok=True)
    mode = args[0]
    image = None
    if mode == "ocr-image":
        image = Path(args[1])
        if image.is_symlink() or image.resolve().parent != RUNTIME.resolve() or not re.fullmatch(r"ocr-\d+-\d+\.png", image.name) or image.stat().st_uid != os.getuid():
            raise ValueError("Geçersiz OCR yakalama dosyası.")
    if mode == "init":
        if not (RUNTIME / "stt.json").exists():
            state("idle")
        return
    if mode in ("stop", "cancel"):
        control(mode == "cancel")
        return
    with (RUNTIME / f"{'ocr' if mode == 'ocr-image' else mode}.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            if mode == "stt":
                control()
            elif image:
                image.unlink(missing_ok=True)
                notice("Metin tanıma devam ediyor", "Önceki alanın okunmasını bekleyin.")
            return
        try:
            if mode == "stt":
                dictation()
            elif image:
                ocr_image(image)
            else:
                ocr()
        except (OSError, ValueError, subprocess.SubprocessError, wave.Error) as error:
            if mode == "stt":
                state("error", message=str(error)[:180])
            else:
                notice("Metin kopyalanamadı", str(error)[:180])
            raise
        finally:
            if image:
                image.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (OSError, ValueError, subprocess.SubprocessError, wave.Error) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
