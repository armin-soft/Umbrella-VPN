import 'package:flutter/services.dart';

/// Android SMS User Consent: the OS asks before sharing one message. Devices
/// without Google Play services simply fall back to manual or keyboard autofill.
class SmsConsent {
  static const MethodChannel _channel = MethodChannel('ir.umbrella.app/sms_consent');

  void listen(void Function(String) onCode) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'smsCode' && call.arguments is String) {
        final code = call.arguments as String;
        if (RegExp(r'^[0-9]{6}$').hasMatch(code)) onCode(code);
      }
    });
  }

  Future<void> start() async {
    try {
      await _channel.invokeMethod<bool>('start').timeout(const Duration(seconds: 2));
    } on Object {
      // Manual entry and autofill remain available if Play services is missing.
    }
  }

  Future<void> stop() async {
    try { await _channel.invokeMethod<void>('stop'); } on Object { /* optional */ }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    stop();
  }
}
