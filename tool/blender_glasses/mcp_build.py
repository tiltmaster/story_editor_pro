"""Payload executed inside the live Blender MCP session."""

import sys
import importlib
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PACKAGE_ROOT = SCRIPT_DIR.parent.parent
OUTPUT_DIR = PACKAGE_ROOT / "assets" / "ar" / "glasses"
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
import glasses_generator
importlib.reload(glasses_generator)
from glasses_generator import build_asset

result = build_asset(OUTPUT_DIR, replace_existing=True, canonicalize_file=True)
