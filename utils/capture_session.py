#!/usr/bin/python3
"""Private Hyprland portal sessions: reuse the user's selection without a second picker."""
import json
import os
from pathlib import Path
import re
import select
import signal
import shutil
import subprocess
import sys
import tempfile
import time
import math

from caelestia.utils.capture import destination, game_name
from caelestia.utils.paths import recordings_dir, c_state_dir


def validate(source):
    if not isinstance(source, dict):
        raise ValueError("Geçersiz yakalama kaynağı")
    if source.get("kind") == "window":
        if not re.fullmatch(r"0x[0-9a-fA-F]+", str(source.get("window", {}).get("address", ""))):
            raise ValueError("Geçersiz pencere")
    elif source.get("kind") == "region":
        if not re.fullmatch(r"[\w.-]+", str(source.get("output", ""))):
            raise ValueError("Geçersiz ekran")
        for key in ("x", "y", "width", "height"):
            value = source.get(key)
            if type(value) is not int or value < (1 if key in ("width", "height") else 0) or value > 32768:
                raise ValueError("Geçersiz seçim boyutu")
    else:
        raise ValueError("Geçersiz yakalama türü")
    return source


def selection(source, window_list):
    validate(source)
    if source["kind"] == "region":
        return "region:{output}@{x},{y},{width},{height}".format(**source)
    address = int(source["window"]["address"], 16)
    entries = re.findall(r"(\d+)\[HC>\](.*?)\[HT>\](.*?)\[HE>\](\d+)\[HA>\]", window_list)
    for handle, app_class, title, mapped in entries:
        if int(mapped) == address:
            return "window:" + handle
    # Older compositors may not provide address mapping. Never guess between windows.
    matches = [(handle, app_class, title) for handle, app_class, title, mapped in entries
               if app_class == source["window"].get("class") and title == source["window"].get("title")]
    if len(matches) == 1:
        return "window:" + matches[0][0]
    raise ValueError("Seçilen pencere kapandı veya kesin olarak eşleştirilemedi")


def crop_bounds(source, width, height, logical_width, logical_height):
    validate(source)
    x = max(0, min(width - 2, round(source["x"] * width / logical_width)))
    y = max(0, min(height - 2, round(source["y"] * height / logical_height)))
    w = max(2, min(width - x, round(source["width"] * width / logical_width)))
    h = max(2, min(height - y, round(source["height"] * height / logical_height)))
    return x, y, width - x - w, height - y - h


