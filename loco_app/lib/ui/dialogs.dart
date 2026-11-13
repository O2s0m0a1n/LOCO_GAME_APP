import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/chat_controller.dart';
import '../game/game_controller.dart';
import '../game/voice_controller.dart';
import '../i18n.dart';
import '../services/audio_service.dart';
import '../services/settings.dart';
import '../services/socket_service.dart';
import '../theme.dart';
import 'widgets/common.dart';

RoundedRectangleBorder _shape([double r = 24]) =>
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));

// ---------------------------------------------------------------- confirmations

Future<bool> confirmDialog(BuildContext context, String titleKey, String textKey) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: LC.card(ctx),
      shape: _shape(),
      icon: const Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 44),
      title: Text(ctx.tr(titleKey), textAlign: TextAlign.center),
      content: Text(ctx.tr(textKey), textAlign: TextAlign.center, style: TextStyle(color: LC.soft(ctx))),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: LC.purple),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ctx.tr('confirmYes')),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Back to the lobby; asks first when a game would be lost.
Future<void> leaveGame(BuildContext context, GameController g) async {
  if (g.inActiveGame) {
    final ok = await confirmDialog(
      context,
      'confirmLeaveTitle',
      g.isBot ? 'confirmLeaveText' : 'confirmLeaveOnline',
    );
    if (!ok) return;
  }
  g.leave();
}

/// The Restart button: a running game needs confirmation; online also needs the opponent to accept.
Future<void> restartPressed(BuildContext context, GameController g) async {
  if (g.movesCount == 0) return;
  if (g.winner == null) {
    final ok = await confirmDialog(
      context,
      'confirmRestartTitle',
      g.isBot ? 'confirmRestartText' : 'confirmRestartOnline',
    );
    if (!ok) return;
  }
  if (g.isBot) {
    g.restartBot();
  } else {
    g.sendRestartRequest();
  }
}

// ---------------------------------------------------------------- bot level picker

Future<void> showBotPicker(BuildContext context) {
  final g = context.read<GameController>();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: LC.card(context),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (ctx) {
      Widget level(String id, String title, String desc, IconData icon) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: LC.card2(ctx),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.pop(ctx);
                  g.startBot(id);
                },
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Icon(icon, color: LC.accent(ctx)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(ctx.tr(title), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 2),
                        Text(ctx.tr(desc), style: TextStyle(color: LC.soft(ctx), fontSize: 13)),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          );

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.smart_toy_rounded, size: 44, color: LC.pink),
            const SizedBox(height: 8),
            Text(ctx.tr('botTitle'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(ctx.tr('botSubtitle'), textAlign: TextAlign.center, style: TextStyle(color: LC.soft(ctx))),
            const SizedBox(height: 16),
            level('easy', 'levelEasy', 'levelEasyDesc', Icons.sentiment_satisfied_alt_rounded),
            level('medium', 'levelMedium', 'levelMediumDesc', Icons.bolt_rounded),
            level('hard', 'levelHard', 'levelHardDesc', Icons.local_fire_department_rounded),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
          ]),
        ),
      );
    },
  );
}

// ---------------------------------------------------------------- result / restart request

class ResultDialog extends StatefulWidget {
  const ResultDialog({super.key, required this.kind});
  final String kind; // win | lose | draw

  @override
  State<ResultDialog> createState() => _ResultDialogState();
}

class _ResultDialogState extends State<ResultDialog> {
  StreamSubscription<UiEvent>? _sub;

