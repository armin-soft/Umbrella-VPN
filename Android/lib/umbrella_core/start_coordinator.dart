import 'dart:async';

import 'core_messages.dart';

/// Waits for the core lifecycle, not just the asynchronous Start RPC reply.
/// A ready core is not proof that user traffic flows; callers must verify VPN
/// traffic separately before showing the connected state.
class CoreStartCoordinator {
  const CoreStartCoordinator._();

  static Future<CoreInfoResponse> start({
    required Stream<CoreInfoResponse> statuses,
    required Future<CoreInfoResponse> Function() sendStart,
    void Function(int state, int messageType)? onState,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final first = Completer<CoreInfoResponse?>();
    final outcome = Completer<CoreInfoResponse?>();
    var requestSent = false;
    var sawStarting = false;
    final subscription = statuses.listen((info) {
      onState?.call(info.coreState, info.messageType);
      if (!first.isCompleted) {
        first.complete(info);
        return;
      }
      if (!requestSent || outcome.isCompleted) return;
      if (info.coreState == CoreStates.starting) sawStarting = true;
      if (info.coreState == CoreStates.started ||
          info.coreState == CoreStates.waiting ||
          info.coreState == CoreStates.noAvailableProxies ||
          (sawStarting && info.coreState == CoreStates.stopped)) {
        outcome.complete(info);
      }
    }, onError: (Object _, StackTrace __) {
      if (!first.isCompleted) first.complete(null);
      if (!outcome.isCompleted) outcome.complete(null);
    }, onDone: () {
      if (!first.isCompleted) first.complete(null);
      if (!outcome.isCompleted) outcome.complete(null);
    });

    Future<CoreInfoResponse> run() async {
      final initial = await first.future;
      if (initial == null || initial.coreState != CoreStates.stopped) {
        throw StateError('Core is not ready for a new start');
      }
      requestSent = true;
      final response = await sendStart();
      if (response.messageType != MessageType.empty ||
          response.coreState != CoreStates.starting) {
        throw StateError('Core rejected start');
      }
      final result = await outcome.future;
      if (result == null || result.coreState == CoreStates.stopped ||
          result.coreState == CoreStates.noAvailableProxies) {
        throw StateError('Core did not start successfully');
      }
      return result;
    }

    try {
      return await run().timeout(timeout);
    } finally {
      await subscription.cancel();
    }
  }
}
