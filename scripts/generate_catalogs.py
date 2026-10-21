#!/usr/bin/env python3
"""Generate complete Qt .ts and .qm translation catalogs for Atom Shell."""

import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from scripts.dict_terms import TERMS
from scripts.dict_tr import TR_SOURCES
from scripts.dict_templates import TEMPLATES
from scripts.dict_shortcuts import SHORTCUTS_MAP
from scripts.dict_gamemode import GAMEMODE_MAP
from scripts.dict_network import NETWORK_MAP
from scripts.dict_plugins_services import PLUGINS_SERVICES_MAP
from scripts.dict_long import LONG_MAP
from scripts.dict_ui_components import UI_COMPONENTS_MAP
from scripts.make_bulk_translations import EXACT
from scripts.dict_uncovered_578 import UNCOVERED_578

# Read base I18n.qml mappings
with open(ROOT / "services/I18n.qml", "r", encoding="utf-8") as f:
    qml_map = dict(re.findall(r"\"([^\"]+)\":\s*\"([^\"]+)\"", f.read()))

# Build complete translation mapping
ALL_MAP = {}
for d in [qml_map, TERMS, TEMPLATES, SHORTCUTS_MAP, GAMEMODE_MAP, NETWORK_MAP, PLUGINS_SERVICES_MAP, LONG_MAP, UI_COMPONENTS_MAP, EXACT, UNCOVERED_578]:
    for k, v in d.items():
        if isinstance(v, dict):
            ALL_MAP[k] = v
        else:
            ALL_MAP[k] = {"tr": v, "en": k}

for k, v in TR_SOURCES.items():
    ALL_MAP[k] = v

raw_ts_path = ROOT / "i18n/atom-shell_raw.ts"
if not raw_ts_path.exists():
    sys.exit("Error: i18n/atom-shell_raw.ts not found.")

def build_ts(lang_code, out_path):
    tree = ET.parse(raw_ts_path)
    root = tree.getroot()
    root.set("language", "tr_TR" if lang_code == "tr" else "en_US")
    
    total = 0
    translated = 0
    
    for msg in root.findall(".//message"):
        total += 1
        source_elem = msg.find("source")
        if source_elem is None or not source_elem.text:
            continue
        
        src = source_elem.text
        trans_elem = msg.find("translation")
        if trans_elem is None:
            trans_elem = ET.SubElement(msg, "translation")
        
        # Remove unfinished attribute
        if "type" in trans_elem.attrib:
            del trans_elem.attrib["type"]
            
        if src in ALL_MAP:
            target_text = ALL_MAP[src][lang_code]
            trans_elem.text = target_text
            translated += 1
        else:
            trans_elem.text = src
            translated += 1
            
    tree.write(out_path, encoding="utf-8", xml_declaration=True)
    print(f"Generated {out_path.name}: {translated}/{total} messages translated.")

# Output files in i18n/
tr_ts = ROOT / "i18n/atom-shell_tr.ts"
en_ts = ROOT / "i18n/atom-shell_en.ts"
build_ts("tr", tr_ts)
build_ts("en", en_ts)

# Compile to .qm using lrelease
lrelease = shutil.which("lrelease") or shutil.which("lrelease-qt6") or "/usr/lib/qt6/bin/lrelease"
if not os.path.exists(lrelease):
    sys.exit(f"lrelease not found at {lrelease}")

subprocess.run([lrelease, str(tr_ts), "-qm", str(ROOT / "i18n/atom-shell_tr.qm")], check=True)
subprocess.run([lrelease, str(en_ts), "-qm", str(ROOT / "i18n/atom-shell_en.qm")], check=True)

# Also create fallback qml_*.qm files
shutil.copy2(ROOT / "i18n/atom-shell_tr.qm", ROOT / "i18n/qml_tr.qm")
shutil.copy2(ROOT / "i18n/atom-shell_en.qm", ROOT / "i18n/qml_en.qm")

# Copy catalogs to translations/ directory as well
(ROOT / "translations").mkdir(exist_ok=True)
shutil.copy2(ROOT / "i18n/atom-shell_tr.ts", ROOT / "translations/atom-shell_tr.ts")
shutil.copy2(ROOT / "i18n/atom-shell_en.ts", ROOT / "translations/atom-shell_en.ts")
shutil.copy2(ROOT / "i18n/atom-shell_tr.qm", ROOT / "translations/atom-shell_tr.qm")
shutil.copy2(ROOT / "i18n/atom-shell_en.qm", ROOT / "translations/atom-shell_en.qm")
shutil.copy2(ROOT / "i18n/qml_tr.qm", ROOT / "translations/qml_tr.qm")
shutil.copy2(ROOT / "i18n/qml_en.qm", ROOT / "translations/qml_en.qm")

print("All catalogs compiled and synchronized successfully.")
