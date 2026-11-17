import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/settings_controller.dart';

class AdvancedNetworkSettings extends StatelessWidget {
  const AdvancedNetworkSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsController controller = context.watch<SettingsController>();
    final AppSettings settings = controller.settings;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      const SizedBox(height: AppMetrics.space4),
      ExpansionTile(
        title: const Text('WARP و اتصال زنجیره‌ای'),
        subtitle: Text(settings.chain.position.label),
        childrenPadding: const EdgeInsets.all(AppMetrics.space3),
        children: <Widget>[
          const Text('فقط همراه سرور مجاز اشتراک آمبرلا کار می‌کند. ثبت دستگاه WARP با Cloudflare انجام می‌شود؛ ترافیک از سرویس واسط نیز عبور می‌کند. زنجیره ممکن است سرعت را کم کند و ناشناس‌بودن را تضمین نمی‌کند.'),
          const SizedBox(height: AppMetrics.space3),
          OutlinedButton.icon(
            icon: const Icon(Icons.link_rounded), label: const Text('تنظیم زنجیره'),
            onPressed: () async {
              final ChainSettings? next = await showDialog<ChainSettings>(context: context,
                builder: (BuildContext context) => ChainSettingsDialog(initial: settings.chain));
              if (next != null) await controller.setChain(next);
            },
          ),
        ],
      ),
      ExpansionTile(
        title: const Text('مسیریابی برنامه‌های ویندوز'),
        subtitle: const Text('فقط تونل؛ اولین قانون منطبق اجرا می‌شود'),
        childrenPadding: const EdgeInsets.all(AppMetrics.space3),
        children: <Widget>[
          const Text('برنامه‌های بدون قانون از تونل عبور می‌کنند. قانون مستقیم عمداً ترافیک و DNS آن برنامه را خارج از تونل می‌فرستد. در پروکسی سیستمی این قواعد اعمال نمی‌شوند. پس از تغییر، دوباره متصل شوید.'),
          for (int i = 0; i < settings.appRoutes.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppMetrics.space2),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                Text(settings.appRoutes[i].process, textDirection: TextDirection.ltr, overflow: TextOverflow.ellipsis),
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
                  Switch(value: settings.appRoutes[i].enabled, onChanged: (bool enabled) => _saveRules(context, controller,
                    <AppRouteRule>[for (int j = 0; j < settings.appRoutes.length; j++)
                      j == i ? AppRouteRule(process: settings.appRoutes[j].process, action: settings.appRoutes[j].action, enabled: enabled) : settings.appRoutes[j]])),
                  Text(settings.appRoutes[i].action.label),
                  IconButton(tooltip: 'ویرایش قانون', icon: const Icon(Icons.edit_outlined), onPressed: () => _editRule(context, controller, index: i)),
                  IconButton(tooltip: 'اولویت بالاتر', icon: const Icon(Icons.arrow_upward_rounded), onPressed: i == 0 ? null : () {
                    final List<AppRouteRule> rules = List<AppRouteRule>.of(settings.appRoutes);
                    final AppRouteRule rule = rules.removeAt(i); rules.insert(i - 1, rule);
                    _saveRules(context, controller, rules);
                  }),
                  IconButton(tooltip: 'حذف قانون', icon: const Icon(Icons.delete_outline_rounded), onPressed: () => _saveRules(context, controller,
                    List<AppRouteRule>.of(settings.appRoutes)..removeAt(i))),
                ]),
              ]),
            ),
          OutlinedButton.icon(icon: const Icon(Icons.add_rounded), label: const Text('افزودن برنامه'),
            onPressed: settings.appRoutes.length >= 64 ? null : () => _editRule(context, controller)),
        ],
      ),
    ]);
  }

  Future<void> _saveRules(BuildContext context, SettingsController controller, List<AppRouteRule> rules) async {
    try {
      await controller.setAppRoutes(rules);
    } on FormatException catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _editRule(BuildContext context, SettingsController controller, {int? index}) async {
    final List<AppRouteRule> rules = List<AppRouteRule>.of(controller.settings.appRoutes);
    final AppRouteRule? result = await showDialog<AppRouteRule>(context: context, builder: (BuildContext context) =>
      AppRouteDialog(initial: index == null ? null : rules[index]));
    if (result == null || !context.mounted) return;
    if (index == null) { rules.add(result); } else { rules[index] = result; }
    await _saveRules(context, controller, rules);
  }
}

