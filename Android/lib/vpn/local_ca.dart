import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// مدیریت گواهی ریشه محلی (Local Root CA) و صدور لحظه ای گواهی های TLS برگ
/// برای فیلترینگ عمیق HTTPS (سبک AdGuard Desktop/Android).
///
/// تمام عملیات رمزنگاری با استاندارد **ECDSA P-256 (`secp256r1`) + SHA-256**،
/// امضای قطعی **RFC 6979** (به همراه Low-S normalization) و قالب استاندارد
/// **ASN.1 DER / PKCS#8 / X.509 v3 (RFC 5280)** به صورت خالص در Dart
/// پیاده سازی شده است تا بدون نیاز به باینری یا پلاگین خارجی، در ویندوز،
/// اندروید و آزمون های واحد یکپارچه و قابل راستی آزمایی کار کند.
class LocalCaManager {
  LocalCaManager({
    required this.storageDir,
    this.commonName = 'Umbrella Local HTTPS Filter CA',
    this.organization = 'Umbrella VPN',
    this.organizationalUnit = 'Local Ad & Content Guard',
    this.maxCachedLeaves = 256,
  });

  final String storageDir;
  final String commonName;
  final String organization;
  final String organizationalUnit;
  final int maxCachedLeaves;

  static const String certFileName = 'umbrella-https-ca.crt';
  static const String keyFileName = 'umbrella-https-ca.key';

  _EcP256KeyPair? _caKeyPair;
  Uint8List _caCertDer = Uint8List(0);
  String _caCertPem = '';
  Uint8List _caSki = Uint8List(0);
  String _caSha1Hex = '';
  String _caSha256Hex = '';
  Future<void>? _initInFlight;

  final LinkedHashMap<String, _CachedLeafContext> _leafCache =
      LinkedHashMap<String, _CachedLeafContext>();
  final Map<String, Future<SecurityContext>> _pendingLeaves =
      <String, Future<SecurityContext>>{};

  String get certPath =>
      '${_stripTrailingSep(storageDir)}${Platform.pathSeparator}$certFileName';
  String get keyPath =>
      '${_stripTrailingSep(storageDir)}${Platform.pathSeparator}$keyFileName';

  bool get isInitialized =>
      _caKeyPair != null && _caCertDer.isNotEmpty && _caCertPem.isNotEmpty;

  Uint8List get caCertDer => Uint8List.fromList(_caCertDer);
  String get caCertPem => _caCertPem;
  String get caSha1Hex => _caSha1Hex;
  String get caSha256Hex => _caSha256Hex;

  static String _stripTrailingSep(String dir) {
    final String sep = Platform.pathSeparator;
    return dir.endsWith(sep) ? dir.substring(0, dir.length - sep.length) : dir;
  }

  /// آماده سازی گواهی ریشه محلی؛ اگر از پیش روی دیسک موجود و معتبر باشد همان
  /// بارگذاری می شود تا گواهی نصب شده کاربر در سیستم عامل معتبر بماند.
  Future<void> ensureInitialized() {
    if (isInitialized) {
      return Future<void>.value();
    }
    return _initInFlight ??= _initializeInternal();
  }

  Future<void> _initializeInternal() async {
    try {
      await Directory(storageDir).create(recursive: true);
      final File certFile = File(certPath);
      final File keyFile = File(keyPath);
      if (await certFile.exists() && await keyFile.exists()) {
        final String certPem = await certFile.readAsString();
        final String keyPem = await keyFile.readAsString();
        final _EcP256KeyPair? loadedKey = _parsePkcs8EcPrivateKeyPem(keyPem);
        final Uint8List? loadedDer = _parsePemBlock(certPem, 'CERTIFICATE');
        if (loadedKey != null &&
            loadedDer != null &&
            loadedDer.length > 64 &&
            _derPublicKeyMatches(loadedDer, loadedKey.uncompressedPublicKey)) {
          _applyCaMaterial(loadedKey, loadedDer, certPem);
          return;
        }
      }
      await _generateAndPersistFreshCa();
    } finally {
      _initInFlight = null;
    }
  }

  /// تولید دوباره گواهی ریشه جدید و پاک سازی کش گواهی های برگ.
  Future<void> regenerate() async {
    _leafCache.clear();
    _pendingLeaves.clear();
    await Directory(storageDir).create(recursive: true);
    await _generateAndPersistFreshCa();
  }

