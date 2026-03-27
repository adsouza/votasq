import 'package:word_count/word_count.dart';

/// Returns `true` when [text] is at least 20 characters long and contains at
/// least 3 words. Used by both `AddProblemRow` and `ProblemEditTile` to gate
/// form submission.
bool hasEnoughWords(String text) =>
    text.length >= 20 && wordsCount(text.trim()) >= 3;
