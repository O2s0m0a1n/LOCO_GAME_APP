import 'dart:math';

/// The computer opponent (same logic as the website's bot.js).
/// easy = random, medium = wins / blocks / sensible, hard = unbeatable.
class Bot {
  static const lines = <List<int>>[
    [0, 1, 2], [3, 4, 5], [6, 7, 8],
    [0, 3, 6], [1, 4, 7], [2, 5, 8],
    [0, 4, 8], [2, 4, 6],
  ];

  static final Random _rnd = Random();

  /// Returns the winner ('X' / 'O' / 'draw') and the winning line, or null if the game goes on.
  static ({String winner, List<int> line})? result(List<String> b) {
    for (final l in lines) {
      if (b[l[0]].isNotEmpty && b[l[0]] == b[l[1]] && b[l[0]] == b[l[2]]) {
        return (winner: b[l[0]], line: l);
      }
    }
    if (!b.contains('')) return (winner: 'draw', line: const <int>[]);
    return null;
  }

  static List<int> _empty(List<String> b) =>
      [for (var i = 0; i < 9; i++) if (b[i].isEmpty) i];

  static int _pick(List<int> l) => l[_rnd.nextInt(l.length)];

  static int _findWin(List<String> b, String who) {
    for (final i in _empty(b)) {
      b[i] = who;
      final r = result(b);
      b[i] = '';
      if (r != null && r.winner == who) return i;
    }
    return -1;
  }

  static int _minimax(List<String> b, String turn, String me, String opp, int depth) {
    final r = result(b);
    if (r != null) {
      return r.winner == me ? 10 - depth : (r.winner == opp ? depth - 10 : 0);
    }
    var best = turn == me ? -1000 : 1000;
    for (final i in _empty(b)) {
      b[i] = turn;
      final score = _minimax(b, turn == me ? opp : me, me, opp, depth + 1);
      b[i] = '';
      best = turn == me ? max(best, score) : min(best, score);
    }
    return best;
  }

  static int _hard(List<String> b, String me, String opp) {
    final cells = _empty(b);
    if (cells.length == 9) return _pick(const [0, 2, 4, 6, 8]);
    var bestScore = -1000;
    var bestCells = <int>[];
    for (final i in cells) {
      b[i] = me;
      final score = _minimax(b, opp, me, opp, 1);
      b[i] = '';
      if (score > bestScore) {
        bestScore = score;
        bestCells = [i];
      } else if (score == bestScore) {
        bestCells.add(i);
      }
    }
    return _pick(bestCells);
  }

  static int _medium(List<String> b, String me, String opp) {
    final w = _findWin(b, me);
    if (w != -1) return w;
    final block = _findWin(b, opp);
    if (block != -1) return block;
    if (b[4].isEmpty) return 4;
    final corners = [0, 2, 6, 8].where((i) => b[i].isEmpty).toList();
    if (corners.isNotEmpty && _rnd.nextDouble() < 0.7) return _pick(corners);
    return _pick(_empty(b));
  }

  /// The cell the bot wants to play, or -1 if the board is full.
  static int bestMove(List<String> board, String level, String me, String opp) {
    final b = List<String>.of(board);
    if (_empty(b).isEmpty) return -1;
    if (level == 'hard') return _hard(b, me, opp);
    if (level == 'medium') return _medium(b, me, opp);
    return _pick(_empty(b));
  }
}
