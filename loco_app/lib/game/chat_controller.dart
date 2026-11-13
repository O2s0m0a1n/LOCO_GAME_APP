import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../services/audio_service.dart';
import '../services/socket_service.dart';
import 'game_controller.dart';

class ChatMsg {
  const ChatMsg(this.role, this.text, this.ts);
  final String role;
  final String text;
  final DateTime ts;
}

/// Real-time text chat (same server events as the website).
class ChatController extends ChangeNotifier {
  ChatController(this.net, this.audio, this.game) {
    net.on('chat_message', _onMessage);
    _sub = game.ui.listen((e) {
      if (e.kind == UiKind.left) reset();
    });
  }

  final SocketService net;
  final AudioService audio;
  final GameController game;

  final List<ChatMsg> messages = [];
  int unread = 0;
  bool sheetOpen = false;

  final StreamController<ChatMsg> _incoming = StreamController<ChatMsg>.broadcast();

  /// Fires for a message from the opponent while the chat is closed (for the notification).
  Stream<ChatMsg> get incoming => _incoming.stream;

  StreamSubscription<UiEvent>? _sub;
  DateTime _lastSend = DateTime.fromMillisecondsSinceEpoch(0);

  void _onMessage(dynamic data) {
    final m = SocketService.asMap(data);
    final role = m['role']?.toString();
    final text = m['text']?.toString();
    if ((role != 'X' && role != 'O') || text == null) return;

    final ms = (m['ts'] as num?)?.toInt();
    final msg = ChatMsg(role!, text, ms == null ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(ms));
    messages.add(msg);
    if (messages.length > 100) messages.removeAt(0);

    if (role != game.myRole) {
      audio.sfx('message');
      HapticFeedback.lightImpact();
      if (!sheetOpen) {
        unread++;
        _incoming.add(msg);
      }
    }
    notifyListeners();
  }

  /// Returns a translation key when something is wrong, otherwise null.
  String? send(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    if (text.length > kChatMaxLength) return 'err_chat_too_long';
    if (!net.connected) return 'err_not_connected';

    final now = DateTime.now();
    if (now.difference(_lastSend).inMilliseconds < 400) return null; // the server enforces the real limit
    _lastSend = now;

    net.emit('chat_message', {'text': text});
    return null;
  }

  void setSheetOpen(bool open) {
    sheetOpen = open;
    if (open) unread = 0;
    notifyListeners();
  }

  void reset() {
    messages.clear();
    unread = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _incoming.close();
    super.dispose();
  }
}
