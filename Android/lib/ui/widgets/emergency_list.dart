import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../core/theme.dart';
import '../../vpn/proxy_security.dart';
import 'common.dart';

/// Public nodes are never shown as the subscriber's own private servers.
void showEmergencyList(BuildContext context, List<VpnNode> nodes, int unavailable) {
  showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
    title: const Text('فهرست مسیرهای اضطراری'),
    content: SizedBox(width: AppMetrics.dialogMaxWidth, height: MediaQuery.sizeOf(dialogContext).height * 0.55, child: Column(children: <Widget>[
      if (unavailable > 0) ...<Widget>[
        const Text('برخی منابع دریافت نشدند یا قالب آن ها پشتیبانی نمی شود.'),
        const SizedBox(height: AppMetrics.space3),
      ],
      Expanded(child: nodes.isEmpty ? const Center(child: Text('مسیر سازگاری دریافت نشده است.'))
        : ListView.builder(itemCount: nodes.length, itemBuilder: (itemContext, index) {
          final node = nodes[index];
          final String? warning = ProxySecurity.warning(node);
          return ListTile(
            dense: true,
            title: Text(node.name),
            subtitle: Text('${ProxySecurity.description(node)} · اضطراری'),
            trailing: warning == null ? null : IconButton(
              tooltip: 'مسیر ناامن؛ توضیحات',
              icon: Icon(Icons.warning_amber_rounded, color: itemContext.colors.danger),
              onPressed: withUiClick(context, () => showDialog<void>(context: itemContext, builder: (warnContext) => AlertDialog(
                title: const Text('هشدار امنیت مسیر'),
                content: Text('$warning\nاین بررسی تنها بر اساس اطلاعات موجود در اشتراک است.'),
                actions: <Widget>[TextButton(onPressed: withUiClick(context, () => Navigator.pop(warnContext)), child: const Text('بستن'))],
              ))),
            ),
          );
        })),
    ])),
    actions: <Widget>[TextButton(onPressed: withUiClick(context, () => Navigator.pop(dialogContext)), child: const Text('بستن'))],
  ));
}
