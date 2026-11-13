import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

enum Link { connecting, connected, disconnected }

/// One Socket.IO connection to the LOCO server, shared by game, chat and voice.
/// Controllers register handlers with [on]; handlers survive reconnections.
class SocketService extends ChangeNotifier {
  io.Socket? _socket;
  String? _url;
  Link link = Link.disconnected;

  final Map<String, List<void Function(dynamic)>> _handlers = {};
  final Set<String> _bound = {};

  bool get connected => _socket?.connected ?? false;

  /// Server payloads arrive as dynamic; this turns them into a Map safely.
  static Map<String, dynamic> asMap(dynamic d) {
    if (d is List && d.isNotEmpty) d = d.first;
    if (d is Map) return Map<String, dynamic>.from(d);
    return <String, dynamic>{};
  }

  void on(String event, void Function(dynamic) cb) {
    _handlers.putIfAbsent(event, () => []).add(cb);
    final s = _socket;
    if (s != null && event != 'connect' && event != 'disconnect' && _bound.add(event)) {
      s.on(event, (d) => _dispatch(event, d));
    }
  }

  void _dispatch(String event, dynamic data) {
    for (final cb in List.of(_handlers[event] ?? const [])) {
      cb(data);
    }
  }

  void connect(String url) {
    if (_url == url && _socket != null) {
      if (!connected) _socket!.connect();
      return;
    }
    _teardown();
    _url = url;
    link = Link.connecting;
    notifyListeners();

    final s = io.io(url, io.OptionBuilder().disableAutoConnect().enableForceNew().build());

    s.onConnect((_) {
      link = Link.connected;
      notifyListeners();
      _dispatch('connect', null);
    });
    s.onDisconnect((_) {
      link = Link.disconnected;
      notifyListeners();
      _dispatch('disconnect', null);
    });
    s.onConnectError((_) {
      if (link != Link.connected) {
        link = Link.disconnected;
        notifyListeners();
      }
    });

    _bound.clear();
    for (final e in _handlers.keys) {
      if (e == 'connect' || e == 'disconnect') continue;
      _bound.add(e);
      s.on(e, (d) => _dispatch(e, d));
    }

    _socket = s;
    s.connect();
  }

  void _teardown() {
    final s = _socket;
    if (s != null) {
      s.dispose();
    }
    _socket = null;
    _bound.clear();
  }

  /// Always sends a payload (an empty map when there is none): the server's
  /// handlers accept it.
  void emit(String event, [Map<String, dynamic>? data]) {
    _socket?.emit(event, data ?? <String, dynamic>{});
  }

  /// Emit and wait for the server's acknowledgement.
  void emitAck(String event, Map<String, dynamic> data, void Function(Map<String, dynamic>) cb) {
    _socket?.emitWithAck(event, data, ack: (dynamic res) => cb(asMap(res)));
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }
}
