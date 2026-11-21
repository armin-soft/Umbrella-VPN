import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:umbrella_vpn/platform/native.dart';
import 'package:umbrella_vpn/platform/services.dart';
import 'package:umbrella_vpn/state/update_controller.dart';

void main() {
  test('automatic update checks are throttled after a failed attempt', () async {
    int requests = 0;
    final MockClient client = MockClient((http.Request _) async {
      requests++;
      throw const SocketException('offline');
    });
    final UpdateController updates = UpdateController(
      NativeBridge(),
      service: UpdateService(client: client),
    );
    addTearDown(() {
      updates.dispose();
      client.close();
    });

    expect(updates.autoCheckDue, isTrue);
    await updates.checkIfDue();
    expect(requests, greaterThan(0));
    expect(updates.lastCheckAttemptAt, isNotNull);
    expect(updates.autoCheckDue, isFalse);

    final int requestsAfterFirstCheck = requests;
    await updates.checkIfDue();
    expect(requests, requestsAfterFirstCheck);

    // دستی زدن به «بررسی دوباره» همچنان باید محدودیت خودکار را دور بزند.
    await updates.check(silent: false);
    expect(requests, greaterThan(requestsAfterFirstCheck));
  });
}
