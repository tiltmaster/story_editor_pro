"""Headless CLI: blender --background --factory-startup --python build_glasses.py -- --output DIR"""

import argparse
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
from glasses_generator import build_asset  # noqa: E402

parser = argparse.ArgumentParser()
parser.add_argument("--output", required=True)
parser.add_argument("--replace-existing", action="store_true")
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
args = parser.parse_args(argv)
report = build_asset(args.output, args.replace_existing)
print("NIERO_AR_GLASSES_RESULT=" + json.dumps(report, separators=(",", ":")))

