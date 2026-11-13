import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/audio_service.dart';
import '../services/socket_service.dart';
import 'bot.dart';

enum GameMode { online, bot }

/// One-shot things the UI must show (dialogs, notifications).
enum UiKind { toast, toastError, serverError, result, restartRequested, hideRestartRequest, hideResult, left }

class UiEvent {
  const UiEvent(this.kind, [this.key, this.extra]);
  final UiKind kind;
  final String? key;
  final String? extra;
}

/// Game state for online rooms and for playing against the computer.
/// Mirrors the website's game.js, including the restart consent flow.
class GameController extends ChangeNotifier {
  GameController(this.net, this.audio) {
    net.on('connect', (_) {
      if (!isBot && room != null) _join(room!);
      notifyListeners();
    });
    net.on('disconnect', (_) => notifyListeners());
    net.on('your_role', _onRole);
    net.on('room_update', _onRoomUpdate);
    net.on('restart_requested', (_) => _onRestartRequested());
    net.on('restart_declined', (_) => _onRestartDeclined());
    net.on('error_message', _onError);
    net.addListener(notifyListeners);
  }

  static const _botDelay = Duration(milliseconds: 550);
  static const _restartWait = Duration(seconds: 30);

  final SocketService net;
  final AudioService audio;

  final StreamController<UiEvent> _ui = StreamController<UiEvent>.broadcast();
  Stream<UiEvent> get ui => _ui.stream;

  GameMode mode = GameMode.online;
  bool inGameScreen = false;
  String? myRole;
  String? room;
  bool started = false;
  String turn = 'X';
  String? winner;
  int players = 0;
  List<String> board = List.filled(9, '');
  List<int> line = const [];
  bool restartPending = false;
  String botLevel = 'medium';

  bool _synced = false;
  Timer? _botTimer;
  Timer? _resultTimer;
  Timer? _restartTimer;
  Timer? _incomingTimer;

  // ---------- derived state ----------
  bool get isBot => mode == GameMode.bot;
  bool get botThinking => _botTimer != null;
  int get movesCount => board.where((c) => c.isNotEmpty).length;
  bool get linkOk => isBot || net.connected;
  bool get live => started && winner == null && linkOk;
  bool get canPlay => live && turn == myRole && !botThinking;

  /// A running game whose progress would be lost by leaving.
  bool get inActiveGame =>
      isBot ? (winner == null && movesCount > 0) : (room != null && started && winner == null);

  bool get canRestart =>
      isBot ? movesCount > 0 : (net.connected && started && movesCount > 0 && !restartPending);

  String get statusKey {
    if (!isBot && !net.connected) return 'statusDisconnected';
    if (!started) return 'statusWaiting';
    if (winner == 'draw') return 'statusDraw';
    if (winner != null) return winner == myRole ? 'statusWin' : 'statusLose';
    if (turn == myRole) return 'statusYourTurn';
    return isBot ? 'statusBotTurn' : 'statusOppTurn';
  }

  String nameKey(String symbol) {
    if (symbol == myRole) return 'you';
    if (isBot) return 'computer';
    return players == 2 ? 'opponent' : 'waitingShort';
  }

