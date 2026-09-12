/// Column and count formatting shared by the run-level views (`stats`,
/// `deps`), so their tables line up the same way.
library;

/// A count right-aligned in a five-wide column.
String countCol(int n) => '$n'.padLeft(5);

/// A share in `[0, 1]` as a percentage with one decimal, six wide.
String pct(double share) => '${(share * 100).toStringAsFixed(1)}%'.padLeft(6);

/// `1 scope`, `2 scopes`; [many] for the irregular ones (`libraries`).
String plural(int count, String noun, [String? many]) =>
    '$count ${count == 1 ? noun : many ?? '${noun}s'}';
