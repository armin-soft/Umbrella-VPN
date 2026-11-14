// لانچر آمبرلا: هر سه فایل اجرایی هسته از این یک فایل ساخته می شوند.
//
// این فایل همان کاری را می کند که لانچر رسمی موتور می کند
// (`cmd/launcher/main.c` در مخزن hiddify-core)، با یک تفاوت مهم:
//
//   آن لانچر، کتابخانه را با «پیوند» (import) صدا می زند و نام فایل کتابخانه
//   داخل خود فایل اجرایی نوشته می شود. برای همین اگر نام کتابخانه عوض شود،
//   ویندوز فایل اجرایی را پیش از اجرا با کد 0xC0000135 (STATUS_DLL_NOT_FOUND)
//   می بندد؛ همان خطایی که در ۱٫۰٫۲ دیده شد.
//
//   اینجا کتابخانه با LoadLibraryExW از «مسیر» بار می شود، پس نامش هر چه
//   باشد مهم نیست. پوشه کتابخانه هم به مسیر جست وجوی ویندوز اضافه می شود تا
//   libcronet.dll که خود هسته لازم دارد پیدا شود.
//
// سه فایل اجرایی از این یک منبع ساخته می شوند (در windows/CMakeLists.txt):
//
//   UmbrellaCli.exe         — زیرسیستم کنسول؛ همان پنجره خط فرمانی که هنگام
//                             اتصال باز می شود و گزارش زنده هسته را نشان می دهد
//   UmbrellaAdmin.exe       — زیرسیستم گرافیکی با مانیفست requireAdministrator؛
//                             پنجره UAC با نام و آیکون آمبرلا می آید
//   UmbrellaCoreEngine.exe  — زیرسیستم گرافیکی، همان هسته بدون پنجره کنسول
//
// هیچ منطقی از هسته اینجا نیست: همه چیز به `parseCli()` در کتابخانه داده
// می شود؛ دستورها، پرچم ها و رفتار عیناً همان موتور است.

#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>

#ifdef _WIN32
#ifndef UNICODE
#define UNICODE
#endif
#include <windows.h>
#include <shellapi.h>

/// نام فایل کتابخانه هسته در پوشه این فایل اجرایی.
///
/// نام عوض شده و فایل با نام آمبرلا نصب می شود، چون نام فایل در Explorer دیده
/// می شود و کاربر خواسته هیچ نامی جز آمبرلا نبیند. این کار فقط چون کتابخانه
/// «با مسیر» بار می شود بی خطر است: اگر فایل اجرایی، کتابخانه را با پیوند نام
/// صدا می زد (کاری که لانچر رسمی موتور می کند)، عوض شدن نام آن را با
/// 0xC0000135 می بست — همان خطای ۱٫۰٫۲.
///
/// نام قدیمی هم به عنوان جایگزین امتحان می شود تا ارتقای درجا و نسخه های قبلی
/// که فایل را با نام قدیمی دارند هم کار کنند.
#ifndef UMBRELLA_CORE_LIBRARY
#define UMBRELLA_CORE_LIBRARY L"UmbrellaCore.dll"
#endif
#ifndef UMBRELLA_CORE_LIBRARY_LEGACY
#define UMBRELLA_CORE_LIBRARY_LEGACY L"hiddify-core.dll"
#endif

typedef char *(*parse_cli_fn)(int argc, char **argv);

/// گزارش خطا: در نسخه کنسولی روی خروجی خطا و در نسخه گرافیکی با پنجره پیام.
///
/// در ۱٫۰٫۲ فایل اجرایی بی هیچ پیامی بسته می شد و کاربر فقط کد خروج می دید؛
/// اینجا همان حالت هم توضیح دارد.
static void report(const wchar_t *text) {
  fwprintf(stderr, L"%ls\n", text);
  fflush(stderr);
#ifdef UMBRELLA_LAUNCHER_GUI
  MessageBoxW(NULL, text, L"Umbrella", MB_OK | MB_ICONERROR);
#endif
}

