#!/usr/bin/env python3
"""Local screenshot OCR with high-resolution text and conservative emoji matching."""
import csv
import io
from pathlib import Path
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageOps, ImageStat

DATA = Path.home() / '.local/share/desktop-assist/tessdata-best'
EMOJI_FONT = Path('/usr/share/fonts/noto/NotoColorEmoji.ttf')
# ponytail: Turkish/English and common symbols; extend this repertoire for other languages.
ALPHABET = ''.join(chr(i) for i in range(32, 127)) + 'ÇĞİÖŞÜçğıöşüÂâÎîÛûé¢£¥§©«®°»—–‘’“”€™₺…±×÷≤≥≠'
# ponytail: common Noto Color Emoji glyphs only; add other fonts/sequences after measured samples.
EMOJIS = '😀 😃 😄 😁 😆 😅 😂 🤣 😊 🙂 🙃 😉 😍 🥰 😘 😎 🤔 😐 😑 😶 🙄 😏 😒 😔 😢 😭 😱 😴 🤗 🤩 🥳 😇 🤨 🧐 😡 🤬 🤯 🥺 🫠 🫡 ❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 💕 👍 👎 👋 🙌 👏 🙏 💪 👌 ✌️ 🤞 🔥 🎉 🎊 ✅ ❌ ⚠️ ⭐ 🌟 ✨ 🔒 🔓 📁 📂 📄 📋 📌 📍 🔗 💻 🖥️ 📱 ⌨️ 🎤 🔊 🔇 💡 🚀 🌍 ☀️ 🌙 ☁️ 🌧️ 🌈 🐈 🐕 🐱 🐶 🍎 ☕ 🇹🇷 🇬🇧 🇩🇪 🇺🇸 🇫🇷 🇮🇹 🇪🇸 🇦🇱'.split()


def spans(indices):
    if not len(indices):
        return []
    groups = np.split(indices, np.flatnonzero(np.diff(indices) > 1) + 1)
    return [(int(group[0]), int(group[-1]) + 1) for group in groups]


def colour_mask(rgb):
    return np.ptp(rgb.astype(np.int16), axis=2) > 45


def emoji_templates():
    if not EMOJI_FONT.is_file():
        return []
    font = ImageFont.truetype(str(EMOJI_FONT), 109)
    templates = []
    for emoji in EMOJIS:
        image = Image.new('RGBA', (160, 140))
        ImageDraw.Draw(image).text((0, 0), emoji, font=font, embedded_color=True)
        rgba = np.asarray(image)
        yy, xx = np.nonzero(colour_mask(rgba[:, :, :3]) & (rgba[:, :, 3] > 100))
        if len(xx):
            box = (int(xx.min()), int(yy.min()), int(xx.max()) + 1, int(yy.max()) + 1)
            pixels = np.asarray(image.crop(box).resize((32, 32), Image.Resampling.LANCZOS)).astype(np.float32)
            full = image.getbbox()
            margins = ((box[0]-full[0])/(box[2]-box[0]), (box[1]-full[1])/(box[3]-box[1]), (full[2]-box[2])/(box[2]-box[0]), (full[3]-box[3])/(box[3]-box[1]))
            templates.append((emoji, (box[2] - box[0]) / (box[3] - box[1]), pixels, margins))
    return templates


def find_emojis(image):
    rgb = np.asarray(image)
    mask = colour_mask(rgb)
    if not mask.any():
        return []
    templates = emoji_templates()
    if not templates:
        return []
    found = []
    for row_top, row_bottom in spans(np.flatnonzero(mask.any(axis=1))):
        for left, right in spans(np.flatnonzero(mask[row_top:row_bottom].any(axis=0))):
            yy = np.flatnonzero(mask[row_top:row_bottom, left:right].any(axis=1))
            top, bottom = row_top + int(yy[0]), row_top + int(yy[-1]) + 1
            width, height = right - left, bottom - top
            if min(width, height) < 6 or max(width, height) > 160 or not 0.35 < width / height < 2.4:
                continue
            x1, y1, x2, y2 = max(0, left-4), max(0, top-4), min(image.width, right+4), min(image.height, bottom+4)
            ring = np.ones((y2-y1, x2-x1), dtype=bool)
            ring[top-y1:bottom-y1, left-x1:right-x1] = False
            background = np.median(rgb[y1:y2, x1:x2][ring], axis=0) if ring.any() else np.array([255, 255, 255])
            pixels = np.asarray(image.crop((left, top, right, bottom)).resize((32, 32), Image.Resampling.LANCZOS)).astype(np.float32)
            scores = []
            for emoji, ratio, template, margins in templates:
                if abs(np.log((width / height) / ratio)) > 0.22:
                    continue
                alpha = template[:, :, 3:] / 255
                expected = template[:, :, :3] * alpha + background * (1 - alpha)
                scores.append((float(np.abs(pixels - expected).mean()), emoji, margins))
            scores.sort()
            if len(scores) < 2 or scores[0][0] > 26 or scores[1][0] - scores[0][0] < 0.9:
                continue
            margins = scores[0][2]
            box = (max(0, left-round(margins[0]*width)-1), max(0, top-round(margins[1]*height)-1), min(image.width, right+round(margins[2]*width)+1), min(image.height, bottom+round(margins[3]*height)+1))
            found.append((box, scores[0][1], tuple(int(c) for c in background)))
    return found


