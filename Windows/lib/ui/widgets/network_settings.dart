import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/persian.dart';
import '../../core/theme.dart';
import '../../core/ui_formatters.dart';
import '../../models/models.dart';
import '../../state/settings_controller.dart';
import 'advanced_network_settings.dart';
import 'common.dart';

/// تنظیمات پیشرفته، خلوت و خوانای شبکه و DNS برای هسته آمبرلا.
class NetworkSettings extends StatelessWidget {
  const NetworkSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsController controller = context.watch<SettingsController>();
    final AppSettings current = controller.settings;
    final UmbrellaColors colors = context.colors;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool twoCols =
            constraints.maxWidth >= AppMetrics.breakpointCompact;

        final Widget stackField = AnchoredSelectField<TunStack>(
          key: ValueKey<String>('stack-${current.tunStack.name}'),
          label: 'پشته کارت شبکه تونل',
          value: current.tunStack,
          options: <SelectOption<TunStack>>[
            for (final TunStack stack in TunStack.values)
              SelectOption<TunStack>(
                value: stack,
                label: stack.label,
                icon: Icons.layers_rounded,
              ),
          ],
          onChanged: controller.setTunStack,
        );

        final Widget mtuField = _MtuField(
          mtu: current.mtu,
          onSubmitted: controller.setMtu,
        );

        final Widget remoteDnsField = _dnsField(
          label: 'دی ان اس ترافیک تونل',
          id: 'remote',
          value: current.remoteDns,
          defaultValue: NetworkDns.defaultRemote,
          icon: Icons.public_rounded,
          onChanged: controller.setRemoteDns,
        );

        final Widget directDnsField = _dnsField(
          label: 'دی ان اس اتصال اولیه و مستقیم',
          id: 'direct',
          value: current.directDns,
          defaultValue: NetworkDns.defaultDirect,
          icon: Icons.dns_rounded,
          onChanged: controller.setDirectDns,
        );

