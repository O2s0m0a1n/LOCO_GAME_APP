import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/audio_service.dart';
import '../services/socket_service.dart';
import 'game_controller.dart';

enum VoiceState { idle, calling, incoming, connecting, connected }

/// Optional voice chat between the two players (WebRTC).
/// Socket.IO is used for signaling only; the audio goes directly between phones
/// (or through the TURN relay configured on the server).
/// The game never depends on this class: if anything fails, play and chat continue.
class VoiceController extends ChangeNotifier {
  VoiceController(this.net, this.audio, this.game) {
    net.on('voice_incoming', (_) => _onIncoming());
    net.on('voice_accepted', (_) => _onAccepted());
    net.on('voice_offer', _onOffer);
    net.on('voice_answer', _onAnswer);
    net.on('voice_ice', _onIce);
    net.on('voice_rejected', (_) {
      if (state == VoiceState.idle) return;
      _ui.add(const UiEvent(UiKind.toast, 'voiceRejectedMsg'));
      reset();
    });
    net.on('voice_ended', (_) {
      if (state == VoiceState.idle) return;
      _ui.add(const UiEvent(UiKind.toast, 'voiceEnded'));
      reset();
    });
    net.on('disconnect', (_) {
      if (state != VoiceState.idle) reset();
    });
    game.addListener(_onGame);
  }

  static const _ringTimeout = Duration(seconds: 45);
  static const _disconnectGrace = Duration(seconds: 8);

  final SocketService net;
  final AudioService audio;
  final GameController game;

  final StreamController<UiEvent> _ui = StreamController<UiEvent>.broadcast();
  Stream<UiEvent> get ui => _ui.stream;

  VoiceState state = VoiceState.idle;
  bool micMuted = false;
  bool spkMuted = false;
  bool reconnecting = false;

  bool _isCaller = false;
  bool _hasTurn = true;
  int _token = 0; // bumps on every reset: cancels async work still in flight
  RTCPeerConnection? _pc;
  MediaStream? _local;
  MediaStream? _remote;
  final List<Map<String, dynamic>> _pendingIce = [];
  bool _remoteSet = false;
  Timer? _ringTimer;
  Timer? _discTimer;

  bool get canCall => game.started && !game.isBot && net.connected;
  bool get inCall =>
      state == VoiceState.calling || state == VoiceState.connecting || state == VoiceState.connected;

  void _onGame() {
    // the opponent left (or we went back to the lobby): close everything
    if (!(game.started && !game.isBot) && state != VoiceState.idle) {
      reset();
    } else {
      notifyListeners();
    }
  }

  // ---------- microphone (asked only when the player starts or accepts a call) ----------
  Future<MediaStream?> _getMic() async {
    try {
      return await navigator.mediaDevices.getUserMedia({
        'audio': {'echoCancellation': true, 'noiseSuppression': true, 'autoGainControl': true},
        'video': false,
      });
    } catch (e) {
      final s = e.toString().toLowerCase();
      final key = s.contains('notfound') || s.contains('not found')
          ? 'voiceMicMissing'
          : (s.contains('perm') || s.contains('denied') || s.contains('notallowed'))
              ? 'voiceMicDenied'
              : 'voiceFailed';
      _ui.add(UiEvent(UiKind.toastError, key));
      return null;
    }
  }

  void _applyTracks() {
    for (final t in _local?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !micMuted;
    }
    for (final t in _remote?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !spkMuted;
    }
  }

  void toggleMic() {
    micMuted = !micMuted;
    _applyTracks();
    notifyListeners();
  }

  void toggleSpeaker() {
    spkMuted = !spkMuted;
    _applyTracks();
    notifyListeners();
  }

