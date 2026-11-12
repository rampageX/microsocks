"""Run local SOCKS5 CONNECT and authentication smoke tests."""

import socket
import subprocess
import sys
import time


def read_exact(sock, size):
    data = bytearray()
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            raise RuntimeError("Proxy closed the connection")
        data.extend(chunk)
    return data


def open_proxy(process, port):
    deadline = time.monotonic() + 10
    while process.poll() is None and time.monotonic() < deadline:
        try:
            return socket.create_connection(("127.0.0.1", port), timeout=2)
        except ConnectionRefusedError:
            time.sleep(0.05)
    raise RuntimeError("Proxy did not start")


def check_relay(client, target, *, auth, address):
    client.sendall(b"\x05\x01" + (b"\x02" if auth else b"\x00"))
    expected = b"\x05\x02" if auth else b"\x05\x00"
    assert read_exact(client, 2) == expected
    if auth:
        client.sendall(b"\x01\x04test\x06secret")
        assert read_exact(client, 2) == b"\x01\x00"

    target_port = target.getsockname()[1]
    client.sendall(b"\x05\x01\x00\x03" + bytes([len(address)]) + address + target_port.to_bytes(2, "big"))
    assert read_exact(client, 10)[:4] == b"\x05\x00\x00\x01"
    peer, _ = target.accept()
    with peer:
        peer.settimeout(2)
        client.sendall(b"ping")
        assert read_exact(peer, 4) == b"ping"
        peer.sendall(b"pong")
        assert read_exact(client, 4) == b"pong"


def run_proxy_test(command, auth_once):
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]

    with socket.socket() as target:
        target.bind(("127.0.0.1", 0))
        target.listen()
        target.settimeout(2)
        args = [*command, "-i", "127.0.0.1", "-p", str(port), "-b", "127.0.0.1"]
        if auth_once:
            args += ["-1", "-u", "test", "-P", "secret"]
        process = subprocess.Popen(args)
        try:
            if auth_once:
                with open_proxy(process, port) as client:
                    check_relay(client, target, auth=True, address=b"127.0.0.1")
            with open_proxy(process, port) as client:
                check_relay(client, target, auth=False, address=b"localhost")
        finally:
            process.terminate()
            process.wait(timeout=5)


def main(command):
    run_proxy_test(command, auth_once=False)
    run_proxy_test(command, auth_once=True)
    print("SOCKS5 no-auth, auth-once, hostname lookup and TCP relay passed")


if __name__ == "__main__":
    main(sys.argv[1:])
