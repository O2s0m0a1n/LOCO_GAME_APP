import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/chat_controller.dart';
import '../game/game_controller.dart';
import '../i18n.dart';
import '../theme.dart';
import 'dialogs.dart';
import 'widgets/board.dart';
import 'widgets/common.dart';
import 'widgets/voice_bar.dart';

class GameScreen extends StatelessWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.watch<GameController>();

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: LocoCard(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _TopRow(g: g),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _PlayerChip(symbol: 'X', g: g)),
                const SizedBox(width: 10),
                Expanded(child: _PlayerChip(symbol: 'O', g: g)),
              ]),
              const SizedBox(height: 14),
              _Status(g: g),
              if (!g.isBot && !g.started && g.room != null) ...[
                const SizedBox(height: 4),
                OutlineButtonX(
                  label: context.tr('botInstead'),
                  icon: Icons.smart_toy_rounded,
                  color: LC.pink,
                  compact: true,
                  onPressed: () => showBotPicker(context),
                ),
              ],
              const SizedBox(height: 14),
              const BoardView(),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: GradientButton(
                    label: context.tr('restart'),
                    icon: Icons.refresh_rounded,
                    compact: true,
                    onPressed: g.canRestart ? () => restartPressed(context, g) : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlineButtonX(
                    label: context.tr('backToLobby'),
                    icon: Icons.home_rounded,
                    compact: true,
                    onPressed: () => leaveGame(context, g),
                  ),
                ),
              ]),
              if (!g.isBot) ...[
                const SizedBox(height: 10),
                const _ChatButton(),
                const SizedBox(height: 10),
                const VoiceBar(),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _TopRow extends StatelessWidget {
  const _TopRow({required this.g});
  final GameController g;

  @override
  Widget build(BuildContext context) {
    if (g.isBot) {
      return Row(children: [
        Icon(Icons.smart_toy_rounded, color: LC.pink),
        const SizedBox(width: 8),
        Text(context.tr('vsComputer'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const Spacer(),
        Text(context.tr(switch (g.botLevel) { 'easy' => 'levelEasy', 'hard' => 'levelHard', _ => 'levelMedium' }),
            style: TextStyle(color: LC.soft(context))),
      ]);
    }
    return Row(children: [
      Text(context.tr('roomCode'), style: TextStyle(color: LC.soft(context), fontSize: 13)),
      const SizedBox(width: 8),
      Directionality(
        textDirection: TextDirection.ltr,
        child: Text(g.room ?? '',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 4, fontSize: 17, color: LC.accent(context))),
      ),
      IconButton(
        tooltip: context.tr('copyCode'),
        visualDensity: VisualDensity.compact,
        onPressed: g.room == null ? null : () => copyToClipboard(context, g.room!),
        icon: const Icon(Icons.copy_rounded, size: 18),
      ),
      const Spacer(),
      const ConnBadge(),
    ]);
  }
}

class _PlayerChip extends StatelessWidget {
  const _PlayerChip({required this.symbol, required this.g});
  final String symbol;
  final GameController g;

  @override
  Widget build(BuildContext context) {
    final active = g.live && g.turn == symbol;
    final color = symbol == 'X' ? LC.blue : LC.pink;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: LC.card2(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: active ? color : Colors.transparent, width: 1.6),
      ),
      child: Row(children: [
        SizedBox(
          width: 28,
          child: Text(symbol,
              textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(context.tr(g.nameKey(symbol)),
              overflow: TextOverflow.ellipsis, style: TextStyle(color: LC.soft(context), fontSize: 13)),
        ),
      ]),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.g});
  final GameController g;

  @override
  Widget build(BuildContext context) {
    final key = g.statusKey;
    final color = switch (key) {
      'statusWin' => const Color(0xFF22C55E),
      'statusLose' || 'statusDisconnected' => const Color(0xFFEF4444),
      'statusDraw' => const Color(0xFFF59E0B),
      'statusYourTurn' => LC.accent(context),
      _ => LC.text(context),
    };
    return Semantics(
      liveRegion: true,
      child: Text(context.tr(key),
          textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w700)),
    );
  }
}

class _ChatButton extends StatelessWidget {
  const _ChatButton();

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<ChatController>().unread;
    return SizedBox(
      width: double.infinity,
      child: OutlineButtonX(
        label: unread > 0 ? '${context.tr('chat')} ($unread)' : context.tr('chat'),
        icon: Icons.chat_bubble_rounded,
        compact: true,
        onPressed: () => showChatSheet(context),
      ),
    );
  }
}
