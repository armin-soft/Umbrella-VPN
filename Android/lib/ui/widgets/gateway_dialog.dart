import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../state/auth_controller.dart';
import '../../state/toast_controller.dart';
import 'common.dart';

/// گفت و گوی تغییر نشانی درگاه برنامه.
///
/// اگر نصب سرور روی دامنه دیگری باشد، کاربر بدون نصب دوباره می تواند نشانی را
/// درست کند؛ مقدار ذخیره شده در شروع بعدی برنامه هم استفاده می شود.
Future<void> showGatewayDialog(BuildContext context) async {
  final AuthController auth = context.read<AuthController>();
  final TextEditingController controller =
      TextEditingController(text: auth.gatewayBase);
  final String? value = await showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: Text(Fa.num('نشانی درگاه برنامه')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              Fa.num('نشانی کامل درگاه ربات را وارد کنید:'),
              style: Theme.of(dialogContext).textTheme.labelSmall,
            ),
            const SizedBox(height: AppMetrics.space2),
            TextField(
              controller: controller,
              autofocus: true,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(hintText: 'نشانی درگاه ربات'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: withUiClick(context, () => Navigator.of(dialogContext).pop()),
            child: Text(Fa.num('انصراف')),
          ),
          TextButton(
            onPressed: withUiClick(
              context,
              () => Navigator.of(dialogContext).pop(controller.text.trim()),
            ),
            child: Text(Fa.num('ذخیره و بررسی')),
          ),
        ],
      );
    },
  );
  controller.dispose();
  if (value == null || !context.mounted) {
    return;
  }
  final ToastController toasts = context.read<ToastController>();
  await auth.setGatewayBase(value);
  if (auth.error.isNotEmpty) {
    toasts.error('نشانی درگاه ذخیره نشد', auth.error);
    return;
  }
  final bool ok = await auth.testGateway();
  if (!context.mounted) {
    return;
  }
  if (ok) {
    toasts.success('نشانی درگاه ذخیره شد', auth.gatewayHost);
  } else {
    toasts.error('درگاه پاسخ نداد', auth.error);
  }
}
