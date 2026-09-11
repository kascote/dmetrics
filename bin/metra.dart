import 'dart:io';

import 'package:metra/src/cli/cli.dart';

Future<void> main(List<String> args) async {
  final code = runCli(
    args,
    out: stdout,
    err: stderr,
    runRoot: Directory.current.path,
    stdoutIsTerminal: stdout.hasTerminal,
    environment: Platform.environment,
  );
  await stdout.flush();
  await stderr.flush();
  exit(code);
}
