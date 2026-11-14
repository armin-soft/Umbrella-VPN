import 'package:flutter/services.dart';

/// نام کانال های بومی که پیاده سازی سی پلاس پلاس ویندوز در آن گوش می دهد.
///
/// خود کلاس های Dart در برنامه (`lib/platform/native.dart`) این کانال ها را
/// صدا می زنند؛ این فایل فقط برای شناساندن پلاگین به Flutter است.
class UmbrellaNative {
  const UmbrellaNative._();

  static const MethodChannel methods =
      MethodChannel('ir.umbrella.app/native');
  static const EventChannel trayEvents = EventChannel('ir.umbrella.app/tray');
}
