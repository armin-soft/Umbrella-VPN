import 'dart:async';

/// A failed request while lowest/keep-top is still selecting must not restart
/// the entire subscription. Retry on the SAME core, with a bounded deadline.
class StartupVerification {
  const StartupVerification._();

  /// The pinned monitor tests its URLs in stages, waiting for all nodes in a
  /// stage before moving to the next URL. Large pools need a bounded extra
  /// window so a slow first stage cannot consume the entire verification time.
  static Duration mobileBudget(int linkCount) => Duration(
    seconds: 120 + linkCount.clamp(0, 120),
  );
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
        // A Dart timeout cannot cancel a native DNS/socket operation. Never
        // launch another probe while that operation is still running.
        final Future<bool> pending = Future<bool>.sync(() => probe(timeout))
            .catchError((Object _) => false);
        final bool? first = await Future.any<bool?>(<Future<bool?>>[
          pending.then<bool?>((value) => value).timeout(timeout, onTimeout: () => null), stopped.future,
        ]);
        if (cancelled()) return false;
        bool? result = first;
        if (result == null) {
          final Duration left = budget - clock.elapsed;
          if (left <= Duration.zero) return false;
          result = await Future.any<bool?>(<Future<bool?>>[
            pending.then<bool?>((value) => value).timeout(left, onTimeout: () => null), stopped.future,
          ]);
        }
        if (cancelled() || result == null) return false;
        if (result) return true;
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