  // ---------- ICE servers come from the server (STUN / TURN are configured there) ----------
  Future<List<Map<String, dynamic>>> _getIceServers() {
    final c = Completer<List<Map<String, dynamic>>>();
    const fallback = <Map<String, dynamic>>[
      {'urls': ['stun:stun.l.google.com:19302']},
    ];
    final timer = Timer(const Duration(seconds: 9), () {
      if (!c.isCompleted) c.complete(fallback);
    });
    net.emitAck('voice_config', {}, (res) {
      timer.cancel();
      if (c.isCompleted) return;
      _hasTurn = res['hasTurn'] == true;
      final list = res['iceServers'];
      if (res['ok'] == true && list is List) {
        c.complete([for (final e in list) if (e is Map) Map<String, dynamic>.from(e)]);
      } else {
        c.complete(fallback);
      }
    });
    return c.future;
  }

  // ---------- caller ----------
  Future<void> startCall() async {
    if (state != VoiceState.idle || !canCall) return;
    final my = ++_token;
    _isCaller = true;
    state = VoiceState.calling;
    notifyListeners();

    final s = await _getMic();
    if (my != _token) {
      _stop(s);
      return;
    }
    if (s == null) {
      reset();
      return;
    }
    _local = s;
    _applyTracks();
    net.emit('voice_invite');
    audio.hold('call');

    _ringTimer = Timer(_ringTimeout, () {
      if (state == VoiceState.calling) {
        _ui.add(const UiEvent(UiKind.toast, 'voiceNoAnswer'));
        net.emit('voice_end');
        reset();
      }
    });
    notifyListeners();
  }

  Future<void> _onAccepted() async {
    if (state != VoiceState.calling || _local == null) return;
    _ringTimer?.cancel();
    final my = _token;
    state = VoiceState.connecting;
    notifyListeners();

    final ice = await _getIceServers();
    if (my != _token || state != VoiceState.connecting) return;

    try {
      await _createPeer(ice);
      final offer = await _pc!.createOffer({'offerToReceiveAudio': 1});
      await _pc!.setLocalDescription(offer);
      net.emit('voice_offer', {
        'sdp': {'type': offer.type, 'sdp': offer.sdp},
      });
    } catch (e) {
      _fail('voiceFailed');
    }
  }

  Future<void> _onAnswer(dynamic data) async {
    final pc = _pc;
    final sdp = SocketService.asMap(data)['sdp'];
    if (pc == null || !_isCaller || sdp is! Map) return;
    try {
      await pc.setRemoteDescription(RTCSessionDescription(sdp['sdp']?.toString(), sdp['type']?.toString()));
      _remoteSet = true;
      await _flushIce();
    } catch (e) {
      _fail('voiceFailed');
    }
  }

  // ---------- callee ----------
  void _onIncoming() {
    if (state != VoiceState.idle) {
      net.emit('voice_reject');
      return;
    }
    state = VoiceState.incoming;
    notifyListeners();
  }

  Future<void> acceptCall() async {
    if (state != VoiceState.incoming) return;
    final my = ++_token;
    _isCaller = false;
    state = VoiceState.connecting;
    notifyListeners();

    final s = await _getMic();
    if (my != _token) {
      _stop(s);
      return;
    }
    if (s == null) {
      net.emit('voice_reject');
      reset();
      return;
    }
    _local = s;
    _applyTracks();
    audio.hold('call');

    final ice = await _getIceServers();
    if (my != _token || state != VoiceState.connecting) return;

    try {
      await _createPeer(ice); // ready to receive the offer BEFORE we tell the caller to send it
      net.emit('voice_accept');
    } catch (e) {
      _fail('voiceFailed');
    }
  }

  void rejectCall() {
    if (state != VoiceState.incoming) return;
    net.emit('voice_reject');
    reset();
  }

  Future<void> _onOffer(dynamic data) async {
    final pc = _pc;
    final sdp = SocketService.asMap(data)['sdp'];
    if (pc == null || _isCaller || sdp is! Map) return;
    try {
      await pc.setRemoteDescription(RTCSessionDescription(sdp['sdp']?.toString(), sdp['type']?.toString()));
      _remoteSet = true;
      await _flushIce();
      final answer = await pc.createAnswer({'offerToReceiveAudio': 1});
      await pc.setLocalDescription(answer);
      net.emit('voice_answer', {
        'sdp': {'type': answer.type, 'sdp': answer.sdp},
      });
    } catch (e) {
      _fail('voiceFailed');
    }
  }

