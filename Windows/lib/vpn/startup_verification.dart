import 'dart:async';

/// A failed request while lowest/keep-top is still selecting must not restart
/// the entire subscription. Retry on the SAME core, with a bounded deadline.
class StartupVerification {
  const StartupVerification._();
  static Future<bool> wait({
    required Future<bool> Function(Duration timeout) probe,
    required bool Function() cancelled,
    required Future<bool> Function() alive,
    Duration budget = const Duration(minutes: 2),
    Duration interval = const Duration(milliseconds: 500),
    Duration attemptTimeout = const Duration(seconds: 8),
  }) async {
    final Stopwatch clock = Stopwatch()..start();
    final Completer<bool> stopped = Completer<bool>();
    final Timer cancellation = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (cancelled() && !stopped.isCompleted) stopped.complete(false);
    });
    try {
      while (!cancelled() && clock.elapsed < budget) {
        if (!await alive() || cancelled()) return false;
        final Duration remaining = budget - clock.elapsed;
        if (remaining <= Duration.zero) return false;
        final Duration timeout =
            remaining < attemptTimeout ? remaining : attemptTimeout;
        final bool ok = await Future.any(<Future<bool>>[
          probe(timeout).timeout(timeout, onTimeout: () => false), stopped.future,
        ]);
        if (cancelled()) return false;
        if (ok) return true;
        await Future.any(<Future<void>>[
          Future<void>.delayed(interval), stopped.future.then((_) {}),
        ]);
      }
      return false;
    } finally {
      cancellation.cancel();
      clock.stop();
    }
  }
}
