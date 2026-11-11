# قرارداد درگاه وب سرویس آمبرلا

پیاده سازی کلاینت: `lib/data/gateway_client.dart`
پایه: `https://user.umbrella-server.ir/5mkVYdBkp8OS/`
کلید: `ae467ee4-2249-4b67-bfa8-e59ca3125286`

همه درخواست ها `POST` با بدنه `application/json` هستند و کلید در هدر
`X-Api-Key` و همچنین در بدنه با نام `api_key` فرستاده می شود تا با هر دو
سبک پیاده سازی سرور سازگار باشد.

## پاسخ مشترک

```json
{ "ok": true, "data": { }, "message": "متن فارسی", "code": "OK" }
```

اگر `ok` نباشد یا کد HTTP غیر ۲۰۰ باشد، خطای `ApiError` با پیام فارسی ساخته
می شود. خطاهای شبکه با تلاش دوباره در لایه کنترلر مدیریت می شوند.

## مسیرها

### `auth/start`

```json
{
  "phone": "09123456789",
  "operator": "mci",
  "device": {
    "id": "uuid-دستگاه",
    "name": "DESKTOP-XXXX",
    "model": "Windows 11 x64",
    "os": "Windows 11 23H2",
    "app_version": "1.0.0",
    "public_ip": "5.6.7.8",
    "country": "Iran",
    "city": "Tehran"
  }
}
```

پاسخ `data`:

```json
{
  "stage": "needsProfile",
  "user_exists": false,
  "bot_url": "https://t.me/umbrella_bot",
  "masked_phone": "0912***6789",
  "resend_in": 60
}
```

مقادیر `stage`: `needsProfile`، `code_sent`، `awaitingTelegram`، `approved`،
`blocked`.

### `auth/verify`

```json
{ "phone": "09123456789", "code": "123456", "request_id": "..." }
```

پاسخ: همان ساختار `stage` به همراه `token` در صورت تایید.

برای ثبت پروفایل کاربر تازه، پیش از `auth/verify` یک درخواست
`auth/profile` با `first_name` و `last_name` فرستاده می شود؛ اگر سرور این
مسیر را نداشته باشد، همین فیلدها در `auth/verify` هم ارسال می شوند.

### `auth/status`

برای انتظار تایید تلگرام. پاسخ: `{ "stage": "awaitingTelegram" }` تا زمانی که
کاربر در ربات دکمه «خودم بودم» را بزند؛ سپس `approved`.

### `auth/session`

```json
{
  "user": { "id": 12, "uuid": "...", "phone": "09123456789", "first_name": "...", "last_name": "...", "telegram_id": 123456 },
  "account": { "plan": "حرفه ای", "usage_used_gb": 12.4, "usage_limit_gb": 100, "expire_at": "2026-12-01", "days_left": 20, "devices": 2, "device_limit": 5, "usage_percent": 12.4 },
  "token": "..."
}
```

### `account/refresh`

پاسخ همان `account` است.

### `filter/get`

```json
{ "categories": { "adult": true, "ads": true, "malware": false, "phishing": false, "gambling": false, "social": false }, "enabled": true }
```

### `filter/save`

بدنه: `{ "categories": { ... }, "enabled": true }`

### `app/notifications`

```json
{ "items": [ { "id": 1, "title": "...", "body": "...", "created_at": "2026-11-01T10:00:00Z", "read": false } ] }
```

## نگاشت فیلدها

کلاینت هر دو سبک `snake_case` و `camelCase` را می خواند و اگر فیلدی نبود مقدار
پیش فرض می گذارد، بنابراین ناسازگاری جزئی نام فیلد باعث خرابی نمی شود.

## کدهای خطا

| کد | معنا | رفتار کلاینت |
| --- | --- | --- |
| `invalid_phone` | شماره نامعتبر | پیام در فرم |
| `user_not_found` | کاربر نیست | انتقال به ثبت نام |
| `code_invalid` | کد اشتباه | پیام و شمارش تلاش |
| `code_expired` | کد منقضی | فعال شدن ارسال دوباره |
| `rate_limited` | ارسال پیاپی | شمارش معکوس |
| `blocked` | حساب مسدود | پیام و توقف |
| `maintenance` | سرویس در تعمیر | پیام و تلاش دوباره |