  @override
  void initState() {
    super.initState();
    // the game was restarted: close this dialog
    _sub = context.read<GameController>().ui.listen((e) {
      if (e.kind == UiKind.hideResult && mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
        Navigator.pop(context);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.read<GameController>();
    final (emoji, title, text) = switch (widget.kind) {
      'win' => ('🏆', 'winTitle', 'winText'),
      'draw' => ('🤝', 'drawTitle', 'drawText'),
      _ => ('😢', 'loseTitle', 'loseText'),
    };
    return AlertDialog(
      backgroundColor: LC.card(context),
      shape: _shape(),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(emoji, style: const TextStyle(fontSize: 60)),
        const SizedBox(height: 8),
        Text(context.tr(title), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(context.tr(text), textAlign: TextAlign.center, style: TextStyle(color: LC.soft(context))),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: GradientButton(
            label: context.tr('playAgain'),
            icon: Icons.refresh_rounded,
            compact: true,
            onPressed: () {
              Navigator.pop(context);
              g.playAgain();
            },
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlineButtonX(label: context.tr('close'), compact: true, onPressed: () => Navigator.pop(context)),
        ),
      ]),
    );
  }
}

class RestartRequestDialog extends StatefulWidget {
  const RestartRequestDialog({super.key});

  @override
  State<RestartRequestDialog> createState() => _RestartRequestDialogState();
}

class _RestartRequestDialogState extends State<RestartRequestDialog> {
  StreamSubscription<UiEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = context.read<GameController>().ui.listen((e) {
      if (e.kind == UiKind.hideRestartRequest && mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
        Navigator.pop(context);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.read<GameController>();
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: LC.card(context),
        shape: _shape(),
        icon: Icon(Icons.refresh_rounded, size: 44, color: LC.accent(context)),
        title: Text(context.tr('restartIncomingTitle'), textAlign: TextAlign.center),
        content: Text(context.tr('restartIncomingText'),
            textAlign: TextAlign.center, style: TextStyle(color: LC.soft(context))),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => g.respondRestart(false),
            child: Text(context.tr('decline')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
            onPressed: () => g.respondRestart(true),
            child: Text(context.tr('accept')),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- incoming voice call

class IncomingCallDialog extends StatefulWidget {
  const IncomingCallDialog({super.key});

  @override
  State<IncomingCallDialog> createState() => _IncomingCallDialogState();
}

class _IncomingCallDialogState extends State<IncomingCallDialog> {
  late final VoiceController _voice;

  @override
  void initState() {
    super.initState();
    _voice = context.read<VoiceController>();
    _voice.addListener(_check);
  }

  // the caller hung up (or the call ended): close the dialog
  void _check() {
    if (_voice.state != VoiceState.incoming && mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _voice.removeListener(_check);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: LC.card(context),
        shape: _shape(),
        icon: const Icon(Icons.call_received_rounded, size: 46, color: Color(0xFF22C55E)),
        title: Text(context.tr('voiceIncoming'), textAlign: TextAlign.center),
        content: Text(context.tr('voiceIncomingText'),
            textAlign: TextAlign.center, style: TextStyle(color: LC.soft(context))),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            icon: const Icon(Icons.call_end_rounded),
            onPressed: () {
              Navigator.pop(context);
              _voice.rejectCall();
            },
            label: Text(context.tr('voiceReject')),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
            icon: const Icon(Icons.call_rounded),
            onPressed: () {
              Navigator.pop(context);
              _voice.acceptCall();
            },
            label: Text(context.tr('voiceAccept')),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- server address

Future<void> showServerDialog(BuildContext context) {
  final settings = context.read<Settings>();
  final ctrl = TextEditingController(text: settings.serverConfigured ? settings.serverUrl : '');
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: LC.card(ctx),
      shape: _shape(),
      title: Text(ctx.tr('server')),
      content: TextField(
        controller: ctrl,
        keyboardType: TextInputType.url,
        autocorrect: false,
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(hintText: 'https://my-game.onrender.com', helperText: ctx.tr('serverHint'), helperMaxLines: 2),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: LC.purple),
          onPressed: () {
            settings.setServerUrl(ctrl.text);
            Navigator.pop(ctx);
          },
          child: Text(ctx.tr('serverSave')),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------- sound settings

Future<void> showSoundSheet(BuildContext context) {
  final audio = context.read<AudioService>();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: LC.card(context),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (ctx) => SafeArea(
      child: Consumer<Settings>(
        builder: (ctx, s, _) {
          final silent = s.muted || s.volume == 0;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(ctx.tr('sound'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: audio.playing,
                    builder: (_, playing, __) => GradientButton(
                      label: ctx.tr(playing ? 'pauseMusic' : 'playMusic'),
                      icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      compact: true,
                      onPressed: audio.toggleMusic,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlineButtonX(
                    label: ctx.tr(silent ? 'unmute' : 'mute'),
                    icon: silent ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                    compact: true,
                    onPressed: () => s.setMuted(!silent),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(ctx.tr('volume'), style: TextStyle(color: LC.soft(ctx))),
              ),
              Slider(value: s.muted ? 0.0 : s.volume, onChanged: s.setVolume),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: s.sfxOn,
                onChanged: s.setSfx,
                title: Text(ctx.tr('soundEffects')),
              ),
            ]),
          );
        },
      ),
    ),
  );
}

// ---------------------------------------------------------------- chat

Future<void> showChatSheet(BuildContext context) async {
  final chat = context.read<ChatController>();
  chat.setSheetOpen(true);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: LC.card(context),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (_) => const _ChatSheet(),
  );
  chat.setSheetOpen(false);
}

class _ChatSheet extends StatefulWidget {
  const _ChatSheet();

  @override
  State<_ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<_ChatSheet> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  int _lastCount = 0;

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final raw = _text.text;
    if (raw.trim().isEmpty) return;
    final err = context.read<ChatController>().send(raw);
    if (err != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.tr(err))));
      return;
    }
    _text.clear();
  }

  String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    final g = context.read<GameController>();
    final online = context.watch<SocketService>().connected;
    final mq = MediaQuery.of(context);
    final height = math.min(560.0, (mq.size.height - mq.viewInsets.bottom) * 0.85);

    if (chat.messages.length != _lastCount) {
      _lastCount = chat.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SizedBox(
        height: height,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: Row(children: [
              const Icon(Icons.chat_bubble_rounded, size: 20),
              const SizedBox(width: 8),
              Text(context.tr('chat'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              const Spacer(),
              const ConnBadge(),
            ]),
          ),
          Divider(height: 1, color: LC.border(context)),
          Expanded(
            child: chat.messages.isEmpty
                ? Center(child: Text(context.tr('chatEmpty'), style: TextStyle(color: LC.soft(context))))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: chat.messages.length,
                    itemBuilder: (_, i) {
                      final m = chat.messages[i];
                      final mine = m.role == g.myRole;
                      return Align(
                        alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
                          constraints: BoxConstraints(maxWidth: mq.size.width * 0.75),
                          decoration: BoxDecoration(
                            gradient: mine ? LC.gradient : null,
                            color: mine ? null : LC.card2(context),
                            border: mine ? null : Border.all(color: LC.border(context)),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(m.role,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                    color: mine ? Colors.white : (m.role == 'X' ? LC.blue : LC.pink),
                                  )),
                              if (mine) ...[
                                const SizedBox(width: 6),
                                Text(context.tr('you'), style: const TextStyle(fontSize: 11, color: Colors.white70)),
                              ],
                              const SizedBox(width: 10),
                              Text(_time(m.ts),
                                  style: TextStyle(fontSize: 11, color: mine ? Colors.white60 : LC.soft(context))),
                            ]),
                            const SizedBox(height: 2),
                            Text(m.text, style: TextStyle(color: mine ? Colors.white : LC.text(context), fontSize: 15)),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
          Divider(height: 1, color: LC.border(context)),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  enabled: online,
                  maxLength: 200,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: context.tr('chatPlaceholder'),
                    filled: true,
                    fillColor: LC.card2(context),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: LC.purple),
                tooltip: context.tr('send'),
                onPressed: online ? _send : null,
                icon: const Icon(Icons.send_rounded),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
