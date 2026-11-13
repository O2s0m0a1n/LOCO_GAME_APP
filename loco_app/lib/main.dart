import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'game/chat_controller.dart';
import 'game/game_controller.dart';
import 'game/voice_controller.dart';
import 'services/audio_service.dart';
import 'services/settings.dart';
import 'services/socket_service.dart';
import 'theme.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  final settings = await Settings.load();
  runApp(LocoApp(settings: settings));
}

class LocoApp extends StatefulWidget {
  const LocoApp({super.key, required this.settings});
  final Settings settings;

  @override
  State<LocoApp> createState() => _LocoAppState();
}

class _LocoAppState extends State<LocoApp> with WidgetsBindingObserver {
  late final SocketService net;
  late final AudioService audio;
  late final GameController game;
  late final ChatController chat;
  late final VoiceController voice;
  String? _lastUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    net = SocketService();
    audio = AudioService(widget.settings);
    game = GameController(net, audio);
    chat = ChatController(net, audio, game);
    voice = VoiceController(net, audio, game);
    widget.settings.addListener(_connect);
    _connect();
  }

  /// Connects (or reconnects when the server address changed).
  void _connect() {
    final s = widget.settings;
    if (s.serverConfigured && s.serverUrl != _lastUrl) {
      _lastUrl = s.serverUrl;
      net.connect(s.serverUrl);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      audio.release('background');
      final s = widget.settings;
      if (s.serverConfigured) net.connect(s.serverUrl); // wake the connection up again
    } else if (state == AppLifecycleState.paused) {
      audio.hold('background'); // no music while the app is in the background
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.settings.removeListener(_connect);
    voice.dispose();
    chat.dispose();
    game.dispose();
    audio.dispose();
    net.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<Settings>.value(value: widget.settings),
        ChangeNotifierProvider<SocketService>.value(value: net),
        Provider<AudioService>.value(value: audio),
        ChangeNotifierProvider<GameController>.value(value: game),
        ChangeNotifierProvider<ChatController>.value(value: chat),
        ChangeNotifierProvider<VoiceController>.value(value: voice),
      ],
      child: Consumer<Settings>(
        builder: (context, s, _) => Listener(
          // browsers and phones only allow sound after a touch: start the music on the first one
          onPointerDown: (_) => audio.startIfWanted(),
          child: MaterialApp(
            title: 'LOCO',
            debugShowCheckedModeBanner: false,
            theme: LC.theme(Brightness.light),
            darkTheme: LC.theme(Brightness.dark),
            themeMode: s.themeMode,
            locale: s.locale,
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const Shell(),
          ),
        ),
      ),
    );
  }
}
