import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../core/theme.dart';
import '../../vpn/proxy_security.dart';

/// Public nodes are never shown as the subscriber's own private servers.
void showEmergencyList(BuildContext context, List<VpnNode> nodes, int unavailable) {
  showDialog<void>(context: context, builder: (context) => AlertDialog(
    title: const Text('فهرست مسیرهای اضطراری'),
    content: SizedBox(width: AppMetrics.dialogMaxWidth, height: MediaQuery.sizeOf(context).height * 0.55, child: Column(children: <Widget>[
      Text('مسیرهای عمومی اشخاص ثالث؛ حریم خصوصی و دسترس پذیری تضمین نمی شود. '
        '${unavailable > 0 ? 'برخی منابع دریافت نشدند یا قالب آن ها پشتیبانی نمی شود.' : ''}'),
      const SizedBox(height: AppMetrics.space3),
      Expanded(child: nodes.isEmpty ? const Center(child: Text('مسیر سازگاری دریافت نشده است.'))
        : ListView.builder(itemCount: nodes.length, itemBuilder: (context, index) {
          final node = nodes[index];
          final String? warning = ProxySecurity.warning(node);
          return ListTile(
            dense: true,
            title: Text(node.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${ProxySecurity.description(node)} · اضطراری'),
            trailing: warning == null ? null : IconButton(
              tooltip: 'مسیر ناامن؛ توضیحات',
              icon: Icon(Icons.warning_amber_rounded, color: context.colors.danger),
              onPressed: () => showDialog<void>(context: context, builder: (context) => AlertDialog(
                title: const Text('هشدار امنیت مسیر'),
                content: Text('$warning\nاین بررسی تنها بر اساس اطلاعات موجود در اشتراک است.'),
                actions: <Widget>[TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن'))],
              )),
            ),
          );
        })),
    ])),
    actions: <Widget>[TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن'))],
  ));
}
