#!/usr/bin/env python3
"""Synthetic OCR regression check; never captures the screen or changes the clipboard."""
import importlib.util
import ast
from pathlib import Path
import tempfile

from PIL import Image, ImageDraw, ImageFont

spec = importlib.util.spec_from_file_location('screen_ocr', Path(__file__).with_name('screen-ocr.py'))
ocr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ocr)
font = ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf', 18)
emoji_font = ImageFont.truetype(str(ocr.EMOJI_FONT), 109)
emojis = '😀 😂 ❤️ 👍 👎 🔥 🎉 ✅ ❌ ⚠️ ⭐ 🔒 📁 🇹🇷 🇬🇧 🇩🇪'.split()

with tempfile.TemporaryDirectory() as folder:
    for dark in (False, True):
        image = Image.new('RGB', (1000, 210), '#242424' if dark else 'white')
        draw = ImageDraw.Draw(image)
        text = 'Pijamalı hasta yağız şoföre çabucak güvendi.\nHello world 123.\nTutar: 1.234,56 TL | Saat: 14:35:09'
        draw.multiline_text((12, 12), text, font=font, fill='#dddddd' if dark else '#222222', spacing=10)
        draw.text((12, 120), 'Emoji:', font=font, fill='#dddddd' if dark else '#222222')
        for i, emoji in enumerate(emojis):
            glyph = Image.new('RGBA', (136, 128))
            ImageDraw.Draw(glyph).text((0, 0), emoji, font=emoji_font, embedded_color=True)
            glyph = glyph.resize((26, 24), Image.Resampling.LANCZOS)
            image.paste(glyph, (90+i*44, 116), glyph)
        assert [value[1] for value in ocr.find_emojis(image)] == emojis, ('emoji detection', dark)
        path = Path(folder)/'sample.png'
        image.save(path)
        actual = ocr.read_text(path)
        for expected in text.splitlines():
            assert expected in actual, (dark, expected, actual)
        assert ' '.join(emojis) in ' '.join(actual.split()), ('emoji ordering', dark, actual)
        print('PASS:', 'dark' if dark else 'light', 'Turkish, English, numbers, 16 emoji/flags')
    image = Image.new('RGB', (650, 70), 'white')
    draw = ImageDraw.Draw(image)
    for i, colour in enumerate(('#de2222', '#2277dd', '#22aa44')):
        draw.text((10+i*210, 15), 'TypeScript 123', font=font, fill=colour)
    assert ocr.find_emojis(image) == [], 'Coloured text was mistaken for emoji'
    print('PASS: coloured text is not emoji')
    for text in (
        'def greet(name):\n    if name:\n        print("Merhaba", name)\n\n    return 0',
        'const total = 42;\nif (total > 0) {\n    console.log("Merhaba", total);\n}',
        'ÜRÜN       ADET     FİYAT\nKalem      12       45,50 TL\nDefter     3        120,00 TL',
    ):
        image = Image.new('RGB', (900, 240), '#242424')
        ImageDraw.Draw(image).multiline_text((20, 20), text, font=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSansMono.ttf', 18), fill='#dddddd', spacing=10)
        image.save(path)
        actual = ocr.read_text(path)
        assert actual == text, ('layout', text, actual)
        if text.startswith('def '):
            ast.parse(actual)
    print('PASS: four/eight-space indentation, blank lines, Python/JavaScript syntax, table columns')
