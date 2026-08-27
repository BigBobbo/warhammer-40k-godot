#!/usr/bin/env python3
"""NDJSON-over-TCP client for the in-game GodotMCP bridge (127.0.0.1:9080).
Usage: mcp_client.py <command> [json-params-or-bare-code]
For execute_script a non-JSON second arg becomes {"code": ..., "multiline": true}.
"""
import json, socket, sys

def call(command, params, timeout=180.0):
    s = socket.create_connection(("127.0.0.1", 9080), timeout=timeout)
    s.sendall((json.dumps({"id": 1, "command": command, "params": params}) + "\n").encode())
    buf = b""
    while b"\n" not in buf:
        chunk = s.recv(65536)
        if not chunk:
            break
        buf += chunk
    s.close()
    return json.loads(buf.decode().split("\n")[0]) if buf else {"error": "no response"}

if __name__ == "__main__":
    cmd = sys.argv[1]
    raw = sys.argv[2] if len(sys.argv) > 2 else "{}"
    try:
        params = json.loads(raw)
        if not isinstance(params, dict):
            raise ValueError
    except ValueError:
        params = {"code": raw, "multiline": True} if cmd == "execute_script" else {"value": raw}
    print(json.dumps(call(cmd, params), indent=1)[:6000])