        final Widget strictToggle = Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppMetrics.space3,
            vertical: AppMetrics.space1,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceHigh.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
            border: Border.all(color: colors.border),
          ),
          child: ToggleRow(
            icon: Icons.route_outlined,
            title: 'مسیریابی سخت گیرانه تونل',
            subtitle: 'جلوگیری از نشت بسته ها بیرون از مسیر امن تونل',
            value: current.strictRoute,
            onChanged: controller.setStrictRoute,
          ),
        );

        final Widget ipv4Toggle = Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppMetrics.space3,
            vertical: AppMetrics.space1,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceHigh.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
            border: Border.all(color: colors.border),
          ),
          child: ToggleRow(
            icon: Icons.language_rounded,
            title: 'حالت فقط آی پی نسخه ۴',
            subtitle: 'غیرفعال کردن آی پی نسخه ۶ برای پایداری و سرعت بالاتر اتصال',
            value: current.blockIpv6,
            onChanged: controller.setBlockIpv6,
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _GroupCaption(
              icon: Icons.tune_rounded,
              title: 'پشته تونل و اندازه بسته',
            ),
            const SizedBox(height: AppMetrics.space3),
            if (twoCols)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: stackField),
                  const SizedBox(width: AppMetrics.space4),
                  Expanded(child: mtuField),
                ],
              )
            else ...<Widget>[
              stackField,
              const SizedBox(height: AppMetrics.space4),
              mtuField,
            ],
            const SizedBox(height: AppMetrics.space5),
            const _GroupCaption(
              icon: Icons.dns_rounded,
              title: 'سرورهای دی ان اس',
            ),
            const SizedBox(height: AppMetrics.space3),
            if (twoCols)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: remoteDnsField),
                  const SizedBox(width: AppMetrics.space4),
                  Expanded(child: directDnsField),
                ],
              )
            else ...<Widget>[
              remoteDnsField,
              const SizedBox(height: AppMetrics.space4),
              directDnsField,
            ],
            const SizedBox(height: AppMetrics.space5),
            const _GroupCaption(
              icon: Icons.alt_route_rounded,
              title: 'سیاست عبور ترافیک',
            ),
            const SizedBox(height: AppMetrics.space3),
            if (twoCols)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: strictToggle),
                  const SizedBox(width: AppMetrics.space4),
                  Expanded(child: ipv4Toggle),
                ],
              )
            else ...<Widget>[
              strictToggle,
              const SizedBox(height: AppMetrics.space3),
              ipv4Toggle,
            ],
            const SizedBox(height: AppMetrics.space5),
            const _GroupCaption(
              icon: Icons.hub_rounded,
              title: 'اتصال زنجیره ای و تفکیک برنامه ها',
            ),
            const SizedBox(height: AppMetrics.space3),
            const AdvancedNetworkSettings(),
            const SizedBox(height: AppMetrics.space5),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppMetrics.space4,
                vertical: AppMetrics.space3,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceHigh.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.info_outline_rounded,
                    size: AppMetrics.iconSm,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: AppMetrics.space2),
                  Expanded(
                    child: Text(
                      'تغییرات شبکه، دی ان اس و مسیریابی در اتصال بعدی اعمال می شوند.',
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
      },
    );
  }

  Widget _dnsField({
    required String label,
    required String id,
    required String value,
    required String defaultValue,
    required IconData icon,
    required ValueChanged<String> onChanged,
  }) {
    final String normalized =
        NetworkDns.normalize(value, defaultValue: defaultValue);
    return AnchoredSelectField<String>(
      key: ValueKey<String>('dns-$id-$normalized'),
      label: label,
      value: normalized,
      options: <SelectOption<String>>[
        for (final MapEntry<String, String> entry in NetworkDns.presets.entries)
          SelectOption<String>(
            value: entry.key,
            label: entry.value,
            subtitle: NetworkDns.subtitleFa(entry.key),
            icon: icon,
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _MtuField extends StatelessWidget {
  const _MtuField({
    required this.mtu,
    required this.onSubmitted,
  });

  final int mtu;
  final ValueChanged<int> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
            'اندازه بسته تونل',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: AppMetrics.space2),
        TextFormField(
          key: ValueKey<String>('mtu-$mtu'),
          initialValue: Fa.num('$mtu'),
          keyboardType: TextInputType.number,
          textDirection: TextDirection.ltr,
          inputFormatters: const <TextInputFormatter>[
            PersianDigitsFormatter(),
          ],
          decoration: InputDecoration(
            isDense: true,
            helperText: Fa.num('بین ۱۲۸۰ تا ۹۰۰۰'),
            helperMaxLines: 2,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppMetrics.space4,
              vertical: AppMetrics.space3,
            ),
            prefixIcon: Icon(
              Icons.straighten_rounded,
              size: AppMetrics.iconSm,
              color: colors.textSecondary,
            ),
          ),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (String? value) {
            final int? parsed = int.tryParse(Fa.toEn(value ?? ''));
            return parsed == null || parsed < 1280 || parsed > 9000
                ? 'عددی بین ۱۲۸۰ و ۹۰۰۰ وارد کنید'
                : null;
          },
          onFieldSubmitted: (String value) {
            final int? parsed = int.tryParse(Fa.toEn(value));
            if (parsed != null && parsed >= 1280 && parsed <= 9000) {
              onSubmitted(parsed);
            }
          },
        ),
      ],
    );
  }
}

class _GroupCaption extends StatelessWidget {
  const _GroupCaption({
    required this.icon,
    required this.title,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final UmbrellaColors colors = context.colors;
    return Row(
      children: <Widget>[
        Icon(icon, size: AppMetrics.iconSm, color: colors.primary),
        const SizedBox(width: AppMetrics.space2),
        Flexible(
          flex: 4,
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        const SizedBox(width: AppMetrics.space3),
        Expanded(child: Divider(height: AppMetrics.space1, color: colors.border)),
      ],
    );
  }
}
