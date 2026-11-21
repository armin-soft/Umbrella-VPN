import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../state/auth_controller.dart';
import '../../state/toast_controller.dart';

/// گفت و گوی تغییر نشانی درگاه برنامه.
///
/// اگر نصب سرور روی دامنه دیگری باشد، کاربر بدون نصب دوباره می تواند نشانی را
/// درست کند؛ مقدار ذخیره شده در شروع بعدی برنامه هم استفاده می شود.
Future<void> showGatewayDialog(BuildContext context) async {
  final AuthController auth = context.read<AuthController>();
  final String? value = await showDialog<String>(
    context: context,
    builder: (_) => _GatewayInputDialog(initial: auth.gatewayBase),
  );
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

class _GatewayInputDialog extends StatefulWidget {
  const _GatewayInputDialog({required this.initial});
  final String initial;
  @override
  State<_GatewayInputDialog> createState() => _GatewayInputDialogState();
}

class _GatewayInputDialogState extends State<_GatewayInputDialog> {
  late final TextEditingController controller;
  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initial);
  }
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(Fa.num('نشانی درگاه برنامه')),
    content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(Fa.num('نشانی کامل درگاه ربات را وارد کنید:'), style: Theme.of(context).textTheme.labelSmall),
      const SizedBox(height: AppMetrics.space2),
      TextField(controller: controller, autofocus: true, textDirection: TextDirection.ltr,
        decoration: const InputDecoration(hintText: 'نشانی درگاه ربات')),
    ]),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(Fa.num('انصراف'))),
      TextButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: Text(Fa.num('ذخیره و بررسی'))),
    ],
  );
}