  // ---------- peer connection ----------
  Future<void> _createPeer(List<Map<String, dynamic>> ice) async {
    final pc = await createPeerConnection({
      'iceServers': ice,
      'sdpSemantics': 'unified-plan',
    });
    _pc = pc;

    for (final t in _local!.getAudioTracks()) {
      await pc.addTrack(t, _local!);
    }

    pc.onIceCandidate = (RTCIceCandidate c) {
      if (c.candidate == null) return;
      net.emit('voice_ice', {
        'candidate': {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex},
      });
    };

    pc.onTrack = (RTCTrackEvent e) {
      if (e.streams.isNotEmpty) _remote = e.streams.first;
      _applyTracks();
      try {
        Helper.setSpeakerphoneOn(true); // loudspeaker, like a normal voice chat
      } catch (_) {}
    };

    pc.onConnectionState = (RTCPeerConnectionState s) {
      if (_pc == null) return;
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _discTimer?.cancel();
        reconnecting = false;
        state = VoiceState.connected;
        notifyListeners();
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        reconnecting = true;
        notifyListeners();
        _discTimer?.cancel();
        _discTimer = Timer(_disconnectGrace, () {
          if (_pc != null && state != VoiceState.connected) _fail('voiceFailed');
        });
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _fail('voiceFailed');
      }
    };
  }

  Future<void> _onIce(dynamic data) async {
    final pc = _pc;
    final cand = SocketService.asMap(data)['candidate'];
    if (pc == null || cand is! Map) return;
    final c = Map<String, dynamic>.from(cand);
    if (!_remoteSet) {
      _pendingIce.add(c);
      return;
    }
    await _addCandidate(pc, c);
  }

  Future<void> _addCandidate(RTCPeerConnection pc, Map<String, dynamic> c) async {
    try {
      await pc.addCandidate(RTCIceCandidate(
        c['candidate']?.toString(),
        c['sdpMid']?.toString(),
        (c['sdpMLineIndex'] as num?)?.toInt(),
      ));
    } catch (_) {
      // a stale candidate: ignore
    }
  }

  Future<void> _flushIce() async {
    final pc = _pc;
    if (pc == null) return;
    final queued = List.of(_pendingIce);
    _pendingIce.clear();
    for (final c in queued) {
      await _addCandidate(pc, c);
    }
  }

  // ---------- end / cleanup (microphone off, connection closed) ----------
  void endCall() {
    net.emit('voice_end');
    reset();
  }

  void _fail(String key) {
    final k = (key == 'voiceFailed' && !_hasTurn) ? 'voiceNeedTurn' : key;
    _ui.add(UiEvent(UiKind.toastError, k));
    net.emit('voice_end');
    reset();
  }

  void _stop(MediaStream? s) {
    if (s == null) return;
    for (final t in s.getTracks()) {
      try {
        t.stop();
      } catch (_) {}
    }
    try {
      s.dispose();
    } catch (_) {}
  }

  void reset() {
    _token++;
    _ringTimer?.cancel();
    _discTimer?.cancel();

    final pc = _pc;
    _pc = null;
    if (pc != null) {
      pc.onIceCandidate = null;
      pc.onTrack = null;
      pc.onConnectionState = null;
      try {
        pc.close();
      } catch (_) {}
    }
    _stop(_local);
    _local = null;
    _remote = null;

    _pendingIce.clear();
    _remoteSet = false;
    reconnecting = false;
    micMuted = false;
    spkMuted = false;
    _isCaller = false;
    final wasActive = state != VoiceState.idle;
    state = VoiceState.idle;
    if (wasActive) audio.release('call');
    notifyListeners();
  }

  @override
  void dispose() {
    game.removeListener(_onGame);
    reset();
    _ui.close();
    super.dispose();
  }
}
