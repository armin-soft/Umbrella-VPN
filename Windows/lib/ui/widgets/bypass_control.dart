import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../core/theme.dart';
import '../../state/auth_controller.dart';
import '../../state/toast_controller.dart';
import 'common.dart';

/// Domains routed directly, synchronized with the account's Telegram settings.
class BypassControlCard extends StatefulWidget {
  const BypassControlCard({super.key});
  @override
  State<BypassControlCard> createState() => _BypassControlCardState();
}

class _BypassControlCardState extends State<BypassControlCard> {
  final TextEditingController _input = TextEditingController();
  @override
  void dispose() { _input.dispose(); super.dispose(); }

  Future<bool> _save(FilterSettings settings) async {
    final auth = context.read<AuthController>();
    final toast = context.read<ToastController>();
    final bool saved = await auth.saveBypass(settings);
    if (!saved && mounted) {
      toast.error('ذخیره مسیر مستقیم ناموفق بود', auth.error);
    }
    return saved;
  }

  Future<void> _add() async {
    final auth = context.read<AuthController>();
    final parsed = FilterSettings.parseDomainInputs(_input.text);
    if (parsed.valid.isEmpty || parsed.invalid.isNotEmpty) {
      context.read<ToastController>().error('دامنه معتبر وارد کنید', 'مثال: example.com');
      return;
    }
    final domains = <String>{...auth.filter.bypassDomains, ...parsed.valid}.toList();
    if (domains.length > FilterSettings.maxCustomDomains) {
      context.read<ToastController>().error('ظرفیت فهرست پر است', 'حداکثر ۲۰۰ دامنه مجاز است.');
      return;
    }
    final bool saved = await _save(auth.filter.copyWith(bypassDomains: domains));
    if (mounted && saved) _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final filter = auth.filter;
    final bool editable = auth.signedIn && !auth.savingFilter;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      const Text('سایت های این فهرست خارج از VPN باز می شوند و نشانی واقعی شما برای آن ها قابل مشاهده است. قوانین مسدودسازی اولویت دارند.'),
      SwitchListTile(
        title: const Text('سایت های ایرانی'),
        subtitle: const Text('دامنه های ایرانی و مجموعه مسیرهای ایران را مستقیم باز کن'),
        value: filter.bypassIran,
        onChanged: editable
            ? withUiClickValue(context, (value) => _save(filter.copyWith(bypassIran: value)))
            : null,
      ),
      TextField(controller: _input, enabled: editable, minLines: 1, maxLines: 3,
        decoration: const InputDecoration(labelText: 'وارد کردن لینک یا دامنه', hintText: 'example.com')),
      const SizedBox(height: AppMetrics.space2),
      OutlinedButton.icon(onPressed: editable ? withUiClick(context, _add) : null,
        icon: const Icon(Icons.add), label: const Text('افزودن سایت')),
      Text('فهرست مسیر مستقیم (${filter.bypassDomains.length} از ۲۰۰)'),
      if (filter.bypassDomains.isEmpty) const Text('هنوز سایتی اضافه نشده است.'),
      for (final domain in filter.bypassDomains)
        ListTile(dense: true, title: Text(domain),
          trailing: IconButton(tooltip: 'حذف سایت', icon: const Icon(Icons.delete_outline),
            onPressed: editable ? withUiClick(context, () => _save(filter.copyWith(
              bypassDomains: filter.bypassDomains.where((value) => value != domain).toList()))) : null)),
    ]);
  }
}
