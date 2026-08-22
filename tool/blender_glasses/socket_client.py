"""Client for Blender 5.2's localhost, null-byte-delimited MCP socket."""

import argparse
import json
import socket
from pathlib import Path


def execute(code: str, host: str = "127.0.0.1", port: int = 9876) -> dict:
    payload = json.dumps({"type": "execute", "code": code, "strict_json": True}).encode() + b"\0"
    with socket.create_connection((host, port), timeout=15) as connection:
        connection.settimeout(180)
        connection.sendall(payload)
        response = bytearray()
        while b"\0" not in response:
            chunk = connection.recv(65536)
            if not chunk:
                raise RuntimeError("Blender MCP socket closed without a response")
            response.extend(chunk)
    return json.loads(bytes(response[:response.index(0)]))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("code_file", type=Path)
    args = parser.parse_args()
    code_path = args.code_file.resolve()
    code = f"__file__ = {str(code_path)!r}\n" + code_path.read_text(encoding="utf-8")
    result = execute(code)
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result.get("status") == "ok" else 1)
