import 'package:flutter_test/flutter_test.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/vpn/balancer.dart';

/// آزمون حالت های انتخاب سرور: هر حالت باید رفتار خودش را داشته باشد، نه
/// اینکه همه یک نتیجه بدهند.
void main() {
  VpnNode node(
    String id,
    int ping, {
    double stability = 0.8,
  }) {
    return VpnNode(
      id: id,
      name: 'سرور $id',
      protocol: NodeProtocol.vless,
      host: 'host-$id.example.com',
      port: 443,
      sourceId: 'src',
      params: <String, dynamic>{
        'id': '9b9d9f5d-9841-45bf-a6b9-0479de273c11',
      },
      pingMs: ping,
      stability: stability,
      checkedAt: DateTime.now(),
    );
  }

  final List<VpnNode> nodes = <VpnNode>[
    node('a', 300),
    node('b', 90),
    node('c', 180),
  ];

  test('حالت خودکار سرور با کمترین پینگ را برمی دارد', () {
    final NodeBalancer balancer = NodeBalancer();
    final SelectionResult result = balancer.pick(
      nodes: nodes,
      mode: SelectionMode.auto,
      deviceSeed: 'device-1',
    );
    expect(result.node?.id, 'b');
  });

  test('حالت گردشی نوبت ها را عوض می کند و همه سرورها را می چرخاند', () {
    final NodeBalancer balancer = NodeBalancer();
    final List<String> picked = <String>[];
    for (int i = 0; i < nodes.length; i++) {
      picked.add(
        balancer
            .pick(
              nodes: nodes,
              mode: SelectionMode.roundRobin,
              deviceSeed: 'device-1',
            )
            .node!
            .id,
      );
    }
    expect(picked.toSet().length, nodes.length);
    expect(picked.first, isNot(picked[1]));
  });

  test('حالت هش پایدار برای یک دستگاه همیشه یک سرور می دهد', () {
    final SelectionResult first = NodeBalancer().pick(
      nodes: nodes,
      mode: SelectionMode.consistentHash,
      deviceSeed: 'machine-abc',
    );
    final SelectionResult second = NodeBalancer().pick(
      nodes: nodes,
      mode: SelectionMode.consistentHash,
      deviceSeed: 'machine-abc',
    );
    expect(first.node?.id, second.node?.id);
  });

  test('حالت نشست چسبنده بین دو اتصال پشت سر هم سرور را عوض نمی کند', () {
    final NodeBalancer balancer = NodeBalancer();
    final SelectionResult first = balancer.pick(
      nodes: nodes,
      mode: SelectionMode.stickySession,
      deviceSeed: 'device-1',
      stickyMinutes: 30,
    );
    final SelectionResult second = balancer.pick(
      nodes: nodes,
      mode: SelectionMode.stickySession,
      deviceSeed: 'device-1',
      stickyMinutes: 30,
    );
    expect(first.node?.id, isNotNull);
    expect(second.node?.id, first.node?.id);
  });

  test('حالت دستی همان سرور انتخابی کاربر را می دهد', () {
    final SelectionResult result = NodeBalancer().pick(
      nodes: nodes,
      mode: SelectionMode.manual,
      deviceSeed: 'device-1',
      preferredNodeId: 'c',
    );
    expect(result.node?.id, 'c');
  });

  test('سروری که همین حالا شکست خورده در انتخاب بعدی کنار گذاشته می شود', () {
    final NodeBalancer balancer = NodeBalancer();
    balancer.markFailed('b');
    final SelectionResult result = balancer.pick(
      nodes: nodes,
      mode: SelectionMode.auto,
      deviceSeed: 'device-1',
    );
    expect(result.node?.id, isNot('b'));
  });
}
