/// Redact before showing/copying core diagnostics. Raw engine files on disk are
/// still sensitive and should never be shared without review.
String redactNetworkSecrets(
  String input, {
  Iterable<String> knownSecrets = const <String>[],
}) {
  String result = input.replaceAllMapped(
    RegExp(
      r'("(?:license-key|web-secret|lan-sharing-password|password|(?:ed[_-]?25519|wireguard)[_-]?(?:private|public)[_-]?key|wg_(?:pk|pub|psk)|private[_-]?key|privatekey|public[_-]?key|publickey|pre[_-]?shared[_-]?key|presharedkey|psk)"\s*:\s*)"(?:\\.|[^"\\])*"',
      caseSensitive: false,
    ),
    (Match match) => '${match.group(1)}"[redacted]"',
  );
  // Also cover standard WireGuard/SSH style key=value lines in diagnostics.
  result = result.replaceAllMapped(
    RegExp(
      r'(?im)(^\s*(?:private[_-]?key|public[_-]?key|preshared[_-]?key|pre[_-]?shared[_-]?key|psk)\s*=\s*).+$',
    ),
    (Match match) => '${match.group(1)}[redacted]',
  );
  result = result.replaceAllMapped(
    RegExp(
      r'-----BEGIN ([A-Z0-9 ]*PRIVATE KEY)-----.*?-----END \1-----',
      dotAll: true,
    ),
    (Match match) =>
        '-----BEGIN ${match.group(1)}-----[redacted]-----END ${match.group(1)}-----',
  );
  for (final String secret in knownSecrets) {
    if (secret.isNotEmpty) result = result.replaceAll(secret, '[redacted]');
  }
  return result;
}
