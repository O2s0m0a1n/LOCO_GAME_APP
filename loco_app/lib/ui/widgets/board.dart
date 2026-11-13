import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../game/game_controller.dart';
import '../../theme.dart';
import 'logo.dart';

/// The 3 x 3 board. Always left-to-right so both players see the same layout,
/// whatever the app language is.
class BoardView extends StatelessWidget {
  const BoardView({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.watch<GameController>();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: AspectRatio(
            aspectRatio: 1,
            child: GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < 9; i++)
                  _Cell(
                    index: i,
                    value: g.board[i],
                    enabled: g.canPlay && g.board[i].isEmpty,
                    win: g.line.contains(i),
                    onTap: () => g.tapCell(i),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.index, required this.value, required this.enabled, required this.win, required this.onTap});

  final int index;
  final String value;
  final bool enabled;
  final bool win;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    return Semantics(
      button: true,
      label: '${index + 1} $value',
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: LC.cell(context),
            borderRadius: radius,
            border: Border.all(color: win ? LC.blue : LC.border(context), width: win ? 2.5 : 1),
            boxShadow: win ? const [BoxShadow(color: Color(0x5938BDF8), blurRadius: 16)] : null,
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: enabled ? onTap : null,
            child: Center(
              child: FractionallySizedBox(
                widthFactor: 0.58,
                heightFactor: 0.58,
                child: value.isEmpty
                    ? const SizedBox.shrink()
                    : TweenAnimationBuilder<double>(
                        // a new key each time the cell changes => the "pop" plays once per move
                        key: ValueKey('$index$value'),
                        tween: Tween(begin: 0.3, end: 1.0),
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutBack,
                        builder: (_, s, child) => Transform.scale(
                          scale: s,
                          child: Opacity(opacity: s > 1 ? 1 : s, child: child),
                        ),
                        child: CustomPaint(painter: value == 'X' ? _XPainter() : _OPainter()),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _XPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTRB(size.width * 0.12, size.height * 0.12, size.width * 0.88, size.height * 0.88);
    LocoPaint.x(canvas, r, size.width * 0.2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _OPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.2;
    LocoPaint.ring(canvas, size.center(Offset.zero), size.width / 2 - stroke / 2, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