class ChainSettingsDialog extends StatefulWidget {
  const ChainSettingsDialog({super.key, required this.initial});
  final ChainSettings initial;
  @override
  State<ChainSettingsDialog> createState() => _ChainSettingsDialogState();
}
class _ChainSettingsDialogState extends State<ChainSettingsDialog> {
  late ChainPosition position;
  late ChainTransport transport;
  late WarpEndpoint endpoint;
  late String masqueProtocol, region;
  late bool searchNoise;
  final Map<String, TextEditingController> fields = <String, TextEditingController>{};
  String? error;
  @override
  void initState() {
    super.initState();
    final ChainSettings initial = widget.initial;
    position = initial.position; transport = initial.transport; endpoint = initial.endpoint;
    masqueProtocol = initial.masqueProtocol; region = initial.psiphonRegion; searchNoise = initial.searchNoise;
    final Map<String, String> values = <String, String>{
      'address': initial.address, 'port': '${initial.port}', 'mtu': '${initial.mtu}',
      'scanCount': '${initial.scanCount}', 'scanConcurrency': '${initial.scanConcurrency}',
      'scanTimeout': '${initial.scanTimeout}', 'scanMaxRtt': '${initial.scanMaxRtt}', 'license': initial.licenseKey,
    };
    for (final MapEntry<String, String> entry in values.entries) { fields[entry.key] = TextEditingController(text: entry.value); }
  }
  @override
  void dispose() { for (final TextEditingController controller in fields.values) { controller.dispose(); } super.dispose(); }