def stream(source):
    import dbus
    import gi
    gi.require_version("Gst", "1.0")
    from gi.repository import Gst
    Gst.init(None)
    Gst.Registry.get().scan_path(str(Path.home() / ".local/lib/caelestia/gstreamer"))
    source = validate(source)
    processes = []
    bus = None
    with tempfile.TemporaryDirectory(prefix="caelestia-portal-") as temporary:
        root = Path(temporary)
        (root / "hypr").mkdir()
        (root / "hypr/xdph.conf").write_text(
            "screencopy {\n custom_picker_binary = " + str(Path(__file__).resolve())
            + "\n force_shm = 1\n max_fps = 60\n}\n")
        with (root / "portal.log").open("w") as log:
            try:
                daemon = subprocess.Popen(["dbus-daemon", "--session", "--nofork", "--print-address=1"],
                                          stdout=subprocess.PIPE, stderr=log, text=True)
                processes.append(daemon)
                address = daemon.stdout.readline().strip()
                if not address:
                    raise RuntimeError("Yakalama oturumu başlatılamadı")
                monitor = None
                portal_source = source
                if source["kind"] == "region":
                    monitor = next(m for m in json.loads(subprocess.check_output(["hyprctl", "monitors", "-j"])) if m["name"] == source["output"])
                    logical_width = round(monitor["width"] / monitor["scale"])
                    logical_height = round(monitor["height"] / monitor["scale"])
                    if monitor.get("transform", 0) % 2:
                        logical_width, logical_height = logical_height, logical_width
                    # Capture one output once; move its crop without restarting audio/video.
                    portal_source = source | dict(x=0, y=0, width=logical_width, height=logical_height)
                env = os.environ | {"DBUS_SESSION_BUS_ADDRESS": address, "XDG_CONFIG_HOME": temporary,
                                    "CAELESTIA_CAPTURE_SOURCE": json.dumps(portal_source)}
                processes.append(subprocess.Popen(["/usr/lib/xdg-desktop-portal-hyprland"], env=env, stdout=log, stderr=log))
                bus = dbus.bus.BusConnection(address)
                deadline = time.monotonic() + 8
                name = "org.freedesktop.impl.portal.desktop.hyprland"
                while not bus.name_has_owner(name):
                    if time.monotonic() > deadline or processes[-1].poll() is not None:
                        raise RuntimeError("Hyprland pencere yakalama hizmeti başlatılamadı")
                    time.sleep(0.05)
                portal = dbus.Interface(bus.get_object(name, "/org/freedesktop/portal/desktop"), "org.freedesktop.impl.portal.ScreenCast")
                request = dbus.ObjectPath("/org/freedesktop/portal/desktop/request/caelestia/capture")
                session = dbus.ObjectPath("/org/freedesktop/portal/desktop/session/caelestia/capture")
                options = dbus.Dictionary({}, signature="sv")
                code, result = portal.CreateSession(request, session, "com.caelestia.Capture", options)
                if code:
                    raise RuntimeError("Yakalama oturumu oluşturulamadı")
                time.sleep(0.2)  # Let the portal receive the compositor's toplevel list.
                code, result = portal.SelectSources(request, session, "com.caelestia.Capture", dbus.Dictionary({"types": dbus.UInt32(2 if source["kind"] == "window" else 1), "cursor_mode": dbus.UInt32(2)}, signature="sv"), timeout=10)
                if code:
                    raise RuntimeError("Yakalama kaynağı seçilemedi")
                code, result = portal.Start(request, session, "com.caelestia.Capture", "", options, timeout=10)
                if code or not result.get("streams"):
                    raise RuntimeError("Görüntü akışı başlatılamadı")
                folder = c_state_dir / "capture-parts"
                path = destination(folder, "", "part_", ".mp4")
                node, properties = result["streams"][0]
                width, height = properties.get("size", source.get("window", {}).get("size", (source.get("width", 1280), source.get("height", 720))))
                frame_width, frame_height = int(width), int(height)
                crop_pipeline = ""
                if monitor:
                    crop_target = crop_bounds(source, frame_width, frame_height, logical_width, logical_height)
                    left, top, right, bottom = crop_target
                    width, height = frame_width-left-right, frame_height-top-bottom
                    crop_pipeline = f"videocrop name=crop left={left} top={top} right={right} bottom={bottom} ! "
                width, height = max(2, int(width) // 2 * 2), max(2, int(height) // 2 * 2)
                codec = "vah264enc bitrate=16000 key-int-max=120" if Gst.ElementFactory.find("vah264enc") else "x264enc speed-preset=veryfast tune=zerolatency bitrate=16000"
                pipeline = Gst.parse_launch(
                    f"pipewiresrc name=vsrc path={int(node)} do-timestamp=true provide-clock=false keepalive-time=50 use-bufferpool=false ! queue ! videoconvert ! {crop_pipeline}videoscale add-borders=true ! videorate ! "
                    f"video/x-raw,width={width},height={height},framerate=60/1,pixel-aspect-ratio=1/1 ! {codec} ! h264parse ! mp4mux name=mux faststart=true ! filesink location=\"{path}\""
                    + (" pulsesrc name=asrc device=" + subprocess.check_output(["pactl", "get-default-sink"], text=True).strip()
                       + '.monitor do-timestamp=true ! queue ! audioconvert ! audioresample ! audio/x-raw,rate=48000,channels=2 ! avenc_aac ! mux.' if source.get("sound") else ""))
                if monitor:
                    crop = pipeline.get_by_name("crop")
                    crop_position = list(crop_target)
                    applied_crop = crop_target
                    last_frame = time.monotonic()

                    def update_crop(pad, info):
                        nonlocal last_frame, applied_crop
                        now = time.monotonic()
                        amount = 1 - math.exp(-min(now-last_frame, .1) / .045)
                        last_frame = now
                        target = crop_target
                        for i, value in enumerate(target):
                            crop_position[i] += (value-crop_position[i]) * amount
                        values = tuple(round(value) for value in crop_position)
                        if values != applied_crop:
                            left, top, right, bottom = values
                            crop.set_properties(left=left, top=top, right=right, bottom=bottom)
                            applied_crop = values
                        return Gst.PadProbeReturn.OK

                    crop.get_static_pad("sink").add_probe(Gst.PadProbeType.BUFFER, update_crop)
                messages = pipeline.get_bus()
                try:
                    if pipeline.set_state(Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE:
                        raise RuntimeError("Video kodlayıcı başlatılamadı")
                    print(json.dumps({"recording": True, "path": str(path)}), flush=True)
                    pending_input = ""
                    stopping = False
                    while not stopping:
                        message = messages.timed_pop_filtered(0, Gst.MessageType.ERROR | Gst.MessageType.EOS)
                        if message:
                            if message.type == Gst.MessageType.ERROR:
                                raise RuntimeError(str(message.parse_error()[0]))
                            break
                        if select.select([sys.stdin], [], [], 0.02)[0]:
                            chunk = os.read(sys.stdin.fileno(), 65536)
                            if not chunk:
                                break
                            pending_input += chunk.decode()
                            while "\n" in pending_input:
                                command, pending_input = pending_input.split("\n", 1)
                                if command.startswith("{"):
                                    updated = validate(json.loads(command))
                                    if not monitor or updated["kind"] != "region" or updated["output"] != source["output"]:
                                        raise ValueError("Canlı alan değişikliği aynı ekranda olmalı")
                                    crop_target = crop_bounds(updated, frame_width, frame_height, logical_width, logical_height)
                                    print(json.dumps({"source": updated}), flush=True)
                                elif command in ("pause", "resume"):
                                    state = Gst.State.PAUSED if command == "pause" else Gst.State.PLAYING
                                    pipeline.set_state(state)
                                    if command == "pause":
                                        pipeline.get_state(2 * Gst.SECOND)
                                    print(json.dumps({"paused": command == "pause"}), flush=True)
                                else:
                                    stopping = True
                                    break
                    pipeline.set_state(Gst.State.PLAYING)
                    pipeline.send_event(Gst.Event.new_eos())
                    message = messages.timed_pop_filtered(10 * Gst.SECOND, Gst.MessageType.EOS | Gst.MessageType.ERROR)
                    if not message or message.type == Gst.MessageType.ERROR:
                        raise RuntimeError("Kayıt sonlandırılamadı; parça dosyası korundu: " + (str(message.parse_error()) if message else "EOS zaman aşımı"))
                finally:
                    pipeline.set_state(Gst.State.NULL)
            finally:
                if bus:
                    bus.close()
                for process in reversed(processes):
                    if process.poll() is None:
                        process.terminate()
                        try:
                            process.wait(timeout=3)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait()


def finish(data):
    parts = [Path(p).resolve() for p in data["parts"]]
    base = (c_state_dir / "capture-parts").resolve()
    if not parts or any(p.parent != base or not p.is_file() or p.suffix != ".mp4" for p in parts):
        raise ValueError("Kayıt parçaları bulunamadı; mevcut dosyalar korundu")
    infos = []
    for part in parts:
        info = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(part)]))
        if not any(s["codec_type"] == "video" for s in info["streams"]) or float(info["format"].get("duration", 0)) <= 0:
            raise ValueError("Kayıtta görüntü bulunamadı; parça dosyaları korundu")
        infos.append(info["streams"])
    saved = destination(recordings_dir, game_name(data.get("window", {})), "recording_", ".mp4")
    if len(parts) == 1:
        shutil.move(parts[0], saved)
    else:
        # ponytail: a source change creates a segment; normalize only at final save.
        # Keep every original until the joined file is safely written.
        video = next(s for s in infos[0] if s["codec_type"] == "video")
        width, height = video["width"] // 2 * 2, video["height"] // 2 * 2
        signatures = [[(s.get("codec_name"), s.get("width"), s.get("height"), s.get("pix_fmt"), s.get("sample_rate"), s.get("channels")) for s in streams] for streams in infos]
        with tempfile.TemporaryDirectory(prefix="caelestia-join-", dir=base) as temporary:
            normalized = []
            for index, (part, streams) in enumerate(zip(parts, infos)):
                if all(s == signatures[0] for s in signatures):
                    normalized.append(part)
                    continue
                target = Path(temporary) / f"{index}.mp4"
                args = ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-i", str(part)]
                if not any(s["codec_type"] == "audio" for s in streams):
                    args += ["-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo"]
                args += ["-map", "0:v:0", "-map", "0:a:0" if any(s["codec_type"] == "audio" for s in streams) else "1:a:0",
                         "-vf", f"scale={width}:{height}:force_original_aspect_ratio=decrease:force_divisible_by=2,pad={width}:{height}:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=60",
                         "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p",
                         "-c:a", "aac", "-ar", "48000", "-ac", "2", "-shortest", str(target)]
                subprocess.run(args, check=True)
                normalized.append(target)
            manifest = Path(temporary) / "parts.txt"
            manifest.write_text("".join(f"file '{p}'\n" for p in normalized))
            pending = saved.with_suffix(".pending.mp4")
            subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", str(manifest),
                            "-c", "copy", "-movflags", "+faststart", str(pending)], check=True)
            pending.replace(saved)
        for part in parts:
            part.unlink()
    print(json.dumps({"saved": str(saved)}), flush=True)


def main():
    if "CAELESTIA_CAPTURE_SOURCE" in os.environ:
        print("[SELECTION]/" + selection(json.loads(os.environ["CAELESTIA_CAPTURE_SOURCE"]), os.environ.get("XDPH_WINDOW_SHARING_LIST", "")))
        return
    if len(sys.argv) != 3:
        raise ValueError("Usage: capture_session.py {stream|finish} JSON")
    if sys.argv[1] == "stream":
        stream(json.loads(sys.argv[2]))
    elif sys.argv[1] == "finish":
        finish(json.loads(sys.argv[2]))
    else:
        raise ValueError("Geçersiz yakalama komutu")


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    try:
        main()
    except Exception as error:
        print(json.dumps({"error": str(error)}), flush=True)
        sys.exit(1)
