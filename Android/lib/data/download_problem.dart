import 'dart:async';
import 'dart:io';

import '../core/persian.dart';

/// نوع دقیق خطای دریافت اشتراک یا منبع شبکه برای راهنمایی روشن کاربر بدون
/// افشای نشانی یا توکن اشتراک.
enum DownloadProblemType {
  serverError,
  notFound,
  denied,
  tooManyRequests,
  badStatus,
  tooLarge,
  noInternet,
  dns,
  certificate,
  reset,
  tls,
  refused,
  timeout,
  unknown,
}

/// دسته بندی یکپارچه خطاهای دریافت اشتراک (از مسیر WinHTTP، سوکت دارت یا هسته).
class DownloadProblem {
  const DownloadProblem({
    required this.type,
    required this.titleFa,
    required this.hintFa,
    this.statusCode,
    this.mayPass = true,
  });

  final DownloadProblemType type;
  final String titleFa;
  final String hintFa;
  final int? statusCode;
  final bool mayPass;

  String get messageFa => '$titleFa؛ $hintFa';

  /// نگاشت مستقیم کد `FetchUrlError` هسته (`0..9` در قرارداد Core).
  static DownloadProblem fromCoreError(int code, {int? statusCode}) {
    switch (code) {
      case 1: // timeout
        return const DownloadProblem(
          type: DownloadProblemType.timeout,
          titleFa: 'پاسخ سرور اشتراک دیر رسید',
          hintFa: 'اتصال اینترنت یا وضعیت شبکه را بررسی کنید و دوباره تلاش کنید.',
          mayPass: true,
        );
      case 2: // dns
        return const DownloadProblem(
          type: DownloadProblemType.dns,
          titleFa: 'نام دامنه سرور اشتراک پیدا نشد',
          hintFa: 'تنظیمات دی ان اس یا اتصال اینترنت را بررسی کنید.',
          mayPass: true,
        );
      case 3: // refused
        return const DownloadProblem(
          type: DownloadProblemType.refused,
          titleFa: 'سرور اشتراک اتصال را نپذیرفت',
          hintFa: 'چند لحظه بعد دوباره امتحان کنید.',
          mayPass: true,
        );
      case 4: // reset
        return const DownloadProblem(
          type: DownloadProblemType.reset,
          titleFa: 'ارتباط در مسیر شبکه قطع شد',
          hintFa: 'احتمالاً محدودیت شبکه یا فیلتر در مسیر وجود دارد؛ با اتصال فعال یا شبکه دیگر امتحان کنید.',
          mayPass: true,
        );
      case 5: // unreachable
        return const DownloadProblem(
          type: DownloadProblemType.noInternet,
          titleFa: 'دسترسی به اینترنت برقرار نیست',
          hintFa: 'اتصال وای فای یا کابل شبکه را بررسی کنید.',
          mayPass: true,
        );
      case 6: // tls
        return const DownloadProblem(
          type: DownloadProblemType.tls,
          titleFa: 'دست دادن امن با سرور اشتراک کامل نشد',
          hintFa: 'ممکن است ترافیک امن محدود شده باشد؛ چند لحظه بعد یا با شبکه دیگر امتحان کنید.',
          mayPass: true,
        );
      case 7: // certificate
        return const DownloadProblem(
          type: DownloadProblemType.certificate,
          titleFa: 'گواهی امنیتی سرور تایید نشد',
          hintFa: 'ساعت و تاریخ دستگاه و درستی گواهی شبکه را بررسی کنید.',
          mayPass: false,
        );
      case 9: // too_large
        return const DownloadProblem(
          type: DownloadProblemType.tooLarge,
          titleFa: 'حجم فایل اشتراک بیش از حد مجاز است',
          hintFa: 'با پشتیبانی در ارتباط باشید.',
          mayPass: false,
        );
      default:
        return fromStatusOrSignal(statusCode: statusCode);
    }
  }

