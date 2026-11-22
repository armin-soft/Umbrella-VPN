import 'package:flutter/material.dart';
import '../../models/models.dart';

/// Public nodes are never shown as the subscriber's own private servers.
void showEmergencyList(BuildContext context, List<VpnNode> nodes, int unavailable) {
  showDialog<void>(context: context, builder: (context) => AlertDialog(
    title: const Text('فهرست مسیرهای اضطراری'),
    content: SizedBox(width: 480, height: 400, child: Column(children: <Widget>[
      Text('مسیرهای عمومی اشخاص ثالث؛ حریم خصوصی و دسترس پذیری تضمین نمی شود. '
        '${unavailable > 0 ? 'برخی منابع دریافت نشدند یا قالب آن ها پشتیبانی نمی شود.' : ''}'),
      const SizedBox(height: 12),
      Expanded(child: nodes.isEmpty ? const Center(child: Text('مسیر سازگاری دریافت نشده است.'))
        : ListView.builder(itemCount: nodes.length, itemBuilder: (context, index) {
          final node = nodes[index];
          return ListTile(dense: true, title: Text(node.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${node.protocol.label} · اضطراری'));
        })),
    ])),
    actions: <Widget>[TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن'))],
  ));
}
