import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/vpn/ping.dart';

/// آزمون پاکسازی عدد پینگ: عددهای ۰ و ۱ میلی ثانیه برای سرور بیرونی ممکن
/// نیست و نباید به عنوان «عالی» نمایش داده شوند.
void main() {
  test('پینگ کمتر از ۴ میلی ثانیه غیرمعقول است', () {
    expect(PingService.plausible(0), isFalse);
    expect(PingService.plausible(1), isFalse);
    expect(PingService.plausible(3), isFalse);
  });

  test('پینگ واقعی معقول است', () {
    expect(PingService.plausible(4), isTrue);
    expect(PingService.plausible(87), isTrue);
    expect(PingService.plausible(420), isTrue);
  });
}
