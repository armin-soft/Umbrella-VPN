import '../models/models.dart';

/// Conservative warnings based on parsed profile metadata, not a statement that
/// an unmarked connection is secure. The core's authoritative security RPC is
/// not exposed by our standalone srun process.
class ProxySecurity {
  const ProxySecurity._();

  static String? warning(VpnNode node) {
    final Map<String, dynamic> p = node.params;
    String text(dynamic value) => value?.toString().trim().toLowerCase() ?? '';
    final String security = text(p['security']);
    final String tls = text(p['tls']);
    final String raw = node.raw.trim().toLowerCase();
    final String method = text(p['method'] ?? p['cipher']);
    final String insecure = text(p['allowInsecure'] ?? p['allow_insecure'] ?? p['insecure']);
    final bool pinned = <String>['pinnedPeerCertificateChainSha256', 'pinned_peer_certificate_chain_sha256', 'certificate_public_key_sha256', 'certificate', 'certificate_path', 'pbk']
        .any((String key) => text(p[key]).isNotEmpty);
    if ((insecure == 'true' || insecure == '1') && !pinned &&
        (security == 'tls' || tls == 'tls' || tls == 'true' ||
         node.protocol == NodeProtocol.trojan || node.protocol == NodeProtocol.hysteria2 ||
         node.protocol == NodeProtocol.tuic || node.protocol == NodeProtocol.anytls || node.protocol == NodeProtocol.naive)) {
      return 'در تنظیمات این مسیر، بررسی گواهی TLS خاموش است؛ هویت سرور ممکن است تأیید نشود.';
    }
    if (node.protocol == NodeProtocol.shadowsocks && (method == 'none' || method == 'plain')) {
      return 'این مسیر بدون رمزگذاری شادوساکس تنظیم شده است.';
    }
    if (node.protocol == NodeProtocol.socks &&
        (raw.startsWith('socks://') || raw.startsWith('socks5://')) &&
        security.isEmpty && tls.isEmpty) {
      return 'این مسیر SOCKS بدون رمزگذاری انتقال تعریف شده است.';
    }
    if (node.protocol == NodeProtocol.vless && raw.startsWith('vless://') &&
        (security.isEmpty || security == 'none') && tls.isEmpty) {
      return 'این مسیر VLESS بدون TLS یا REALITY تعریف شده است.';
    }
    return null;
  }

  static String description(VpnNode node) {
    final List<String> pieces = <String>[node.protocol.label];
    final String type = (node.params['type'] ?? node.params['network'] ?? '').toString().trim().toLowerCase();
    const allowed = <String>{'tcp', 'ws', 'grpc', 'xhttp', 'httpupgrade', 'http', 'quic'};
    if (allowed.contains(type)) pieces.add(type.toUpperCase());
    final String security = (node.params['security'] ?? node.params['tls'] ?? '').toString().trim().toLowerCase();
    if (security == 'tls' || security == 'reality') pieces.add(security.toUpperCase());
    return pieces.join(' · ');
  }
}