  /// نگاشت خطاهای HTTP، کدهای WinHTTP و استثناهای شبکه.
  static DownloadProblem fromStatusOrSignal({
    int? statusCode,
    int winError = 0,
    bool timedOut = false,
    bool tlsFailed = false,
    bool certificateFailed = false,
    bool reset = false,
    bool dnsFailed = false,
    bool refused = false,
    bool offline = false,
    Object? error,
  }) {
    if (statusCode != null && statusCode > 0) {
      if (statusCode >= 500 && statusCode <= 599) {
        return DownloadProblem(
          type: DownloadProblemType.serverError,
          statusCode: statusCode,
          titleFa: 'سرور اشتراک موقتاً پاسخ خطا داد (کد ${Fa.num(statusCode)})',
          hintFa: 'چند لحظه صبر کنید و دوباره تلاش کنید.',
          mayPass: true,
        );
      }
      if (statusCode == 404) {
        return DownloadProblem(
          type: DownloadProblemType.notFound,
          statusCode: statusCode,
          titleFa: 'نشانی اشتراک یافت نشد (کد ${Fa.num(404)})',
          hintFa: 'حساب خود را در برنامه یا ربات بررسی کنید.',
          mayPass: false,
        );
      }
      if (statusCode == 401 || statusCode == 403) {
        return DownloadProblem(
          type: DownloadProblemType.denied,
          statusCode: statusCode,
          titleFa: 'دسترسی به اشتراک رد شد (کد ${Fa.num(statusCode)})',
          hintFa: 'وضعیت اعتبار یا دستگاه مجاز را بررسی کنید.',
          mayPass: false,
        );
      }
      if (statusCode == 429) {
        return DownloadProblem(
          type: DownloadProblemType.tooManyRequests,
          statusCode: statusCode,
          titleFa: 'تعداد درخواست های دریافت اشتراک زیاد شده است',
          hintFa: 'چند دقیقه صبر کنید و دوباره امتحان کنید.',
          mayPass: true,
        );
      }
      if (statusCode >= 400) {
        return DownloadProblem(
          type: DownloadProblemType.badStatus,
          statusCode: statusCode,
          titleFa: 'دریافت اشتراک ناموفق بود (کد ${Fa.num(statusCode)})',
          hintFa: 'اتصال اینترنت و وضعیت حساب را بررسی کنید.',
          mayPass: false,
        );
      }
    }

    // کدهای رایج خطای WinHTTP ویندوز (`winhttp.h`)
    switch (winError) {
      case 12002: // ERROR_WINHTTP_TIMEOUT
        timedOut = true;
        break;
      case 12007: // ERROR_WINHTTP_NAME_NOT_RESOLVED
        dnsFailed = true;
        break;
      case 12029: // ERROR_WINHTTP_CANNOT_CONNECT
        refused = true;
        break;
      case 12030: // ERROR_WINHTTP_CONNECTION_ERROR
      case 12031: // ERROR_WINHTTP_RESEND_REQUEST
        reset = true;
        break;
      case 12037: // ERROR_WINHTTP_SECURE_CERT_DATE_INVALID
      case 12038: // ERROR_WINHTTP_SECURE_CERT_CN_INVALID
      case 12044: // ERROR_WINHTTP_CLIENT_AUTH_CERT_NEEDED
      case 12045: // ERROR_WINHTTP_SECURE_INVALID_CA
      case 12057: // ERROR_WINHTTP_SECURE_CERT_REV_FAILED
        certificateFailed = true;
        break;
      case 12175: // ERROR_WINHTTP_SECURE_FAILURE
        tlsFailed = true;
        break;
    }

    final String detail = '${error ?? ''}'.toLowerCase();
    if (error is TimeoutException || timedOut || detail.contains('timed out')) {
      return fromCoreError(1);
    }
    if (error is HandshakeException && (detail.contains('eof') || detail.contains('reset'))) {
      return fromCoreError(4);
    }
    if (certificateFailed || error is CertificateException || detail.contains('certificate')) {
      return fromCoreError(7);
    }
    if (tlsFailed || error is HandshakeException || error is TlsException || detail.contains('handshake')) {
      return fromCoreError(6);
    }
    if (dnsFailed || detail.contains('failed host lookup') || detail.contains('name not resolved') || detail.contains('no such host')) {
      return fromCoreError(2);
    }
    if (reset || detail.contains('connection reset') || detail.contains('aborted') || detail.contains('broken pipe')) {
      return fromCoreError(4);
    }
    if (refused || detail.contains('connection refused')) {
      return fromCoreError(3);
    }
    if (offline || detail.contains('network is unreachable') || detail.contains('no route to host')) {
      return fromCoreError(5);
    }
    if (error is SocketException) {
      return fromCoreError(5);
    }
    return const DownloadProblem(
      type: DownloadProblemType.unknown,
      titleFa: 'دسترسی به سرور اشتراک برقرار نشد',
      hintFa: 'اتصال اینترنت یا محدودیت شبکه را بررسی کنید و دوباره تلاش کنید.',
      mayPass: true,
    );
  }
}
