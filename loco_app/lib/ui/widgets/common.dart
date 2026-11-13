import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../i18n.dart';
import '../../services/audio_service.dart';
import '../../services/socket_service.dart';
import '../../theme.dart';

/// Soft static glow behind everything (no animation, cheap).
class LocoBackground extends StatelessWidget {
  const LocoBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = LC.isDark(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: LC.bg(context),
        gradient: RadialGradient(
          center: const Alignment(-0.9, -1.1),
          radius: 1.3,
          colors: [
            LC.purple.withValues(alpha: dark ? 0.22 : 0.12),
            Colors.transparent,
          ],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(1.0, 1.1),
            radius: 1.1,
            colors: [
              LC.blue.withValues(alpha: dark ? 0.14 : 0.14),
              Colors.transparent,
            ],
          ),
        ),
        child: child,
      ),
    );
  }
}

class LocoCard extends StatelessWidget {
  const LocoCard({super.key, required this.child, this.padding = const EdgeInsets.all(20)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: LC.card(context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: LC.border(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: LC.isDark(context) ? 0.35 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Main button: brand gradient.
class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, required this.onPressed, this.icon, this.compact = false});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LC.gradient,
            borderRadius: radius,
            boxShadow: const [BoxShadow(color: Color(0x527045D8), blurRadius: 16, offset: Offset(0, 6))],
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: onPressed == null
                ? null
                : () {
                    context.read<AudioService>().sfx('click');
                    onPressed!();
                  },
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: compact ? 12 : 16, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[Icon(icon, color: Colors.white, size: 20), const SizedBox(width: 8)],
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary button: outline.
class OutlineButtonX extends StatelessWidget {
  const OutlineButtonX({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.compact = false,
    this.color,
    this.dashed = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool compact;
  final Color? color;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final c = color ?? LC.purple;
    final radius = BorderRadius.circular(14);
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: onPressed == null
              ? null
              : () {
                  context.read<AudioService>().sfx('click');
                  onPressed!();
                },
          child: Container(
            padding: EdgeInsets.symmetric(vertical: compact ? 11 : 15, horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: c, width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[Icon(icon, color: c, size: 20), const SizedBox(width: 8)],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: LC.text(context), fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Round icon button used in the header.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({super.key, required this.icon, required this.onPressed, this.tooltip, this.label});
  final IconData? icon;
  final String? label;
  final String? tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: LC.card(context),
        shape: StadiumBorder(side: BorderSide(color: LC.border(context))),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 42, minHeight: 42),
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: label != null ? 12 : 0),
                child: label != null
                    ? Text(label!, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: LC.text(context)))
                    : Icon(icon, size: 20, color: LC.text(context)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ConnBadge extends StatelessWidget {
  const ConnBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final link = context.watch<SocketService>().link;
    final color = link == Link.connected
        ? const Color(0xFF22C55E)
        : link == Link.connecting
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);
    final key = link == Link.connected
        ? 'conn_connected'
        : link == Link.connecting
            ? 'conn_connecting'
            : 'conn_disconnected';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(context.tr(key), style: TextStyle(fontSize: 12, color: LC.soft(context))),
      ],
    );
  }
}

class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final line = Expanded(child: Divider(color: LC.border(context), thickness: 1));
    return Row(children: [
      line,
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(context.tr('or'), style: TextStyle(color: LC.soft(context), fontSize: 13)),
      ),
      line,
    ]);
  }
}

class DesignerFooter extends StatelessWidget {
  const DesignerFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 12),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ShaderMask(
          shaderCallback: (r) => const LinearGradient(colors: [LC.purple, LC.pink]).createShader(r),
          child: const Text(
            kDesignerCredit,
            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 4),
          ),
        ),
      ),
    );
  }
}

/// Upper-case + letters/digits only, for room codes.
class RoomCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final t = newValue.text.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    return newValue.copyWith(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
      composing: TextRange.empty,
    );
  }
}

Future<void> copyToClipboard(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(context.tr('copied'))));
}