  Future<void> _generateAndPersistFreshCa() async {
    final _EcP256KeyPair keyPair = _EcP256.generateKeyPair();
    final DateTime now = DateTime.now().toUtc();
    final Uint8List ski = Uint8List.fromList(
      sha1.convert(keyPair.uncompressedPublicKey).bytes,
    );
    final Uint8List caNameDer = _encodeX509Name(
      organization: organization,
      organizationalUnit: organizationalUnit,
      commonName: commonName,
    );
    final Uint8List tbs = _derSequence(<Uint8List>[
      _derExplicit(0, _derIntegerInt(2)), // v3
      _derUnsignedInteger(_randomSerial()),
      _algIdEcdsaSha256,
      caNameDer,
      _derSequence(<Uint8List>[
        _derAsn1Time(now.subtract(const Duration(days: 1))),
        _derAsn1Time(now.add(const Duration(days: 3650))),
      ]),
      caNameDer,
      _encodeSubjectPublicKeyInfo(keyPair.uncompressedPublicKey),
      _derExplicit(
        3,
        _derSequence(<Uint8List>[
          // Basic Constraints: CA:TRUE, pathlen:0 (critical)
          _encodeExtension(
            _oidBasicConstraints,
            _derSequence(<Uint8List>[
              _derBoolean(true),
              _derIntegerInt(0),
            ]),
            critical: true,
          ),
          // Key Usage: digitalSignature (bit 0) + keyCertSign (bit 5) + cRLSign (bit 6)
          _encodeExtension(
            _oidKeyUsage,
            _derBitString(Uint8List.fromList(<int>[0x86]), unusedBits: 1),
            critical: true,
          ),
          _encodeExtension(_oidSubjectKeyId, _derOctetString(ski)),
        ]),
      ),
    ]);

    final Uint8List certDer = _signTbsCertificate(tbs, keyPair);
    final String certPem = _encodePem('CERTIFICATE', certDer);
    final String keyPem = _encodePkcs8EcPrivateKeyPem(keyPair);

    await File(certPath).writeAsString(certPem, flush: true);
    await File(keyPath).writeAsString(keyPem, flush: true);
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', <String>['600', keyPath]);
      } catch (_) {}
    }
    _applyCaMaterial(keyPair, certDer, certPem);
  }

  void _applyCaMaterial(
    _EcP256KeyPair keyPair,
    Uint8List certDer,
    String certPem,
  ) {
    _caKeyPair = keyPair;
    _caCertDer = certDer;
    _caCertPem = certPem.endsWith('\n') ? certPem : '$certPem\n';
    _caSki = Uint8List.fromList(
      sha1.convert(keyPair.uncompressedPublicKey).bytes,
    );
    _caSha1Hex = sha1.convert(certDer).toString().toLowerCase();
    _caSha256Hex = sha256.convert(certDer).toString().toLowerCase();
  }

  /// صدور یا بازیابی فوری [SecurityContext] اختصاصی با گواهی امضاشده برای هاست.
  Future<SecurityContext> securityContextForHost(String rawHost) async {
    await ensureInitialized();
    final String host = normalizeHost(rawHost);
    if (host.isEmpty) {
      throw const FormatException('Empty host for TLS certificate');
    }

    final DateTime now = DateTime.now().toUtc();
    final _CachedLeafContext? existing = _leafCache.remove(host);
    if (existing != null &&
        existing.expiresAt.isAfter(now.add(const Duration(days: 3)))) {
      _leafCache[host] = existing;
      return existing.context;
    }

    final Future<SecurityContext>? inFlight = _pendingLeaves[host];
    if (inFlight != null) {
      return inFlight;
    }

    final Future<SecurityContext> work = _buildLeafContext(host, now);
    _pendingLeaves[host] = work;
    try {
      return await work;
    } finally {
      _pendingLeaves.remove(host);
    }
  }

  /// تولید جفت کلید + زنجیره PEM خام برای تست یا استفاده مستقیم.
  Future<({String leafCertPem, String chainPem, String keyPem})>
      issueLeafPemForHost(String rawHost) async {
    await ensureInitialized();
    final String host = normalizeHost(rawHost);
    if (host.isEmpty) {
      throw const FormatException('Empty host for TLS certificate');
    }
    final _IssuedLeaf leaf = _issueLeafMaterial(host, DateTime.now().toUtc());
    return (
      leafCertPem: leaf.leafPem,
      chainPem: '${leaf.leafPem}$_caCertPem',
      keyPem: leaf.keyPem,
    );
  }

  Future<SecurityContext> _buildLeafContext(String host, DateTime now) async {
    final _IssuedLeaf leaf = _issueLeafMaterial(host, now);
    final SecurityContext ctx = SecurityContext(withTrustedRoots: false);
    ctx.useCertificateChainBytes(utf8.encode('${leaf.leafPem}$_caCertPem'));
    ctx.usePrivateKeyBytes(utf8.encode(leaf.keyPem));

    while (_leafCache.length >= maxCachedLeaves) {
      _leafCache.remove(_leafCache.keys.first);
    }
    _leafCache[host] = _CachedLeafContext(
      context: ctx,
      expiresAt: leaf.notAfter,
    );
    return ctx;
  }

  _IssuedLeaf _issueLeafMaterial(String host, DateTime now) {
    final _EcP256KeyPair? caKey = _caKeyPair;
    if (caKey == null) {
      throw StateError('LocalCaManager not initialized');
    }
    final _EcP256KeyPair leafKey = _EcP256.generateKeyPair();
    final Uint8List leafSki = Uint8List.fromList(
      sha1.convert(leafKey.uncompressedPublicKey).bytes,
    );
    final DateTime notBefore = now.subtract(const Duration(days: 1));
    // حداکثر بازه اعتبار ۳۹۵ روز برای انطباق کامل با قوانین مرورگرهای ۲۰۲۵/۲۰۲۶.
    final DateTime notAfter = now.add(const Duration(days: 395));

    final InternetAddress? parsedIp = InternetAddress.tryParse(host);
    final List<Uint8List> sanEntries = <Uint8List>[
      if (parsedIp != null)
        _derContextSpecificPrimitive(7, parsedIp.rawAddress)
      else
        _derContextSpecificPrimitive(2, Uint8List.fromList(utf8.encode(host))),
    ];

    final Uint8List caNameDer = _encodeX509Name(
      organization: organization,
      organizationalUnit: organizationalUnit,
      commonName: commonName,
    );
    final Uint8List leafSubjectDer = _encodeX509Name(
      organization: organization,
      organizationalUnit: organizationalUnit,
      commonName: host.length > 60 ? host.substring(0, 60) : host,
    );

    final Uint8List tbs = _derSequence(<Uint8List>[
      _derExplicit(0, _derIntegerInt(2)),
      _derUnsignedInteger(_randomSerial()),
      _algIdEcdsaSha256,
      caNameDer,
      _derSequence(<Uint8List>[
        _derAsn1Time(notBefore),
        _derAsn1Time(notAfter),
      ]),
      leafSubjectDer,
      _encodeSubjectPublicKeyInfo(leafKey.uncompressedPublicKey),
      _derExplicit(
        3,
        _derSequence(<Uint8List>[
          _encodeExtension(
            _oidBasicConstraints,
            _derSequence(const <Uint8List>[]),
            critical: true,
          ),
          // برای کلید ECDSA در TLS فقط digitalSignature تنظیم می شود.
          _encodeExtension(
            _oidKeyUsage,
            _derBitString(Uint8List.fromList(<int>[0x80]), unusedBits: 7),
            critical: true,
          ),
          _encodeExtension(
            _oidExtKeyUsage,
            _derSequence(<Uint8List>[_oidServerAuth]),
          ),
          _encodeExtension(
            _oidSubjectAltName,
            _derSequence(sanEntries),
          ),
          _encodeExtension(_oidSubjectKeyId, _derOctetString(leafSki)),
          _encodeExtension(
            _oidAuthorityKeyId,
            _derSequence(<Uint8List>[
              _derContextSpecificPrimitive(0, _caSki),
            ]),
          ),
        ]),
      ),
    ]);

    final Uint8List certDer = _signTbsCertificate(tbs, caKey);
    return _IssuedLeaf(
      leafPem: _encodePem('CERTIFICATE', certDer),
      keyPem: _encodePkcs8EcPrivateKeyPem(leafKey),
      notAfter: notAfter,
    );
  }

  static String normalizeHost(String raw) {
    String host = raw.trim().toLowerCase();
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    while (host.endsWith('.')) {
      host = host.substring(0, host.length - 1);
    }
    return host;
  }

  // ── امضا و کدگذاری ASN.1 DER / X.509 ────────────────────────────────────

  static final Uint8List _oidEcPublicKey = _derOid(<int>[1, 2, 840, 10045, 2, 1]);
  static final Uint8List _oidPrime256v1 =
      _derOid(<int>[1, 2, 840, 10045, 3, 1, 7]);
  static final Uint8List _oidEcdsaWithSha256 =
      _derOid(<int>[1, 2, 840, 10045, 4, 3, 2]);
  static final Uint8List _oidCommonName = _derOid(<int>[2, 5, 4, 3]);
  static final Uint8List _oidOrganization = _derOid(<int>[2, 5, 4, 10]);
  static final Uint8List _oidOrganizationalUnit = _derOid(<int>[2, 5, 4, 11]);
  static final Uint8List _oidSubjectKeyId = _derOid(<int>[2, 5, 29, 14]);
  static final Uint8List _oidKeyUsage = _derOid(<int>[2, 5, 29, 15]);
  static final Uint8List _oidSubjectAltName = _derOid(<int>[2, 5, 29, 17]);
  static final Uint8List _oidBasicConstraints = _derOid(<int>[2, 5, 29, 19]);
  static final Uint8List _oidAuthorityKeyId = _derOid(<int>[2, 5, 29, 35]);
  static final Uint8List _oidExtKeyUsage = _derOid(<int>[2, 5, 29, 37]);
  static final Uint8List _oidServerAuth =
      _derOid(<int>[1, 3, 6, 1, 5, 5, 7, 3, 1]);

  static final Uint8List _algIdEcdsaSha256 =
      _derSequence(<Uint8List>[_oidEcdsaWithSha256]);
  static final Uint8List _algIdEcP256 =
      _derSequence(<Uint8List>[_oidEcPublicKey, _oidPrime256v1]);

  static Uint8List _signTbsCertificate(Uint8List tbs, _EcP256KeyPair signer) {
    final ({BigInt r, BigInt s}) sig = _EcP256.signSha256(signer.d, tbs);
    final Uint8List sigDer = _derSequence(<Uint8List>[
      _derUnsignedInteger(_bigIntToBytes(sig.r)),
      _derUnsignedInteger(_bigIntToBytes(sig.s)),
    ]);
    return _derSequence(<Uint8List>[
      tbs,
      _algIdEcdsaSha256,
      _derBitString(sigDer),
    ]);
  }

  static Uint8List _encodeSubjectPublicKeyInfo(Uint8List uncompressedPoint) {
    return _derSequence(<Uint8List>[
      _algIdEcP256,
      _derBitString(uncompressedPoint),
    ]);
  }

  static Uint8List _encodeX509Name({
    required String organization,
    required String organizationalUnit,
    required String commonName,
  }) {
    return _derSequence(<Uint8List>[
      _derSet(<Uint8List>[
        _derSequence(<Uint8List>[_oidOrganization, _derUtf8String(organization)]),
      ]),
      _derSet(<Uint8List>[
        _derSequence(
            <Uint8List>[_oidOrganizationalUnit, _derUtf8String(organizationalUnit)]),
      ]),
      _derSet(<Uint8List>[
        _derSequence(<Uint8List>[_oidCommonName, _derUtf8String(commonName)]),
      ]),
    ]);
  }

  static Uint8List _encodeExtension(
    Uint8List oidDer,
    Uint8List valueDer, {
    bool critical = false,
  }) {
    return _derSequence(<Uint8List>[
      oidDer,
      if (critical) _derBoolean(true),
      _derOctetString(valueDer),
    ]);
  }

  static String _encodePkcs8EcPrivateKeyPem(_EcP256KeyPair kp) {
    final Uint8List dBytes = _bigIntToFixedBytes(kp.d, 32);
    final Uint8List sec1 = _derSequence(<Uint8List>[
      _derIntegerInt(1),
      _derOctetString(dBytes),
      _derExplicit(1, _derBitString(kp.uncompressedPublicKey)),
    ]);
    final Uint8List pkcs8 = _derSequence(<Uint8List>[
      _derIntegerInt(0),
      _algIdEcP256,
      _derOctetString(sec1),
    ]);
    return _encodePem('PRIVATE KEY', pkcs8);
  }

  static _EcP256KeyPair? _parsePkcs8EcPrivateKeyPem(String pem) {
    final Uint8List? der = _parsePemBlock(pem, 'PRIVATE KEY');
    if (der == null || der.length < 48) return null;
    try {
      final _DerNode root = _DerReader(der).readNext();
      if (root.tag != 0x30) return null;
      final List<_DerNode> top = _DerReader(root.value).readAll();
      if (top.length < 3 || top[2].tag != 0x04) return null;
      final _DerNode sec1 = _DerReader(top[2].value).readNext();
      if (sec1.tag != 0x30) return null;
      final List<_DerNode> fields = _DerReader(sec1.value).readAll();
      if (fields.length < 2 || fields[1].tag != 0x04) return null;
      final BigInt d = _bytesToBigInt(fields[1].value);
      if (d < BigInt.one || d >= _EcP256.n) return null;
      return _EcP256.fromPrivateScalar(d);
    } catch (_) {
      return null;
    }
  }

  static bool _derPublicKeyMatches(Uint8List certDer, Uint8List expectedPub) {
    if (certDer.length < expectedPub.length) return false;
    for (int i = 0; i <= certDer.length - expectedPub.length; i++) {
      bool match = true;
      for (int j = 0; j < expectedPub.length; j++) {
        if (certDer[i + j] != expectedPub[j]) {
          match = false;
          break;
        }
      }
      if (match) return true;
    }
    return false;
  }

  static Uint8List _randomSerial() {
    final Random rng = Random.secure();
    final Uint8List out = Uint8List(16);
    // بایت اول غیرصفر و مثبت (بیت بالا 0) تا در DER همیشه 16 بایتی بماند.
    out[0] = 0x01 + rng.nextInt(0x7e);
    for (int i = 1; i < out.length; i++) {
      out[i] = rng.nextInt(256);
    }
    return out;
  }

  static String _encodePem(String label, Uint8List der) {
    final String b64 = base64Encode(der);
    final StringBuffer sb = StringBuffer('-----BEGIN $label-----\n');
    for (int i = 0; i < b64.length; i += 64) {
      final int end = min(i + 64, b64.length);
      sb.writeln(b64.substring(i, end));
    }
    sb.writeln('-----END $label-----');
    return sb.toString();
  }

  static Uint8List? _parsePemBlock(String pem, String label) {
    final String header = '-----BEGIN $label-----';
    final String footer = '-----END $label-----';
    final int start = pem.indexOf(header);
    if (start < 0) return null;
    final int end = pem.indexOf(footer, start + header.length);
    if (end < 0) return null;
    final String body = pem
        .substring(start + header.length, end)
        .replaceAll(RegExp(r'\s+'), '');
    if (body.isEmpty) return null;
    try {
      return Uint8List.fromList(base64Decode(body));
    } catch (_) {
      return null;
    }
  }

  static Uint8List _derTlv(int tag, Uint8List value) {
    final BytesBuilder out = BytesBuilder(copy: false)..addByte(tag);
    final int len = value.length;
    if (len < 0x80) {
      out.addByte(len);
    } else {
      final Uint8List lenBytes = _bigIntToBytes(BigInt.from(len));
      out.addByte(0x80 | lenBytes.length);
      out.add(lenBytes);
    }
    out.add(value);
    return out.takeBytes();
  }

  static Uint8List _derSequence(List<Uint8List> items) {
    final BytesBuilder b = BytesBuilder(copy: false);
    for (final Uint8List item in items) {
      b.add(item);
    }
    return _derTlv(0x30, b.takeBytes());
  }

  static Uint8List _derSet(List<Uint8List> items) {
    final BytesBuilder b = BytesBuilder(copy: false);
    for (final Uint8List item in items) {
      b.add(item);
    }
    return _derTlv(0x31, b.takeBytes());
  }

  static Uint8List _derExplicit(int tagNo, Uint8List inner) =>
      _derTlv(0xa0 | (tagNo & 0x1f), inner);

  static Uint8List _derContextSpecificPrimitive(int tagNo, Uint8List bytes) =>
      _derTlv(0x80 | (tagNo & 0x1f), bytes);

  static Uint8List _derBoolean(bool val) =>
      _derTlv(0x01, Uint8List.fromList(<int>[val ? 0xff : 0x00]));

  static Uint8List _derIntegerInt(int v) =>
      _derUnsignedInteger(_bigIntToBytes(BigInt.from(v)));

  static Uint8List _derUnsignedInteger(Uint8List raw) {
    int offset = 0;
    while (offset < raw.length - 1 && raw[offset] == 0) {
      offset++;
    }
    final Uint8List trimmed =
        raw.isEmpty ? Uint8List.fromList(<int>[0]) : raw.sublist(offset);
    if ((trimmed[0] & 0x80) != 0) {
      final Uint8List padded = Uint8List(trimmed.length + 1);
      padded[0] = 0;
      padded.setRange(1, padded.length, trimmed);
      return _derTlv(0x02, padded);
    }
    return _derTlv(0x02, trimmed);
  }

  static Uint8List _derBitString(Uint8List bytes, {int unusedBits = 0}) {
    final Uint8List out = Uint8List(bytes.length + 1);
    out[0] = unusedBits & 0x07;
    out.setRange(1, out.length, bytes);
    return _derTlv(0x03, out);
  }

  static Uint8List _derOctetString(Uint8List bytes) => _derTlv(0x04, bytes);

  static Uint8List _derUtf8String(String s) =>
      _derTlv(0x0c, Uint8List.fromList(utf8.encode(s)));

  static Uint8List _derAsn1Time(DateTime utc) {
    final DateTime dt = utc.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    final String rest =
        '${two(dt.month)}${two(dt.day)}${two(dt.hour)}${two(dt.minute)}${two(dt.second)}Z';
    if (dt.year >= 1950 && dt.year <= 2049) {
      final String yy = two(dt.year % 100);
      return _derTlv(0x17, Uint8List.fromList(ascii.encode('$yy$rest')));
    }
    final String yyyy = dt.year.toString().padLeft(4, '0');
    return _derTlv(0x18, Uint8List.fromList(ascii.encode('$yyyy$rest')));
  }

  static Uint8List _derOid(List<int> arcs) {
    final BytesBuilder out = BytesBuilder(copy: false)
      ..addByte(40 * arcs[0] + arcs[1]);
    for (int i = 2; i < arcs.length; i++) {
      int v = arcs[i];
      if (v == 0) {
        out.addByte(0);
        continue;
      }
      final List<int> parts = <int>[v & 0x7f];
      v >>= 7;
      while (v > 0) {
        parts.add((v & 0x7f) | 0x80);
        v >>= 7;
      }
      for (int j = parts.length - 1; j >= 0; j--) {
        out.addByte(parts[j]);
      }
    }
    return _derTlv(0x06, out.takeBytes());
  }

  static Uint8List _bigIntToBytes(BigInt value) {
    if (value == BigInt.zero) {
      return Uint8List.fromList(<int>[0]);
    }
    BigInt v = value;
    final List<int> bytes = <int>[];
    final BigInt mask = BigInt.from(0xff);
    while (v > BigInt.zero) {
      bytes.add((v & mask).toInt());
      v = v >> 8;
    }
    return Uint8List.fromList(bytes.reversed.toList(growable: false));
  }

  static Uint8List _bigIntToFixedBytes(BigInt value, int size) {
    final Uint8List raw = _bigIntToBytes(value);
    if (raw.length == size) return raw;
    if (raw.length > size) return raw.sublist(raw.length - size);
    final Uint8List out = Uint8List(size);
    out.setRange(size - raw.length, size, raw);
    return out;
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    BigInt acc = BigInt.zero;
    for (final int b in bytes) {
      acc = (acc << 8) | BigInt.from(b);
    }
    return acc;
  }
}

