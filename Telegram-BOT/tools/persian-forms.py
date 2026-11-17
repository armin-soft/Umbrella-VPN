"""Regenerate the bundled Unicode presentation-form compatibility map.
Developer-only; uses Python's standard library. PHP does not require intl.
"""
import json
import unicodedata
from pathlib import Path
forms = {}
for cp in list(range(0xFB50, 0xFE00)) + list(range(0xFE70, 0xFF00)):
    char = chr(cp)
    normalized = unicodedata.normalize('NFKC', char)
    if char != normalized:
        forms[char] = normalized
path = Path(__file__).resolve().parents[1] / 'Resources' / 'Persian-Forms.json'
path.write_text(json.dumps(forms, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
