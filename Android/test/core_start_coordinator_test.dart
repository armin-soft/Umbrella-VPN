import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/umbrella_core/core_messages.dart';
import 'package:umbrella_vpn/umbrella_core/start_coordinator.dart';

void main() {
  test('does not treat Start acknowledgement as readiness', () async {
    final stream = StreamController<CoreInfoResponse>();
    addTearDown(stream.close);
    var completed = false;
    final result = CoreStartCoordinator.start(
      statuses: stream.stream,
      sendStart: () async => CoreInfoResponse(coreState: CoreStates.starting),
    ).then((value) { completed = true; return value; });
    stream.add(CoreInfoResponse(coreState: CoreStates.stopped));
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    stream.add(CoreInfoResponse(coreState: CoreStates.starting));
    stream.add(CoreInfoResponse(coreState: CoreStates.waiting));
    expect((await result).coreState, CoreStates.waiting);
  });

  test('reports an asynchronous failed start', () async {
    final stream = StreamController<CoreInfoResponse>();
    addTearDown(stream.close);
    final result = CoreStartCoordinator.start(
      statuses: stream.stream,
      sendStart: () async => CoreInfoResponse(coreState: CoreStates.starting),
    );
    stream.add(CoreInfoResponse(coreState: CoreStates.stopped));
    await Future<void>.delayed(Duration.zero);
    stream.add(CoreInfoResponse(coreState: CoreStates.starting));
    stream.add(CoreInfoResponse(coreState: CoreStates.stopped, messageType: MessageType.errorBuildingConfig));
    await expectLater(result, throwsStateError);
  });

  test('rejects an already active engine without issuing start', () async {
    final stream = StreamController<CoreInfoResponse>();
    addTearDown(stream.close);
    var calls = 0;
    final result = CoreStartCoordinator.start(
      statuses: stream.stream,
      sendStart: () async { calls++; return CoreInfoResponse(); },
    );
    stream.add(CoreInfoResponse(coreState: CoreStates.started));
    await expectLater(result, throwsStateError);
    expect(calls, 0);
  });

  test('times out when the engine never reports readiness', () async {
    final stream = StreamController<CoreInfoResponse>();
    addTearDown(stream.close);
    final result = CoreStartCoordinator.start(
      statuses: stream.stream,
      sendStart: () async => CoreInfoResponse(coreState: CoreStates.starting),
      timeout: const Duration(milliseconds: 50),
    );
    stream.add(CoreInfoResponse(coreState: CoreStates.stopped));
    await expectLater(result, throwsA(isA<TimeoutException>()));
  });
}
