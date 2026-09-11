/// Console color: a [Palette] the reporter paints with, and the policy that
/// picks one. Color carries the verdict and nothing else, so a line stays
/// scannable: fail red, warn yellow, ok and suppressed dim, the status word
/// in the summary, diagnostics by severity.
///
/// The decision is made once in the CLI ([resolveColor]) and passed down;
/// reporters are pure string functions and never look at the terminal.
library;

enum ColorMode { auto, always, never }

/// SGR wrappers. [plain] returns its input unchanged.
class Palette {
  final bool enabled;

  const Palette._(this.enabled);

  static const plain = Palette._(false);
  static const ansi = Palette._(true);

  String _wrap(String code, String s) => enabled ? '\x1B[${code}m$s\x1B[0m' : s;

  String red(String s) => _wrap('31', s);
  String green(String s) => _wrap('32', s);
  String yellow(String s) => _wrap('33', s);
  String cyan(String s) => _wrap('36', s);
  String dim(String s) => _wrap('2', s);
  String bold(String s) => _wrap('1', s);
}

/// `auto` colors only when stdout is a terminal, `NO_COLOR` is unset
/// (https://no-color.org) and `TERM` is not `dumb`. `--json` never colors;
/// the caller enforces that by not asking.
Palette resolveColor(
  ColorMode mode, {
  required bool stdoutIsTerminal,
  required Map<String, String> environment,
}) => switch (mode) {
  ColorMode.always => Palette.ansi,
  ColorMode.never => Palette.plain,
  ColorMode.auto =>
    stdoutIsTerminal &&
            (environment['NO_COLOR'] ?? '').isEmpty &&
            environment['TERM'] != 'dumb'
        ? Palette.ansi
        : Palette.plain,
};
