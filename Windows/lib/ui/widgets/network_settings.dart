import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/settings_controller.dart';
import 'common.dart';

/// Settings for the pinned core, not a profile/source editor.
class NetworkSettings extends StatelessWidget {
  const NetworkSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsController controller = context.watch<SettingsController>();
    final AppSettings current = controller.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text('تغییرات از اتصال بعدی اعمال می‌شوند. پشته، MTU و مسیر سخت‌گیرانه فقط در حالت تونل اثر دارند.'),
        const SizedBox(height: 16),
        DropdownButtonFormField<TunStack>(
          key: ValueKey<String>('stack-${current.tunStack.name}'),
          initialValue: current.tunStack,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'پشته تونل'),
          items: <DropdownMenuItem<TunStack>>[
            for (final TunStack stack in TunStack.values)
              DropdownMenuItem<TunStack>(value: stack, child: Text(stack.label)),
          ],
          onChanged: (TunStack? value) {
            if (value != null) controller.setTunStack(value);
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: ValueKey<String>('mtu-${current.mtu}'),
          initialValue: '${current.mtu}',
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'MTU', helperText: '۱۲۸۰ تا ۹۰۰۰؛ برای ذخیره Enter بزنید'),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (String? value) {
            final int? mtu = int.tryParse(value ?? '');
            return mtu == null || mtu < 1280 || mtu > 9000 ? 'عددی بین ۱۲۸۰ و ۹۰۰۰ وارد کنید' : null;
          },
          onFieldSubmitted: (String value) {
            final int? mtu = int.tryParse(value);
            if (mtu != null && mtu >= 1280 && mtu <= 9000) controller.setMtu(mtu);
          },
        ),
        ToggleRow(
          icon: Icons.route_outlined,
          title: 'مسیریابی سخت‌گیرانه تونل',
          subtitle: 'محدودکردن مسیرهای خارج از تونل؛ ممکن است شبکه محلی را محدود کند',
          value: current.strictRoute,
          onChanged: controller.setStrictRoute,
        ),
        ToggleRow(
          icon: Icons.language_rounded,
          title: 'ترجیح IPv4 در هسته',
          subtitle: 'در شبکه فقط IPv6، هسته ممکن است IPv6 را حفظ کند؛ این گزینه مسدودسازی IPv6 ویندوز نیست',
          value: current.blockIpv6,
          onChanged: controller.setBlockIpv6,
        ),
        const SizedBox(height: 16),
        _dnsField('دی‌ان‌اس ترافیک تونل', 'remote', current.remoteDns, controller.setRemoteDns),
        const SizedBox(height: 16),
        _dnsField('دی‌ان‌اس اتصال اولیه و مستقیم', 'direct', current.directDns, controller.setDirectDns),
        const SizedBox(height: 12),
        const Text('هسته پرس‌وجوهای ترافیک پروکسی را از تونل می‌فرستد. برای یافتن آدرس سرور و مسیرهای مستقیم، DNS مستقیم لازم است. این تنظیم تضمین نبود نشت DNS نیست.'),
      ],
    );
  }

  Widget _dnsField(String label, String id, String value, ValueChanged<String> onChanged) {
    final String normalized = NetworkDns.normalize(value);
    return DropdownButtonFormField<String>(
      key: ValueKey<String>('dns-$id-$normalized'),
      initialValue: normalized,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: <DropdownMenuItem<String>>[
        for (final MapEntry<String, String> entry in NetworkDns.presets.entries)
          DropdownMenuItem<String>(value: entry.key, child: Text(entry.value, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (String? selected) {
        if (selected != null) onChanged(selected);
      },
    );
  }
}
