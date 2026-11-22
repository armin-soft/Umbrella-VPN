import 'package:flutter/services.dart';

class SimNumber {
  const SimNumber(this.slot, this.number);
  final int slot;
  final String number;
}

class SimNumbersResult {
  const SimNumbersResult(this.status, this.sims);
  final String status;
  final List<SimNumber> sims;
}

/// Called only after the user chooses the SIM picker; never logs phone numbers.
class SimNumbers {
  static const MethodChannel _channel = MethodChannel('ir.umbrella.app/android');

  Future<SimNumbersResult> read() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('readSimNumbers');
      final list = result?['sims'];
      final sims = <SimNumber>[];
      if (list is List) {
        for (final value in list) {
          if (value is Map && value['slot'] is int && value['number'] is String) {
            sims.add(SimNumber(value['slot'] as int, value['number'] as String));
          }
        }
      }
      return SimNumbersResult(result?['status'] as String? ?? 'unavailable', sims);
    } on Object {
      return const SimNumbersResult('unavailable', []);
    }
  }
}