class _CachedLeafContext {
  const _CachedLeafContext({
    required this.context,
    required this.expiresAt,
  });

  final SecurityContext context;
  final DateTime expiresAt;
}

class _IssuedLeaf {
  const _IssuedLeaf({
    required this.leafPem,
    required this.keyPem,
    required this.notAfter,
  });

  final String leafPem;
  final String keyPem;
  final DateTime notAfter;
}

class _EcP256KeyPair {
  const _EcP256KeyPair({
    required this.d,
    required this.x,
    required this.y,
    required this.uncompressedPublicKey,
  });

  final BigInt d;
  final BigInt x;
  final BigInt y;
  final Uint8List uncompressedPublicKey;
}

class _JacobianPoint {
  const _JacobianPoint(this.x, this.y, this.z);

  final BigInt x;
  final BigInt y;
  final BigInt z;

  static final _JacobianPoint infinity =
      _JacobianPoint(BigInt.zero, BigInt.one, BigInt.zero);
}

/// پیاده سازی خالص NIST P-256 (`secp256r1`) + RFC 6979 HMAC-SHA256.
class _EcP256 {
  static final BigInt p = BigInt.parse(
    'ffffffff00000001000000000000000000000000ffffffffffffffffffffffff',
    radix: 16,
  );
  static final BigInt gx = BigInt.parse(
    '6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296',
    radix: 16,
  );
  static final BigInt gy = BigInt.parse(
    '4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5',
    radix: 16,
  );
  static final BigInt n = BigInt.parse(
    'ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551',
    radix: 16,
  );
  static final BigInt _halfN = n >> 1;
  static final BigInt _two = BigInt.from(2);
  static final BigInt _three = BigInt.from(3);
  static final BigInt _four = BigInt.from(4);
  static final BigInt _eight = BigInt.from(8);

