/// Formats text emitted by our own engine for display in the app.
/// This does not alter the underlying log, wire protocol, or third-party notices.
String displayOwnCoreOutput(String text, {required String engineId}) {
  if (engineId.isEmpty) return text;
  final pattern = RegExp(
    '\\b${RegExp.escape(engineId)}(?:[-_]?(?:core(?:engine)?|cli))?'
    r'(?:\.(?:dll|exe))?\b',
    caseSensitive: false,
  );
  return text.replaceAll(pattern, 'UmbrellaCore');
}
