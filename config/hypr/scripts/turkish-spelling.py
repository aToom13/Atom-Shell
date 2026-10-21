#!/usr/bin/env python3
"""Local Turkish spelling normalization; no semantic rewriting."""
from difflib import SequenceMatcher
import re
import sys
import unicodedata
from pathlib import Path

MODEL = Path.home() / ".local/share/desktop-assist/byt5-int8"


def folded(text):
    text = text.replace("İ", "i").replace("I", "ı").lower().replace("ı", "i")
    return "".join(c for c in unicodedata.normalize("NFD", text) if not unicodedata.combining(c))


def accept(original, candidate):
    candidate = " ".join(candidate.split())
    if not candidate or any(ord(c) < 32 or ord(c) == 127 for c in candidate):
        return original
    if SequenceMatcher(None, folded(original), folded(candidate), autojunk=False).ratio() < 0.75:
        return original
    protected = r"\d+(?:[.,:]\d+)*|\b(?:değil\w*|yok\w*|hayır|asla|sakın)\b"
    if re.findall(protected, original.lower()) != re.findall(protected, candidate.lower()):
        return original
    # Keep negative verb forms verbatim; expanding these safely needs morphological analysis.
    negative = r"\b\w*(?:m[ae](?:d[ıiuü]\w*|z\w*|[mk]\w*|y[ae]c[ae][kğ]\w*)|m[ıiuü]yo\w*|m[ae](?:y[ıi]n\w*)?)\b"
    if re.findall(negative, original.lower()) != re.findall(negative, candidate.lower()):
        return original
    before, after = re.findall(r"\w+", folded(original)), re.findall(r"\w+", folded(candidate))
    for op, start, end, new_start, new_end in SequenceMatcher(None, before, after, autojunk=False).get_opcodes():
        if op == "equal":
            continue
        old, new = "".join(before[start:end]), "".join(after[new_start:new_end])
        if op != "replace" or SequenceMatcher(None, old, new).ratio() < 0.7:
            return original
    return candidate


def correct(text, translator):
    chunks, current = [], ""
    for word in text.split():
        if current and len((current + " " + word).encode("utf-8")) > 300:
            chunks.append(current)
            current = ""
        current = (current + " " + word).strip()
    if current:
        chunks.append(current)
    inputs = [[chr(byte) for byte in ("düzelt: " + chunk).encode("utf-8")] + ["</s>"] for chunk in chunks]
    results = translator.translate_batch(inputs, beam_size=1, max_decoding_length=512, return_end_token=True)
    output = []
    for chunk, result in zip(chunks, results):
        tokens = result.hypotheses[0]
        if not tokens or tokens[-1] != "</s>" or any(len(token) != 1 for token in tokens[:-1]):
            output.append(chunk)
            continue
        try:
            candidate = bytes(ord(token) for token in tokens[:-1]).decode("utf-8")
            output.append(accept(chunk, candidate))
        except (ValueError, UnicodeError):
            output.append(chunk)
    return " ".join(output) if len(output) == len(chunks) else text


if __name__ == "__main__":
    import ctranslate2
    text = sys.stdin.read(6001)
    # ponytail: cap one dictation at 6000 characters; add streaming for longer recordings.
    if len(text) > 6000:
        raise ValueError("Düzeltme metni çok uzun.")
    translator = ctranslate2.Translator(str(MODEL), device="cpu", compute_type="int8", inter_threads=1, intra_threads=4)
    print(correct(text, translator), end="")