  Widget _choice<T>(String label, T value, Map<T, String> items, ValueChanged<T> changed) => Padding(
    padding: const EdgeInsets.only(bottom: AppMetrics.space3),
    child: DropdownButtonFormField<T>(initialValue: value, isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: items.entries.map((MapEntry<T, String> entry) => DropdownMenuItem<T>(value: entry.key,
        child: Text(entry.value, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: (T? value) { if (value != null) setState(() => changed(value)); }),
  );
  Widget _field(String id, String label, {bool number = false, bool secret = false}) => Padding(
    padding: const EdgeInsets.only(bottom: AppMetrics.space3),
    child: TextField(key: ValueKey<String>('chain-$id'), controller: fields[id], obscureText: secret,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      textDirection: TextDirection.ltr, decoration: InputDecoration(labelText: label)),
  );
  int _int(String key) => int.tryParse(fields[key]!.text) ?? -1;
  void _save() {
    final ChainSettings next = ChainSettings(position: position, transport: transport, endpoint: endpoint,
      address: fields['address']!.text.trim(), port: _int('port'), mtu: _int('mtu'),
      scanCount: _int('scanCount'), scanConcurrency: _int('scanConcurrency'), scanTimeout: _int('scanTimeout'), scanMaxRtt: _int('scanMaxRtt'),
      searchNoise: searchNoise, masqueProtocol: masqueProtocol, licenseKey: fields['license']!.text.trim(), psiphonRegion: region);
    final String? validation = next.enabled ? next.validationError : null;
    if (validation != null) { setState(() => error = validation); return; }
    Navigator.of(context).pop(next);
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('WARP و زنجیره اتصال'),
    content: SizedBox(width: AppMetrics.dialogMaxWidth, child: SingleChildScrollView(child: Column(
      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text('تنظیمات از اتصال بعدی اعمال می‌شوند. روشن‌کردن زنجیره جایگزین حساب یا اشتراک آمبرلا نیست.'),
        const SizedBox(height: AppMetrics.space4),
        _choice<ChainPosition>('ترتیب عبور ترافیک', position, <ChainPosition, String>{for (final ChainPosition item in ChainPosition.values) item: item.label}, (ChainPosition value) => position = value),
        if (position != ChainPosition.off) ...<Widget>[
          _choice<ChainTransport>('نوع واسط', transport, <ChainTransport, String>{for (final ChainTransport item in ChainTransport.values) item: item.label}, (ChainTransport value) => transport = value),
          if (transport == ChainTransport.psiphon)
            _choice<String>('منطقه Psiphon', region, <String, String>{for (final String item in ChainSettings.regions) item: item}, (String value) => region = value)
          else ...<Widget>[
            _choice<WarpEndpoint>('منبع endpoint', endpoint, const <WarpEndpoint, String>{WarpEndpoint.assigned: 'اختصاص‌یافته Cloudflare', WarpEndpoint.scan: 'اسکن توسط هسته', WarpEndpoint.custom: 'IP مشخص'}, (WarpEndpoint value) => endpoint = value),
            if (endpoint == WarpEndpoint.custom) ...<Widget>[_field('address', 'IP endpoint'), _field('port', 'پورت endpoint', number: true)],
            if (endpoint == WarpEndpoint.scan) ...<Widget>[
              const Text('اسکن فقط قبل از سرور آمبرلا پشتیبانی می‌شود. زمان شروع اتصال ممکن است بیشتر شود.'),
              _field('scanCount', 'حداکثر تعداد IP (۱..۲۵۶)', number: true),
              _field('scanConcurrency', 'اسکن همزمان (۱..۳۲)', number: true),
              _field('scanTimeout', 'مهلت هر اسکن (میلی‌ثانیه)', number: true),
              _field('scanMaxRtt', 'حداکثر RTT قابل قبول (میلی‌ثانیه)', number: true),
              SwitchListTile(title: const Text('آزمایش الگوهای نویز'), value: searchNoise, onChanged: (bool value) => setState(() => searchNoise = value)),
            ],
            _field('mtu', 'MTU واسط؛ صفر برای پیش‌فرض هسته', number: true),
            if (transport == ChainTransport.masque || transport == ChainTransport.automatic) ...<Widget>[
              _choice<String>('نسخه HTTP در MASQUE', masqueProtocol, const <String, String>{'auto': 'خودکار', 'h2': 'HTTP/2', 'h3': 'HTTP/3'}, (String value) => masqueProtocol = value),
              const Text('پس از پروکسی، هسته MASQUE را با HTTP/2 اجرا می‌کند؛ حتی اگر HTTP/3 انتخاب شده باشد.'),
            ],
            _field('license', 'کلید WARP+ (اختیاری)', secret: true),
          ],
        ],
        if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ],
    ))),
    actions: <Widget>[
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('انصراف')),
      FilledButton(onPressed: _save, child: const Text('ذخیره زنجیره')),
    ],
  );
}

class AppRouteDialog extends StatefulWidget {
  const AppRouteDialog({super.key, this.initial});
  final AppRouteRule? initial;
  @override
  State<AppRouteDialog> createState() => _AppRouteDialogState();
}
class _AppRouteDialogState extends State<AppRouteDialog> {
  late final TextEditingController process;
  late AppRouteAction action;
  String? error;
  @override
  void initState() { super.initState(); process = TextEditingController(text: widget.initial?.process ?? ''); action = widget.initial?.action ?? AppRouteAction.proxy; }
  @override
  void dispose() { process.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('قانون برنامه'),
    content: SizedBox(width: AppMetrics.dialogMaxWidth, child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
      TextField(controller: process, textDirection: TextDirection.ltr, decoration: InputDecoration(labelText: 'نام exe یا مسیر کامل', hintText: r'C:\Apps\app.exe', errorText: error)),
      const SizedBox(height: AppMetrics.space4),
      DropdownButtonFormField<AppRouteAction>(initialValue: action, isExpanded: true,
        items: <DropdownMenuItem<AppRouteAction>>[for (final AppRouteAction value in AppRouteAction.values) DropdownMenuItem<AppRouteAction>(value: value, child: Text(value.label))],
        onChanged: (AppRouteAction? value) { if (value != null) setState(() => action = value); }),
      const SizedBox(height: AppMetrics.space3),
      const Text('نام exe همه پردازش‌های هم‌نام را شامل می‌شود؛ برای تطبیق دقیق، مسیر کامل را بنویسید.'),
    ])),
    actions: <Widget>[
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('انصراف')),
      FilledButton(child: const Text('ذخیره قانون'), onPressed: () {
        final AppRouteRule rule = AppRouteRule(process: process.text.trim(), action: action, enabled: widget.initial?.enabled ?? true);
        if (rule.validationError != null) { setState(() => error = rule.validationError); return; }
        Navigator.of(context).pop(rule);
      }),
    ],
  );
}
