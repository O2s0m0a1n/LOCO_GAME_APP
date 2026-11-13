import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'settings.dart';

/// Background music + short sound effects. Everything is optional and
/// follows the settings (music on/off, mute, volume, effects on/off).
class AudioService {
  AudioService(this.settings) {
    settings.addListener(_applyVolume);
  }

  final Settings settings;

  AudioPlayer? _music;
  final Map<String, AudioPlayer> _sfx = {};
  final ValueNotifier<bool> playing = ValueNotifier(false);
  final Set<String> _holds = {}; // reasons the music is paused (background, call)
  bool _started = false;

  static const _sfxFiles = <String, (String, double)>{
    'click': ('audio/click.mp3', 1.0),
    'move': ('audio/click.mp3', 1.25),
    'win': ('audio/win.mp3', 1.0),
    'draw': ('audio/click.mp3', 0.7),
    'message': ('audio/message.mp3', 1.0),
  };

  double get _musicVolume => settings.muted ? 0 : settings.volume;

  void _applyVolume() {
    _music?.setVolume(_musicVolume);
  }

  /// Starts the music if the user wants it (called after the first tap).
  Future<void> startIfWanted() async {
    if (_started) return;
    _started = true;
    if (settings.musicWanted && _holds.isEmpty) await _play();
  }

  Future<void> _play() async {
    try {
      var p = _music;
      if (p == null) {
        p = AudioPlayer();
        await p.setReleaseMode(ReleaseMode.loop);
        p.onPlayerStateChanged.listen((s) => playing.value = s == PlayerState.playing);
        _music = p;
      }
      await p.setVolume(_musicVolume);
      if (p.state == PlayerState.paused) {
        await p.resume();
      } else if (p.state != PlayerState.playing) {
        await p.play(AssetSource('audio/background.mp3'), volume: _musicVolume);
      }
    } catch (e) {
      debugPrint('music error: $e');
    }
  }

  Future<void> toggleMusic() async {
    if (playing.value) {
      settings.setMusicWanted(false);
      await _music?.pause();
    } else {
      settings.setMusicWanted(true);
      _holds.remove('background');
      await _play();
    }
  }

  /// Pause the music for a reason (app in background, voice call) and resume later.
  void hold(String reason) {
    _holds.add(reason);
    _music?.pause();
  }

  void release(String reason) {
    _holds.remove(reason);
    if (_started && _holds.isEmpty && settings.musicWanted) _play();
  }

  Future<void> sfx(String name) async {
    final def = _sfxFiles[name];
    if (def == null || !settings.sfxOn || settings.muted || settings.volume == 0) return;
    try {
      var p = _sfx[name];
      if (p == null) {
        p = AudioPlayer();
        await p.setPlayerMode(PlayerMode.lowLatency);
        _sfx[name] = p;
      }
      await p.stop();
      final boosted = settings.volume * 1.5;
      await p.setVolume(boosted > 1.0 ? 1.0 : boosted);
      await p.setPlaybackRate(def.$2);
      await p.play(AssetSource(def.$1));
    } catch (e) {
      debugPrint('sfx error: $e');
    }
  }

  void dispose() {
    settings.removeListener(_applyVolume);
    _music?.dispose();
    for (final p in _sfx.values) {
      p.dispose();
    }
  }
}