/// بار کردن کتابخانه از مسیر خودش، نه با پیوند نام.
///
/// کتابخانه در پوشه `cores\\umbrella` و فایل های اجرایی کنار خود برنامه هستند،
/// پس هر دو جا (به ترتیب) با هر دو نام امتحان می شوند. پوشه ای که کتابخانه در
/// آن پیدا شد به مسیر جست وجوی ویندوز اضافه می شود تا `libcronet.dll` هم پیدا
/// شود. هیچ نامی در جدول واردات فایل اجرایی نیست، پس نام فایل کتابخانه آزاد
/// است؛ همین چیزی است که خطای 0xC0000135 نسخه ۱٫۰٫۲ را غیرممکن می کند.
static parse_cli_fn load_parse_cli(void) {
  wchar_t exe_path[MAX_PATH * 2];
  const DWORD length = GetModuleFileNameW(NULL, exe_path, MAX_PATH * 2);
  if (length == 0 || length >= MAX_PATH * 2) {
    return NULL;
  }
  wchar_t *slash = wcsrchr(exe_path, L'\\');
  if (!slash) {
    return NULL;
  }
  slash[1] = 0;  // پوشه فایل اجرایی
  const size_t root_length = wcslen(exe_path);

  const wchar_t *const folders[] = {L"cores\\umbrella\\", L"cores\\", L""};
  const size_t folder_count = sizeof(folders) / sizeof(folders[0]);
  const wchar_t *const names[] = {UMBRELLA_CORE_LIBRARY,
                                  UMBRELLA_CORE_LIBRARY_LEGACY};
  const size_t name_count = sizeof(names) / sizeof(names[0]);

  for (size_t i = 0; i < folder_count; i++) {
    wchar_t folder[MAX_PATH * 2];
    if (root_length + wcslen(folders[i]) >= MAX_PATH * 2) {
      continue;
    }
    wcscpy(folder, exe_path);
    wcscat(folder, folders[i]);

    for (size_t j = 0; j < name_count; j++) {
      wchar_t library_path[MAX_PATH * 2];
      if (wcslen(folder) + wcslen(names[j]) >= MAX_PATH * 2) {
        continue;
      }
      wcscpy(library_path, folder);
      wcscat(library_path, names[j]);
      if (GetFileAttributesW(library_path) == INVALID_FILE_ATTRIBUTES) {
        continue;
      }
      // پوشه کتابخانه در مسیر جست وجوی ویندوز می رود تا وابسته هایش
      // (libcronet.dll) پیدا شوند. ماندگار است تا عمر همین فرایند.
      SetDllDirectoryW(folder);
      HMODULE core =
          LoadLibraryExW(library_path, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
      if (!core) {
        // ۱۲۶ = ERROR_MOD_NOT_FOUND، ۱۹۳ = ERROR_BAD_EXE_FORMAT
        wchar_t message[MAX_PATH * 3];
        swprintf(message, MAX_PATH * 3,
                 L"Umbrella: the core library could not be loaded from\n%ls\n"
                 L"(error %lu). Reinstall the application with the official "
                 L"setup file.",
                 folder, (unsigned long)GetLastError());
        report(message);
        return NULL;
      }
      parse_cli_fn parse_cli =
          (parse_cli_fn)(void *)GetProcAddress(core, "parseCli");
      if (!parse_cli) {
        report(L"Umbrella: the core library has no entry point. Reinstall the "
               L"application with the official setup file.");
      }
      return parse_cli;
    }
  }

  wchar_t message[MAX_PATH * 3];
  swprintf(message, MAX_PATH * 3,
           L"Umbrella: the core library is missing from\n%ls\n"
           L"(expected in cores\\umbrella). Reinstall the application with the "
           L"official setup file.",
           exe_path);
  report(message);
  return NULL;
}

static char *to_utf8(const wchar_t *wide) {
  int size = WideCharToMultiByte(CP_UTF8, 0, wide, -1, NULL, 0, NULL, NULL);
  char *text = (char *)malloc(size > 0 ? (size_t)size : 1);
  if (!text) {
    return NULL;
  }
  if (size > 0) {
    WideCharToMultiByte(CP_UTF8, 0, wide, -1, text, size, NULL, NULL);
  } else {
    text[0] = 0;
  }
  return text;
}

/// آرگومان های هسته UTF-8 هستند، پس خط فرمان ویندوز دوباره با توابع گسترده
/// خوانده می شود تا مسیرها و نام های فارسی درست برسند.
static char **utf8_arguments(int *argc) {
  wchar_t **wide = CommandLineToArgvW(GetCommandLineW(), argc);
  if (!wide || *argc < 1) {
    return NULL;
  }
  char **argv = (char **)calloc((size_t)*argc + 1, sizeof(char *));
  if (!argv) {
    LocalFree(wide);
    return NULL;
  }
  for (int i = 0; i < *argc; i++) {
    argv[i] = to_utf8(wide[i]);
    if (!argv[i]) {
      LocalFree(wide);
      return NULL;
    }
  }
  LocalFree(wide);
  return argv;
}

static int run(int argc, char **argv) {
  if (!argv) {
    report(L"Umbrella: the command line could not be read.");
    return 1;
  }
  parse_cli_fn parse_cli = load_parse_cli();
  if (!parse_cli) {
    return 3;
  }
#ifdef UMBRELLA_LAUNCHER_GUI
  if (argc < 2) {
    return 2;  // without a command there is nothing to do
  }
#endif
  const char *result = parse_cli(argc, argv);
#if !defined(UMBRELLA_LAUNCHER_GUI)
  if (result) {
    fputs(result, stdout);
    fputc('\n', stdout);
    fflush(stdout);
  }
  return 0;
#else
  return (result && result[0]) ? 1 : 0;  // parseCli returns "" on success
#endif
}

#if defined(UMBRELLA_LAUNCHER_GUI)
int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR command_line,
                    int show_command) {
  (void)instance;
  (void)previous;
  (void)command_line;
  (void)show_command;
  int argc = 0;
  char **argv = utf8_arguments(&argc);
  return run(argc, argv);
}
#else
int main(void) {
  int argc = 0;
  char **argv = utf8_arguments(&argc);
  return run(argc, argv);
}
#endif

#else  // macOS و لینوکس برای ساخت ویندوز لازم نیستند
int main(void) { return 1; }
#endif

/*
  قرارداد این لانچر، همان قرارداد لانچر رسمی موتور است تا هیچ رفتاری عوض نشود:

  * `parseCli(argc, argv)` متن خطا را برمی گرداند و در موفقیت رشته خالی.
  * نسخه کنسولی نتیجه را چاپ می کند و کد ۰ برمی گرداند (پنجره اتصال باز می ماند).
  * نسخه گرافیکی با خطا کد ۱ و در موفقیت ۰ برمی گرداند؛ `argc < 2` یعنی کد ۲.
  * بار نشدن کتابخانه یعنی کد ۳.

  تفاوت تنها در یک چیز است: کتابخانه از مسیر بار می شود، پس نام فایل کتابخانه
  آزاد است و فایل اجرایی هیچ وابستگی پیوندی به آن ندارد (دلیل خطای 0xC0000135
  در ۱٫۰٫۲ همین وابستگی بود).
*/
