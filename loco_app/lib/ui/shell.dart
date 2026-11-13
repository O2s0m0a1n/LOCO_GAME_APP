import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/chat_controller.dart';
import '../game/game_controller.dart';
import '../game/voice_controller.dart';
import '../i18n.dart';
import '../services/audio_service.dart';
import '../services/settings.dart';
import '../theme.dart';
import 'dialogs.dart';
import 'game_screen.dart';
import 'lobby_screen.dart';
import 'widgets/common.dart';
import 'widgets/logo.dart';

/// The one screen of the app: header + (lobby | game) + footer.
/// It also turns controller events into dialogs and notifications.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final List<StreamSubscription<dynamic>> _subs = [];
  VoiceController? _voice;
  bool _callDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _subs.add(context.read<GameController>().ui.listen(_onUi));
      _subs.add(context.read<ChatController>().incoming.listen(_onChat));
      _voice = context.read<VoiceController>();
      _subs.add(_voice!.ui.listen(_onUi));
      _voice!.addListener(_onVoice);
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _voice?.removeListener(_onVoice);
    super.dispose();
  }

  void _snack(String message, {bool error = false, SnackBarAction? action}) {
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(message),
      action: action,
      backgroundColor: error ? const Color(0xFF7F1D1D) : null,
      duration: const Duration(seconds: 3),
    ));
  }

  void _onUi(UiEvent e) {
    if (!mounted) return;
    switch (e.kind) {
      case UiKind.toast:
        _snack(context.tr(e.key!));
      case UiKind.toastError:
        _snack(context.tr(e.key!), error: true);
      case UiKind.serverError:
        final k = 'err_${e.key}';
        _snack(Strings.has(context.lang, k) ? context.tr(k) : (e.extra ?? context.tr('err_generic')), error: true);
      case UiKind.result:
        showDialog<void>(context: context, builder: (_) => ResultDialog(kind: e.key!));
      case UiKind.restartRequested:
        showDialog<void>(context: context, barrierDismissible: false, builder: (_) => const RestartRequestDialog());
      case UiKind.hideRestartRequest:
      case UiKind.hideResult:
      case UiKind.left:
        break;
    }
  }

  /// A message from the opponent arrived while the chat is closed: light notification.
  void _onChat(ChatMsg m) {
    if (!mounted) return;
    final preview = m.text.length > 40 ? '${m.text.substring(0, 40)}…' : m.text;
    _snack(
      '${context.tr('newMessage')} — $preview',
      action: SnackBarAction(label: context.tr('open'), onPressed: () => showChatSheet(context)),
    );
  }

  void _onVoice() {
    final v = _voice;
    if (!mounted || v == null) return;
    if (v.state == VoiceState.incoming && !_callDialogOpen) {
      _callDialogOpen = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const IncomingCallDialog(),
      ).whenComplete(() => _callDialogOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.watch<GameController>();

    return PopScope(
      // In the lobby the back button leaves the app; in a game it asks first.
      canPop: !g.inGameScreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) leaveGame(context, g);
      },
      child: Scaffold(
        body: LocoBackground(
          child: SafeArea(
            child: Column(children: [
              const _HeaderBar(),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: g.inGameScreen
                      ? const GameScreen(key: ValueKey('game'))
                      : const LobbyScreen(key: ValueKey('lobby')),
                ),
              ),
              const DesignerFooter(),
            ]),
          ),
        ),
      ),
    );
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar();

  @override
  Widget build(BuildContext context) {
    final inGame = context.select<GameController, bool>((g) => g.inGameScreen);
    final s = context.watch<Settings>();
    final dark = LC.isDark(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(children: [
        // the big logo is on the lobby card, so the small one only shows during a game
        Opacity(
          opacity: inGame ? 1 : 0,
          child: const Row(children: [
            LocoMark(size: 32),
            SizedBox(width: 8),
            LocoWordmark(height: 18),
          ]),
        ),
        const Spacer(),
        RoundIconButton(
          icon: (s.muted || s.volume == 0) ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          tooltip: context.tr('sound'),
          onPressed: () => showSoundSheet(context),
        ),
        const SizedBox(width: 8),
        RoundIconButton(
          icon: null,
          label: s.lang == 'ar' ? 'EN' : 'عربي',
          tooltip: context.tr('switchLang'),
          onPressed: () => s.setLang(s.lang == 'ar' ? 'en' : 'ar'),
        ),
        const SizedBox(width: 8),
        RoundIconButton(
          icon: dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          tooltip: context.tr('toggleTheme'),
          onPressed: () => s.setTheme(dark ? ThemeMode.light : ThemeMode.dark),
        ),
      ]),
    );
  }
}
