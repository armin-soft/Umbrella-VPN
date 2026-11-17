import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/settings_controller.dart';
import 'advanced_network_settings.dart';
import 'common.dart';

/// تنظیمات مرتب و خوانای شبکه و DNS برای هسته آمبرلا.
class NetworkSettings extends StatelessWidget {
  const NetworkSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsController controller = context.watch<SettingsController>();
    final AppSettings current = controller.settings;
    final UmbrellaColors colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DropdownButtonFormField<TunStack>(
          key: ValueKey<String>('stack-${current.tunStack.name}'),
          initialValue: current.tunStack,
          isExpanded: true,
          dropdownColor: colors.surface,
          borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
          decoration: const InputDecoration(labelText: 'پشته کارت شبکه تونل'),
          items: <DropdownMenuItem<TunStack>>[
            for (final TunStack stack in TunStack.values)
              DropdownMenuItem<TunStack>(
                value: stack,
                child: Text(stack.label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (TunStack? value) {
            if (value != null) controller.setTunStack(value);
          },
        ),
        const SizedBox(height: AppMetrics.space3),
        TextFormField(
          key: ValueKey<String>('mtu-${current.mtu}'),
          initialValue: '${current.mtu}',
          keyboardType: TextInputType.number,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            labelText: 'اندازه بسته (MTU)',
            helperText: 'بین ۱۲۸۰ تا ۹۰۰۰ (برای ذخیره Enter بزنید)',
          ),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (String? value) {
            final int? mtu = int.tryParse(value ?? '');
            return mtu == null || mtu < 1280 || mtu > 9000
                ? 'عددی بین ۱۲۸۰ و ۹۰۰۰ وارد کنید'
                : null;
          },
          onFieldSubmitted: (String value) {
            final int? mtu = int.tryParse(value);
            if (mtu != null && mtu >= 1280 && mtu <= 9000) {
              controller.setMtu(mtu);
            }
          },
        ),
        const SizedBox(height: AppMetrics.space3),
        _dnsField(
          context,
          'دی‌ان‌اس ترافیک تونل',
          'remote',
          current.remoteDns,
          NetworkDns.defaultRemote,
          controller.setRemoteDns,
        ),
        const SizedBox(height: AppMetrics.space3),
        _dnsField(
          context,
          'دی‌ان‌اس اتصال اولیه و مستقیم',
          'direct',
          current.directDns,
          NetworkDns.defaultDirect,
          controller.setDirectDns,
        ),
        const Divider(height: AppMetrics.space5),
        ToggleRow(
          icon: Icons.route_outlined,
          title: 'مسیریابی سخت‌گیرانه تونل',
          subtitle: 'جلوگیری از خروج ناخواسته بسته ها بیرون از مسیر تونل',
          value: current.strictRoute,
          onChanged: controller.setStrictRoute,
        ),
        const Divider(height: AppMetrics.space2),
        ToggleRow(
          icon: Icons.language_rounded,
          title: 'حالت فقط IPv4',
          subtitle: 'غیرفعال کردن IPv6 برای پایداری و سرعت بالاتر اتصال',
          value: current.blockIpv6,
          onChanged: controller.setBlockIpv6,
        ),
        const AdvancedNetworkSettings(),
        const SizedBox(height: AppMetrics.space3),
        Container(
          padding: const EdgeInsets.all(AppMetrics.space3),
          decoration: BoxDecoration(
            color: colors.surfaceHigh.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.info_outline_rounded,
                size: AppMetrics.iconSm,
                color: colors.textSecondary,
              ),
              const SizedBox(width: AppMetrics.space2),
              Expanded(
                child: Text(
                  'تغییرات شبکه و دی‌ان‌اس در اتصال بعدی اعمال می‌شوند.',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary,
                        height: 1.55,
                      ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dnsField(
    BuildContext context,
    String label,
    String id,
    String value,
    String defaultValue,
    ValueChanged<String> onChanged,
  ) {
    final UmbrellaColors colors = context.colors;
    final String normalized =
        NetworkDns.normalize(value, defaultValue: defaultValue);
    return DropdownButtonFormField<String>(
      key: ValueKey<String>('dns-$id-$normalized'),
      initialValue: normalized,
      isExpanded: true,
      dropdownColor: colors.surface,
      borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
      decoration: InputDecoration(labelText: label),
      items: <DropdownMenuItem<String>>[
        for (final MapEntry<String, String> entry in NetworkDns.presets.entries)
          DropdownMenuItem<String>(
            value: entry.key,
            child: Text(entry.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (String? selected) {
        if (selected != null) onChanged(selected);
      },
    );
  }
}