  // ---------- online rooms ----------
  /// Creates a random code and joins it. Returns the code, or null when offline.
  String? createRoom() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    final code = List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
    return joinRoom(code) ? code : null;
  }

  bool joinRoom(String raw) {
    final code = raw.trim().toUpperCase();
    if (code.isEmpty) {
      _ui.add(const UiEvent(UiKind.toastError, 'err_enter_code'));
      return false;
    }
    if (!net.connected) {
      _ui.add(const UiEvent(UiKind.toastError, 'err_not_connected'));
      return false;
    }
    mode = GameMode.online;
    room = code;
    _join(code);
    return true;
  }

  void _join(String code) {
    _synced = false;
    net.emit('join_game', {'code': code});
  }

  void _onRole(dynamic data) {
    if (isBot || room == null) return;
    myRole = SocketService.asMap(data)['role']?.toString();
    inGameScreen = true;
    notifyListeners();
  }

  void _onRoomUpdate(dynamic data) {
    final d = SocketService.asMap(data);
    if (isBot || d['code'] != room) return;

    final previousWinner = winner;
    final hadMoves = movesCount > 0;

    started = d['started'] == true;
    turn = (d['turn'] ?? 'X').toString();
    winner = d['winner']?.toString();
    players = (d['players'] as num?)?.toInt() ?? 0;

    final next = ((d['board'] as List?) ?? const []).map((e) => e?.toString() ?? '').toList();
    while (next.length < 9) {
      next.add('');
    }
    var moved = false;
    for (var i = 0; i < 9; i++) {
      if (next[i].isNotEmpty && board[i] != next[i]) moved = true;
    }
    board = next.take(9).toList();
    line = ((d['line'] as List?) ?? const []).map((e) => (e as num).toInt()).toList();

    final first = !_synced;
    _synced = true;

    if (!started) {
      _clearRestart();
    } else if (hadMoves && movesCount == 0 && !first) {
      _clearRestart(); // the restart was accepted
      _ui.add(const UiEvent(UiKind.toast, 'restartDone'));
    }

    if (winner == null) {
      _cancelResult();
      if (moved && !first) audio.sfx('move');
    } else if (winner != previousWinner && !first) {
      _announceFinish();
    }
    notifyListeners();
  }

  void _onError(dynamic data) {
    final d = SocketService.asMap(data);
    final code = d['code']?.toString();
    _ui.add(UiEvent(UiKind.serverError, code, d['message']?.toString()));
    // Join failed: forget the room and stay in the lobby
    if ((code == 'room_full' || code == 'invalid_code') && !inGameScreen) {
      room = null;
      notifyListeners();
    }
  }

  // ---------- moves ----------
  void tapCell(int i) {
    if (!canPlay || board[i].isNotEmpty) return;
    HapticFeedback.selectionClick();
    if (isBot) {
      _humanMoveLocal(i);
    } else {
      net.emit('make_move', {'index': i}); // the server validates every move
    }
  }

  // ---------- result ----------
  void _announceFinish() {
    if (winner == 'draw') {
      audio.sfx('draw');
      _scheduleResult('draw');
    } else if (winner == myRole) {
      audio.sfx('win');
      _scheduleResult('win');
    } else {
      _scheduleResult('lose');
    }
  }

  void _scheduleResult(String kind) {
    _resultTimer?.cancel();
    // a short pause so the player can see the final move first
    _resultTimer = Timer(const Duration(milliseconds: 600), () => _ui.add(UiEvent(UiKind.result, kind)));
  }

  void _cancelResult() {
    _resultTimer?.cancel();
    _ui.add(const UiEvent(UiKind.hideResult));
  }

  // ---------- play vs computer ----------
  void startBot(String level) {
    _botTimer?.cancel();
    _botTimer = null;
    _clearRestart();
    if (room != null) net.emit('leave_game'); // coming from a waiting room
    room = null;
    mode = GameMode.bot;
    botLevel = level;
    myRole = 'X';
    started = true;
    turn = 'X';
    winner = null;
    players = 2;
    board = List.filled(9, '');
    line = const [];
    _cancelResult();
    inGameScreen = true;
    notifyListeners();
  }

  void _humanMoveLocal(int i) {
    board = List.of(board)..[i] = 'X';
    audio.sfx('move');
    final r = Bot.result(board);
    if (r != null) {
      _finishLocal(r);
      return;
    }
    turn = 'O';
    _botTimer = Timer(_botDelay, _botMove);
    notifyListeners();
  }

  void _botMove() {
    _botTimer = null;
    if (!isBot || winner != null) return;
    final idx = Bot.bestMove(board, botLevel, 'O', 'X');
    if (idx < 0) return;
    board = List.of(board)..[idx] = 'O';
    audio.sfx('move');
    final r = Bot.result(board);
    if (r != null) {
      _finishLocal(r);
    } else {
      turn = 'X';
      notifyListeners();
    }
  }

  void _finishLocal(({String winner, List<int> line}) r) {
    winner = r.winner;
    line = r.line;
    notifyListeners();
    _announceFinish();
  }

  void restartBot() {
    _botTimer?.cancel();
    _botTimer = null;
    started = true;
    turn = 'X';
    winner = null;
    board = List.filled(9, '');
    line = const [];
    _cancelResult();
    notifyListeners();
  }

  // ---------- restart (online needs the opponent's consent) ----------
  void sendRestartRequest() {
    if (restartPending) return;
    net.emit('restart_request');
    restartPending = true;
    _ui.add(const UiEvent(UiKind.toast, 'restartSent'));
    _restartTimer?.cancel();
    _restartTimer = Timer(_restartWait, () {
      restartPending = false;
      notifyListeners();
    });
    _cancelResult();
    notifyListeners();
  }

  void _onRestartRequested() {
    if (isBot || room == null) return;
    _cancelResult();
    _ui.add(const UiEvent(UiKind.restartRequested));
    audio.sfx('message');
    _incomingTimer?.cancel();
    _incomingTimer = Timer(_restartWait, () => respondRestart(false)); // no answer = decline
  }

  void respondRestart(bool accept) {
    _incomingTimer?.cancel();
    net.emit('restart_response', {'accept': accept});
    _ui.add(const UiEvent(UiKind.hideRestartRequest));
  }

  void _onRestartDeclined() {
    restartPending = false;
    _restartTimer?.cancel();
    _ui.add(const UiEvent(UiKind.toastError, 'restartDeclined'));
    notifyListeners();
  }

  void _clearRestart() {
    restartPending = false;
    _restartTimer?.cancel();
    _incomingTimer?.cancel();
    _ui.add(const UiEvent(UiKind.hideRestartRequest));
  }

  /// The "Play again" button of the result dialog.
  void playAgain() {
    if (isBot) {
      restartBot();
    } else if (!restartPending) {
      sendRestartRequest();
    }
  }

  // ---------- leave ----------
  void leave() {
    if (!isBot) net.emit('leave_game');
    _botTimer?.cancel();
    _botTimer = null;
    _clearRestart();
    _cancelResult();
    mode = GameMode.online;
    room = null;
    myRole = null;
    started = false;
    winner = null;
    players = 0;
    board = List.filled(9, '');
    line = const [];
    inGameScreen = false;
    _ui.add(const UiEvent(UiKind.left));
    notifyListeners();
  }

  @override
  void dispose() {
    _botTimer?.cancel();
    _resultTimer?.cancel();
    _restartTimer?.cancel();
    _incomingTimer?.cancel();
    net.removeListener(notifyListeners);
    _ui.close();
    super.dispose();
  }
}
