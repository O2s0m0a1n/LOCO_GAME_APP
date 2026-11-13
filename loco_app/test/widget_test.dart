import 'package:flutter_test/flutter_test.dart';
import 'package:loco/game/bot.dart';

void main() {
  test('the hard computer never loses, whether it plays O or X', () {
    for (final botSym in ['O', 'X']) {
      final human = botSym == 'O' ? 'X' : 'O';
      var humanWins = 0;
      var games = 0;

      void play(List<String> b, String turn) {
        final r = Bot.result(b);
        if (r != null) {
          games++;
          if (r.winner == human) humanWins++;
          return;
        }
        if (turn == botSym) {
          final m = Bot.bestMove(b, 'hard', botSym, human);
          b[m] = botSym;
          play(b, human);
          b[m] = '';
        } else {
          for (var i = 0; i < 9; i++) {
            if (b[i].isEmpty) {
              b[i] = human;
              play(b, botSym);
              b[i] = '';
            }
          }
        }
      }

      play(List.filled(9, ''), 'X');
      expect(games, greaterThan(0));
      expect(humanWins, 0, reason: 'the human won against the hard bot playing $botSym');
    }
  });

  test('medium takes a winning move and blocks the opponent', () {
    expect(Bot.bestMove(['O', 'O', '', 'X', 'X', '', '', '', ''], 'medium', 'O', 'X'), 2);
    expect(Bot.bestMove(['X', 'X', '', 'O', '', '', '', '', ''], 'medium', 'O', 'X'), 2);
  });

  test('every level only plays on empty cells', () {
    final board = ['X', 'O', 'X', 'O', 'X', '', 'O', 'X', 'O'];
    for (final level in ['easy', 'medium', 'hard']) {
      expect(Bot.bestMove(board, level, 'O', 'X'), 5);
    }
    expect(Bot.bestMove(['X', 'O', 'X', 'X', 'O', 'O', 'O', 'X', 'X'], 'hard', 'O', 'X'), -1);
  });
}
