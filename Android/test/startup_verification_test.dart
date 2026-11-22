import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/vpn/startup_verification.dart';

void main() {
  test('mobile timeout accounts for large subscriptions and is bounded', () {
    expect(StartupVerification.mobileBudget(1), const Duration(seconds: 121));
    expect(StartupVerification.mobileBudget(84), const Duration(seconds: 204));
    expect(StartupVerification.mobileBudget(10000), const Duration(minutes: 4));
    expect(StartupVerification.mobileBudget(-1), const Duration(minutes: 2));
  });

  test('does not start overlapping native probes after a timeout', () async {
    final pending = Completer<bool>();
    var calls = 0;
    final result = StartupVerification.wait(
      probe: (_) { calls++; return pending.future; },
      cancelled: () => false,
      alive: () async => true,
      budget: const Duration(milliseconds: 120),
      attemptTimeout: const Duration(milliseconds: 20),
      interval: const Duration(milliseconds: 5),
    );
    await Future<void>.delayed(const Duration(milliseconds: 65));
    expect(calls, 1);
    pending.complete(true);
    expect(await result, isTrue);
    expect(calls, 1);
  });

  test('returns false by its overall budget if the native probe never returns', () async {
    final pending = Completer<bool>();
    var calls = 0;
    final result = await StartupVerification.wait(
      probe: (_) { calls++; return pending.future; },
      cancelled: () => false,
      alive: () async => true,
      budget: const Duration(milliseconds: 100),
      attemptTimeout: const Duration(milliseconds: 20),
    );
    expect(result, isFalse);
    expect(calls, 1);
    pending.complete(false);
  });

  test('retries a completed failure and accepts a verified result', () async {
    var calls = 0;
    expect(await StartupVerification.wait(
      probe: (_) async => ++calls == 2,
      cancelled: () => false,
      alive: () async => true,
      budget: const Duration(seconds: 1),
      attemptTimeout: const Duration(milliseconds: 100),
      interval: Duration.zero,
    ), isTrue);
    expect(calls, 2);
  });
}