def read_text(path):
    Image.MAX_IMAGE_PIXELS = 30_000_000
    with Image.open(path) as source:
        if source.width * source.height > Image.MAX_IMAGE_PIXELS:
            raise ValueError('Seçilen görüntü çok büyük.')
        source.load()
        image = source.convert('RGB')
    emojis = find_emojis(image)
    for box, _emoji, background in emojis:
        ImageDraw.Draw(image).rectangle((box[0], box[1], box[2]-1, box[3]-1), fill=background)
    gray = ImageOps.grayscale(image)
    if ImageStat.Stat(gray).median[0] < 128:
        gray = ImageOps.invert(gray)
    scale = min(2, 6000 / max(image.size))
    gray = ImageOps.autocontrast(gray).resize((max(1, round(image.width*scale)), max(1, round(image.height*scale))), Image.Resampling.LANCZOS)
    gray = ImageOps.expand(gray, border=30, fill=255)
    png = io.BytesIO()
    gray.save(png, format='PNG')
    language = 'Latin' if (DATA / 'Latin.traineddata').is_file() else 'tur+eng'
    command = ['tesseract', 'stdin', 'stdout', '-l', language, '--oem', '1', '--psm', '6', '--dpi', '300', '-c', 'tessedit_char_whitelist=' + ALPHABET]
    if language == 'Latin' or all((DATA / (lang + '.traineddata')).is_file() for lang in ('tur', 'eng')):
        command += ['--tessdata-dir', str(DATA)]
    command += ['-c', 'tessedit_create_tsv=1']
    result = subprocess.run(command, input=png.getvalue(), capture_output=True, check=True, timeout=30)
    lines = {}
    for row in csv.DictReader(io.StringIO(result.stdout.decode('utf-8')), delimiter='\t', quoting=csv.QUOTE_NONE):
        if row['level'] != '5' or not row.get('text', '').strip():
            continue
        box = tuple(int(row[key]) for key in ('left', 'top', 'width', 'height'))
        key = tuple(row[key] for key in ('block_num', 'par_num', 'line_num'))
        lines.setdefault(key, []).append((*box, row['text'].strip(), False))
    groups = list(lines.values())
    for box, emoji, _background in emojis:
        left, top, right, bottom = (round(v*scale) + 30 for v in box)
        middle = (top + bottom) / 2
        closest = min(groups, key=lambda group: abs(middle - np.median([word[1] + word[3]/2 for word in group])), default=None)
        if closest is None or abs(middle - np.median([word[1] + word[3]/2 for word in closest])) > (bottom-top)*0.65:
            closest = []
            groups.append(closest)
        closest.append((left, top, right-left, bottom-top, emoji, True))
    if not groups:
        return ''
    # ponytail: pixels preserve relative spacing, not original Tab bytes or invisible trailing spaces.
    groups.sort(key=lambda group: np.median([word[1] + word[3]/2 for word in group]))
    words = [word for group in groups for word in group]
    origin = min(word[0] for word in words)
    widths = [word[2]/(len(word[4])-0.3) for word in words if not word[5] and len(word[4]) >= 4]
    pitch = float(np.median(widths)) if widths else float(np.median([word[3] for word in words]))*0.65
    pitch = max(1, pitch)
    centers = [float(np.median([word[1]+word[3]/2 for word in group])) for group in groups]
    gaps = [b-a for a, b in zip(centers, centers[1:]) if b-a > 1]
    line_pitch = float(np.quantile(gaps, 0.25)) if gaps else 1
    output = []
    last_center = None
    for group, center in zip(groups, centers):
        if last_center is not None:
            output.extend([''] * max(0, round((center-last_center)/line_pitch)-1))
        group.sort(key=lambda word: word[0])
        text = ' ' * max(0, round((group[0][0]-origin)/pitch))
        previous = None
        for word in group:
            space = ''
            if previous:
                gap = word[0]-previous[0]-previous[2]
                spaces = max(1, round(gap/pitch-0.3))
                if (word[5] or previous[5]) and gap < min(word[3], previous[3])*0.25:
                    spaces = 0
                space = ' ' * spaces
            text += space + word[4]
            previous = word
        output.append(text)
        last_center = center
    return '\n'.join(output)


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Kullanım: screen-ocr.py görüntü.png')
    print(read_text(sys.argv[1]), end='')
