import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbrella_vpn/core/app_config.dart';
import 'package:umbrella_vpn/core/storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalStore.instance.init();
  });

  group('AppConfig Android invariants', () {
    test('pins expected package ID, ports, and TUN defaults', () {
      expect(AppConfig.version, '1.0.1');
      expect(AppConfig.buildNumber, 2);
      expect(AppConfig.androidPackageId, 'ir.umbrella.vpn');
      expect(AppConfig.tunAdapterHint, 'tun0');
      expect(AppConfig.coreGrpcPort, 17078);
      expect(AppConfig.coreUtilityGrpcPort, 17079);
      expect(AppConfig.coreClashPort, 16756);
      expect(AppConfig.httpPortUmbrella, 12334);
      expect(AppConfig.defaultMtu, 9000);
      expect(
        AppConfig.releasesListApiUrl,
        contains('armin-soft/Umbrella-VPN-Releases'),
      );
      expect(AppConfig.routes, containsAll(<String>[
        'auth/start',
        'auth/verify',
        'auth/device',
        'filter/get',
        'filter/save',
      ]));
    });
  });

  group('LocalStore', () {
    test('round-trips primitives, JSON maps, and JSON lists safely', () async {
      final LocalStore store = LocalStore.instance;
      expect(store.isReady, isTrue);

      await store.write('test.str', 'umbrella');
      expect(store.read('test.str'), 'umbrella');

      await store.writeBool('test.bool', true);
      expect(store.readBool('test.bool'), isTrue);

      await store.writeInt('test.int', 42);
      expect(store.readInt('test.int'), 42);

      await store.writeJson('test.json', <String, dynamic>{
        'mode': 'vpn',
        'port': 12334,
      });
      expect(store.readJson('test.json'), <String, dynamic>{
        'mode': 'vpn',
        'port': 12334,
      });

      await store.writeJsonList('test.list', <dynamic>['org.telegram.messenger']);
      expect(store.readJsonList('test.list'), <dynamic>['org.telegram.messenger']);

      await store.write('test.corrupt', '{bad-json');
      expect(store.readJson('test.corrupt'), isEmpty);
      expect(store.readJsonList('test.corrupt'), isEmpty);
    });
  });
}
