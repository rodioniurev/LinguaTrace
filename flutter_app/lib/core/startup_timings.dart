/// How long each startup phase took — shown in Settings → Data, so a slow
/// start can be pinned to a phase instead of guessed.
library;

class StartupTimings {
  StartupTimings._();

  static final phases = <(String, int)>[];
  static final _sw = Stopwatch();

  static void start() => _sw
    ..reset()
    ..start();

  /// Time since the previous mark, recorded under [phase].
  static void mark(String phase) {
    phases.add((phase, _sw.elapsedMilliseconds));
    _sw
      ..reset()
      ..start();
  }

  static int get totalMs => phases.fold(0, (s, p) => s + p.$2);

  static String summary() => phases.isEmpty
      ? ''
      : '${phases.map((p) => '${p.$1} ${p.$2}').join(' · ')} (мс; всего $totalMs)';
}