  static BigInt _modP(BigInt v) {
    final BigInt r = v % p;
    return r.isNegative ? r + p : r;
  }

  static BigInt _modN(BigInt v) {
    final BigInt r = v % n;
    return r.isNegative ? r + n : r;
  }

  static _JacobianPoint _double(_JacobianPoint pt) {
    if (pt.z == BigInt.zero || pt.y == BigInt.zero) {
      return _JacobianPoint.infinity;
    }
    final BigInt delta = _modP(pt.z * pt.z);
    final BigInt gamma = _modP(pt.y * pt.y);
    final BigInt beta = _modP(pt.x * gamma);
    final BigInt alpha = _modP(_three * (pt.x - delta) * (pt.x + delta));
    final BigInt x3 = _modP(alpha * alpha - _eight * beta);
    final BigInt yPlusZ = pt.y + pt.z;
    final BigInt z3 = _modP(yPlusZ * yPlusZ - gamma - delta);
    final BigInt y3 = _modP(
      alpha * (_four * beta - x3) - _eight * _modP(gamma * gamma),
    );
    return _JacobianPoint(x3, y3, z3);
  }

  static _JacobianPoint _add(_JacobianPoint p1, _JacobianPoint p2) {
    if (p1.z == BigInt.zero) return p2;
    if (p2.z == BigInt.zero) return p1;

    final BigInt z1z1 = _modP(p1.z * p1.z);
    final BigInt z2z2 = _modP(p2.z * p2.z);
    final BigInt u1 = _modP(p1.x * z2z2);
    final BigInt u2 = _modP(p2.x * z1z1);
    final BigInt s1 = _modP(p1.y * p2.z * z2z2);
    final BigInt s2 = _modP(p2.y * p1.z * z1z1);
    if (u1 == u2) {
      return s1 == s2 ? _double(p1) : _JacobianPoint.infinity;
    }
    final BigInt h = _modP(u2 - u1);
    final BigInt i = _modP(_four * h * h);
    final BigInt j = _modP(h * i);
    final BigInt r = _modP(_two * (s2 - s1));
    final BigInt v = _modP(u1 * i);
    final BigInt x3 = _modP(r * r - j - _two * v);
    final BigInt y3 = _modP(r * (v - x3) - _two * s1 * j);
    final BigInt zSum = p1.z + p2.z;
    final BigInt z3 = _modP((zSum * zSum - z1z1 - z2z2) * h);
    return _JacobianPoint(x3, y3, z3);
  }

