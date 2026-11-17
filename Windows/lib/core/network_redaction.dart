/// Redact before showing/copying core diagnostics. Raw engine files on disk are
/// still sensitive and should never be shared without review.
String redactNetworkSecrets(String input, {Iterable<String> knownSecrets = const <String>[]}) {
  String result = input.replaceAllMapped(
    RegExp(r'("(?:license-key|web-secret|private_key|private-key|password)"\s*:\s*)"(?:\\.|[^"\\])*"', caseSensitive: false),
    (Match match) => '${match.group(1)}"[redacted]"',
  );
  for (final String secret in knownSecrets) {
    if (secret.isNotEmpty) result = result.replaceAll(secret, '[redacted]');
  }
  return result;
}
