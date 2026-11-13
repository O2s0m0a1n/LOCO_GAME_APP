import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../game/game_controller.dart';
import '../i18n.dart';
import '../services/settings.dart';
import '../theme.dart';
import 'dialogs.dart';
import 'widgets/common.dart';
import 'widgets/logo.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  /// Online play needs the server address first.
  bool _ensureServer() {
    if (context.read<Settings>().serverConfigured) return true;
    showServerDialog(context);
    return false;
  }

  void _create() {
    if (!_ensureServer()) return;
    final code = context.read<GameController>().createRoom();
    if (code != null) _code.text = code;
  }

  void _join() {
    if (!_ensureServer()) return;
    context.read<GameController>().joinRoom(_code.text);
  }

  void _copy() {
    final code = _code.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.tr('err_nothing_copy'))));
      return;
    }
    copyToClipboard(context, code);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Settings>();
    final host = Uri.tryParse(s.serverUrl)?.host ?? s.serverUrl;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: LocoCard(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const LocoLockup(width: 300),
              const SizedBox(height: 18),
              Text(context.tr('welcome'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(context.tr('welcomeSub'), textAlign: TextAlign.center, style: TextStyle(color: LC.soft(context))),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: GradientButton(label: context.tr('createRoom'), icon: Icons.add_circle_rounded, onPressed: _create),
              ),
              const SizedBox(height: 14),
              const OrDivider(),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _code,
                    textAlign: TextAlign.center,
                    textCapitalization: TextCapitalization.characters,
                    textDirection: TextDirection.ltr,
                    autocorrect: false,
                    maxLength: 12,
                    inputFormatters: [RoomCodeFormatter()],
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 6),
                    onSubmitted: (_) => _join(),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: context.tr('roomPlaceholder'),
                      hintStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w400, letterSpacing: 0),
                      filled: true,
                      fillColor: LC.card2(context),
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: context.tr('copyCode'),
                  onPressed: _copy,
                  icon: const Icon(Icons.copy_rounded),
                ),
              ]),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlineButtonX(label: context.tr('joinRoom'), icon: Icons.login_rounded, onPressed: _join),
              ),
              const SizedBox(height: 14),
              const OrDivider(),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlineButtonX(
                  label: context.tr('playBot'),
                  icon: Icons.smart_toy_rounded,
                  color: LC.pink,
                  onPressed: () => showBotPicker(context),
                ),
              ),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const ConnBadge(),
                TextButton.icon(
                  onPressed: () => showServerDialog(context),
                  icon: const Icon(Icons.dns_rounded, size: 16),
                  label: Text(
                    s.serverConfigured ? host : context.tr('serverNotSet'),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
