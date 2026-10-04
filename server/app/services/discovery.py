"""LAN auto-discovery for MyLangLean clients.

Phones on the same Wi-Fi can broadcast a tiny UDP probe and learn this
server's reachable address automatically, so nobody has to type the PC's
LAN IP by hand. Standard library only.

Wire protocol (plain UTF-8 text, intentionally simple):
  client -> 255.255.255.255:DISCOVERY_PORT : ``MLL-PING``
  server -> client                            : ``MLL-PONG <json>``

The reply carries the HTTP port; the client takes the *sender address*
of the reply as the host, which is always the right one even when the PC
has several network adapters.
"""
from __future__ import annotations

import json
import socket
import threading

DISCOVERY_PORT = 43800
PING = b"MLL-PING"


class LanDiscoveryService:
    """Answers UDP discovery probes on a background thread."""

    def __init__(self, http_port: int = 8000, port: int = DISCOVERY_PORT):
        self.http_port = http_port
        self.port = port
        self._sock: socket.socket | None = None
        self._thread: threading.Thread | None = None
        self._stop = threading.Event()

    @property
    def running(self) -> bool:
        return self._sock is not None

    def start(self) -> None:
        if self._sock is not None:
            return
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(("0.0.0.0", self.port))
            sock.settimeout(0.5)
        except OSError:
            # Port unavailable (another instance?): discovery is optional,
            # never let it crash the API startup.
            sock.close()
            return
        self._sock = sock
        name = f"mll-lan-discovery:{self.port}"
        self._thread = threading.Thread(target=self._serve, name=name,
                                        daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        sock, self._sock = self._sock, None
        thread, self._thread = self._thread, None
        if sock is not None:
            try:
                sock.close()
            except OSError:
                pass
        if thread is not None:
            thread.join(timeout=2)
        self._stop.clear()

    def _serve(self) -> None:
        assert self._sock is not None
        payload = (
            "MLL-PONG "
            + json.dumps({
                "service": "mylanglean",
                "httpPort": self.http_port,
                "version": "0.5.0",
                }, separators=(",", ":"))
        ).encode("utf-8")
        while not self._stop.is_set():
            try:
                data, addr = self._sock.recvfrom(512)
            except socket.timeout:
                continue
            except OSError:
                break
            if data.strip() == PING:
                try:
                    self._sock.sendto(payload, addr)
                except OSError:
                    pass