  static ({BigInt x, BigInt y}) _scalarMultGenerator(BigInt k) {
    _JacobianPoint acc = _JacobianPoint.infinity;
    _JacobianPoint cur = _JacobianPoint(gx, gy, BigInt.one);
    BigInt rem = k;
    while (rem > BigInt.zero) {
      if (rem.isOdd) {
        acc = _add(acc, cur);
      }
      cur = _double(cur);
      rem = rem >> 1;
    }
    final BigInt zInv = acc.z.modInverse(p);
    final BigInt zInv2 = _modP(zInv * zInv);
    return (
      x: _modP(acc.x * zInv2),
      y: _modP(acc.y * zInv2 * zInv),
    );
  }

  static _EcP256KeyPair generateKeyPair() {
    final Random rng = Random.secure();
    while (true) {
      final Uint8List raw = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        raw[i] = rng.nextInt(256);
      }
      final BigInt d = LocalCaManager._bytesToBigInt(raw);
      if (d >= BigInt.one && d < n) {
        return fromPrivateScalar(d);
      }
    }
  }

  static _EcP256KeyPair fromPrivateScalar(BigInt d) {
    final ({BigInt x, BigInt y}) pt = _scalarMultGenerator(d);
    final Uint8List pub = Uint8List(65);
    pub[0] = 0x04;
    pub.setRange(1, 33, LocalCaManager._bigIntToFixedBytes(pt.x, 32));
    pub.setRange(33, 65, LocalCaManager._bigIntToFixedBytes(pt.y, 32));
    return _EcP256KeyPair(
      d: d,
      x: pt.x,
      y: pt.y,
      uncompressedPublicKey: pub,
    );
  }

  static ({BigInt r, BigInt s}) signSha256(BigInt d, Uint8List message) {
    final Uint8List digest = Uint8List.fromList(sha256.convert(message).bytes);
    final BigInt z = _modN(LocalCaManager._bytesToBigInt(digest));
    final Uint8List dBytes = LocalCaManager._bigIntToFixedBytes(d, 32);

    Uint8List v = Uint8List(32)..fillRange(0, 32, 0x01);
    Uint8List k = Uint8List(32);

    k = _hmacSha256(k, <int>[...v, 0x00, ...dBytes, ...digest]);
    v = _hmacSha256(k, v);
    k = _hmacSha256(k, <int>[...v, 0x01, ...dBytes, ...digest]);
    v = _hmacSha256(k, v);

    while (true) {
      v = _hmacSha256(k, v);
      final BigInt cand = LocalCaManager._bytesToBigInt(v);
      if (cand >= BigInt.one && cand < n) {
        final BigInt r = _modN(_scalarMultGenerator(cand).x);
        if (r != BigInt.zero) {
          BigInt s = _modN(cand.modInverse(n) * (z + r * d));
          if (s > _halfN) {
            s = n - s;
          }
          if (s != BigInt.zero) {
            return (r: r, s: s);
          }
        }
      }
      k = _hmacSha256(k, <int>[...v, 0x00]);
      v = _hmacSha256(k, v);
    }
  }

  static Uint8List _hmacSha256(List<int> key, List<int> data) {
    final Hmac mac = Hmac(sha256, key);
    return Uint8List.fromList(mac.convert(data).bytes);
  }
}

class _DerNode {
  const _DerNode(this.tag, this.value);

  final int tag;
  final Uint8List value;
}

class _DerReader {
  _DerReader(this.data);

  final Uint8List data;
  int offset = 0;

  _DerNode readNext() {
    if (offset >= data.length) {
      throw const FormatException('Unexpected end of DER');
    }
    final int tag = data[offset++];
    if (offset >= data.length) {
      throw const FormatException('Truncated DER length');
    }
    int len = data[offset++];
    if ((len & 0x80) != 0) {
      final int numBytes = len & 0x7f;
      if (numBytes == 0 || numBytes > 4 || offset + numBytes > data.length) {
        throw const FormatException('Invalid DER length');
      }
      len = 0;
      for (int i = 0; i < numBytes; i++) {
        len = (len << 8) | data[offset++];
      }
    }
    if (len < 0 || offset + len > data.length) {
      throw const FormatException('DER value out of bounds');
    }
    final Uint8List value = data.sublist(offset, offset + len);
    offset += len;
    return _DerNode(tag, value);
  }

  List<_DerNode> readAll() {
    final List<_DerNode> out = <_DerNode>[];
    while (offset < data.length) {
      out.add(readNext());
    }
    return out;
  }
}
