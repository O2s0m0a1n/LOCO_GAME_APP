import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// User preferences, saved on the phone (theme, language, sound, server).
class Settings extends ChangeNotifier {
  Settings._(this._p);

  final SharedPreferences _p;

  ThemeMode themeMode = ThemeMode.system;
  String lang = 'ar';
  bool musicWanted = true;
  bool muted = false;
  double volume = 0.4;
  bool sfxOn = true;
  String serverUrl = kDefaultServerUrl;

  static Future<Settings> load() async {
    final s = Settings._(await SharedPreferences.getInstance());
    s._read();
    return s;
  }

  void _read() {
    final theme = _p.getString('theme');
    themeMode = theme == 'dark'
        ? ThemeMode.dark
        : theme == 'light'
            ? ThemeMode.light
            : ThemeMode.system;
    final device = ui.PlatformDispatcher.instance.locale.languageCode;
    final savedLang = _p.getString('lang');
    lang = (savedLang == 'ar' || savedLang == 'en') ? savedLang! : (device == 'ar' ? 'ar' : 'en');
    musicWanted = _p.getBool('music') ?? true;
    muted = _p.getBool('muted') ?? false;
    final v = _p.getDouble('volume') ?? 0.4;
    volume = v < 0 ? 0.0 : (v > 1 ? 1.0 : v);
    sfxOn = _p.getBool('sfx') ?? true;
    serverUrl = _p.getString('server') ?? kDefaultServerUrl;
  }

  bool get serverConfigured =>
      serverUrl.isNotEmpty && !serverUrl.toUpperCase().contains('YOUR-APP-NAME');

  Locale get locale => Locale(lang);

  void setTheme(ThemeMode m) {
    themeMode = m;
    _p.setString('theme', m == ThemeMode.dark ? 'dark' : m == ThemeMode.light ? 'light' : 'system');
    notifyListeners();
  }

  void setLang(String l) {
    lang = l;
    _p.setString('lang', l);
    notifyListeners();
  }

  void setMusicWanted(bool v) {
    musicWanted = v;
    _p.setBool('music', v);
    notifyListeners();
  }

  void setMuted(bool v) {
    muted = v;
    if (!v && volume == 0) volume = 0.4;
    _p.setBool('muted', v);
    _p.setDouble('volume', volume);
    notifyListeners();
  }

  void setVolume(double v) {
    volume = v < 0 ? 0.0 : (v > 1 ? 1.0 : v);
    if (volume > 0) muted = false;
    _p.setDouble('volume', volume);
    _p.setBool('muted', muted);
    notifyListeners();
  }

  void setSfx(bool v) {
    sfxOn = v;
    _p.setBool('sfx', v);
    notifyListeners();
  }

  /// Normalises what the user typed: trims, adds https://, removes trailing slashes.
  void setServerUrl(String raw) {
    var u = raw.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (u.isNotEmpty && !u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    serverUrl = u;
    _p.setString('server', u);
    notifyListeners();
  }
}
