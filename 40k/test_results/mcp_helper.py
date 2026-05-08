import socket, json, sys, time

def mcp_call(command, params=None, timeout=15):
    if params is None:
        params = {}
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    sock.connect(('127.0.0.1', 9080))
    msg = json.dumps({'id': 1, 'command': command, 'params': params}) + '\n'
    sock.sendall(msg.encode())
    data = b''
    try:
        while True:
            chunk = sock.recv(65536)
            if not chunk:
                break
            data += chunk
            if b'\n' in data:
                break
    except socket.timeout:
        pass
    sock.close()
    if data:
        return json.loads(data.decode().strip())
    return None

if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'ping'
    params = json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}
    result = mcp_call(cmd, params)
    print(json.dumps(result, indent=2) if result else 'No response')
