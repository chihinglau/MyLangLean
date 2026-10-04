import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Finds the MyLangLean PC server on the local network via UDP broadcast.
///
/// Mirrors the protocol in `server/app/services/discovery.py`: we send
/// `MLL-PING` to 255.255.255.255:43800 a few times and take the *sender*
/// address of the first `MLL-PONG` reply as the host, which is correct
/// even when the PC has multiple adapters.
class LanServerDiscovery {
  static const int discoveryPort = 43800;
  static const int defaultHttpPort = 8000;

  /// Returns the first server base URL found (e.g.
  /// `http://192.168.1.20:8000`) or `null` if nothing replies in time.
  static Future<String?> discover({
    Duration timeout = const Duration(milliseconds: 3500),
  }) async {
    final completer = Completer<String?>();
    RawDatagramSocket? socket;
    Timer? probeTimer;
    Timer? timeoutTimer;
    var probesLeft = 3;

    void finish(String? value) {
      if (completer.isCompleted) return;
      completer.complete(value);
    }

    void sendPing() {
      final s = socket;
      if (s == null || probesLeft <= 0) return;
      probesLeft--;
      try {
        s.send(utf8.encode('MLL-PING'),
            InternetAddress('255.255.255.255'), discoveryPort);
      } catch (_) {
        // Broadcast may be blocked on some networks; keep listening for
        // replies to the earlier probes.
      }
    }

    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = socket?.receive();
        if (dg == null) return;
        final text = utf8.decode(dg.data, allowMalformed: true);
        if (!text.startsWith('MLL-PONG ')) return;
        try {
          final m = jsonDecode(text.substring('MLL-PONG '.length))
              as Map<String, dynamic>;
          final httpPort =
              (m['httpPort'] as num?)?.toInt() ?? defaultHttpPort;
          finish('http://${dg.address.address}:$httpPort');
        } catch (_) {
          // Malformed reply: ignore and wait for another probe.
        }
      });

      sendPing();
      probeTimer =
          Timer.periodic(const Duration(milliseconds: 800), (_) => sendPing());
      timeoutTimer = Timer(timeout, () => finish(null));
    } catch (_) {
      finish(null);
    }

    try {
      return await completer.future;
    } finally {
      probeTimer?.cancel();
      timeoutTimer?.cancel();
      socket?.close();
    }
  }
}
