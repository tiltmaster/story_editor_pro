"""Generate a disposable Flutter integration host; never overwrite a local app."""
import argparse
import sys
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', default=str(ROOT / 'example'))
    args = parser.parse_args()
    host = Path(args.output).resolve()
    if host.exists():
        raise SystemExit(f'Refusing to overwrite existing app: {host}')
    flutter = shutil.which('flutter')
    if not flutter:
        raise SystemExit('Flutter must be on PATH')
    subprocess.run([flutter, 'create', '--no-pub', '--project-name', 'story_editor_ci',
                    '--platforms', 'android,ios', str(host)], check=True)
    # Keep the host compatible with the library's Dart floor even when a newer
    # Flutter template uses newer language syntax.
    (host / 'lib/main.dart').write_text(
        "import 'package:flutter/material.dart';\n"
        "void main() => runApp(const MaterialApp(home: Scaffold()));\n",
        encoding='utf-8')
    (host / 'test/widget_test.dart').unlink(missing_ok=True)
    (host / 'pubspec.yaml').write_text(
        "name: story_editor_ci\npublish_to: none\nenvironment:\n  sdk: ^3.8.1\n"
        "dependencies:\n  flutter:\n    sdk: flutter\n  story_editor_pro:\n"
        f"    path: '{ROOT.as_posix()}'\n"
        "dev_dependencies:\n  flutter_test:\n    sdk: flutter\n  flutter_lints: ^5.0.0\n"
        "flutter:\n  uses-material-design: true\n", encoding='utf-8')
    gradle = host / 'android/app/build.gradle.kts'
    text = gradle.read_text(encoding='utf-8')
    text = text.replace('minSdk = flutter.minSdkVersion', 'minSdk = 24')
    text = text.replace('compileSdk = flutter.compileSdkVersion', 'compileSdk = 36')
    gradle.write_text(text, encoding='utf-8')
    shutil.copyfile(ROOT / 'tool/ci/Podfile', host / 'ios/Podfile')
    if sys.platform == 'darwin':
        subprocess.run(['ruby', str(ROOT / 'tool/ci/configure_ios.rb'), str(host)], check=True)


if __name__ == '__main__':
    main()
