import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:umbrella_vpn/core/theme.dart';
import 'package:umbrella_vpn/models/models.dart';
import 'package:umbrella_vpn/state/auth_controller.dart';
import 'package:umbrella_vpn/state/subscription_controller.dart';
import 'package:umbrella_vpn/state/toast_controller.dart';
import 'package:umbrella_vpn/ui/pages/account_page.dart';
import 'package:umbrella_vpn/vpn/vpn_controller.dart';

class _TestAuth extends ChangeNotifier implements AuthController {
  _TestAuth(this.accountValue);

  Account accountValue;

  @override
  Account get account => accountValue;
  @override
  bool get signedIn => false;
  @override
  bool? get botLinked => true;
  @override
  SubscriptionOffers get offers => const SubscriptionOffers();
  @override
  List<SubscriptionPlan> get subscriptionPlans => const <SubscriptionPlan>[
        SubscriptionPlan(
          month: '1m',
          name: 'پلن آزمایشی',
          days: 30,
          price: 100000,
        ),
      ];
  @override
  int get walletBalance => 1250;
  @override
  double get walletExactBalance => 1250.5;
  @override
  bool get walletLoaded => true;
  @override
  bool get walletBusy => false;
  @override
  bool get walletPaymentPending => false;
  @override
  bool get walletTopupPending => false;
  @override
  double get walletPendingCredit => 0;
  @override
  double get walletPendingAmount => 0;
  @override
  String get walletCheckoutUrl => '';
  @override
  int get walletMinTopup => 80000;
  @override
  int get walletMaxTopup => 100000000;
  @override
  bool get loadingSubscriptionPlans => false;
  @override
  bool get purchasingSubscription => false;
  @override
  CustomSubscriptionTerms? get customSubscriptionTerms => null;
  @override
  bool get claimingOffer => false;
  @override
  String get claimingPlanType => '';
  @override
  bool get linkingBot => false;
  @override
  String get error => '';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestVpn extends ChangeNotifier implements VpnController {
  @override
  VpnStatus get status => VpnStatus.disconnected;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('account tabs separate content, hide active renewal, and omit panel ID',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(980, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final DateTime now = DateTime.now();
    final _TestAuth auth = _TestAuth(
      Account(
        panelId: 7654321,
        uuid: 'abcd1234-5678-9876',
        name: 'کاربر آزمایشی',
        phone: '09120000000',
        telegramId: '1234567',
        isActive: true,
        usageLimitGb: 100,
        currentUsageGb: 12,
        packageDays: 30,
        startDate: now.subtract(const Duration(days: 10)),
        expiryDate: now.add(const Duration(days: 30)),
      ),
    );
    final _TestVpn vpn = _TestVpn();
    final SubscriptionController subscriptions = SubscriptionController(
      vpn: vpn,
      auth: auth,
      client: MockClient((http.Request _) async => http.Response('{}', 200)),
    );
    final ToastController toasts = ToastController();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      subscriptions.dispose();
      auth.dispose();
      vpn.dispose();
      toasts.dispose();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ChangeNotifierProvider<SubscriptionController>.value(
            value: subscriptions,
          ),
          ChangeNotifierProvider<ToastController>.value(value: toasts),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: AccountPage()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const PageStorageKey<String>('account-tab-content-summary')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('account-wallet-card')),
        findsNothing);
    expect(find.byKey(const ValueKey<String>('account-active-subscription')),
        findsNothing);

    final Finder walletTab =
        find.byKey(const ValueKey<String>('account-tab-wallet'));
    await tester.ensureVisible(walletTab);
    await tester.pumpAndSettle();
    await tester.tap(walletTab);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('account-wallet-card')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('account-wallet-balance')),
        findsOneWidget);
    expect(find.byKey(const PageStorageKey<String>('account-tab-content-wallet')),
        findsOneWidget);

    final Finder subscriptionTab =
        find.byKey(const ValueKey<String>('account-tab-subscription'));
    await tester.ensureVisible(subscriptionTab);
    await tester.pumpAndSettle();
    await tester.tap(subscriptionTab);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('account-active-subscription')),
        findsOneWidget);
    expect(find.text('خرید و تمدید اشتراک'), findsNothing);
    expect(find.text('تمدید اشتراک'), findsNothing);
    expect(find.text('پلن آزمایشی'), findsNothing);

    auth.accountValue = auth.accountValue.copyWith(
      isActive: true,
      expiryDate: now.subtract(const Duration(days: 1)),
    );
    auth.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('account-active-subscription')),
        findsNothing);
    expect(find.text('تمدید اشتراک'), findsOneWidget);
    expect(find.text('پلن آزمایشی'), findsOneWidget);

    final Finder profileTab =
        find.byKey(const ValueKey<String>('account-tab-profile'));
    await tester.ensureVisible(profileTab);
    await tester.pumpAndSettle();
    await tester.tap(profileTab);
    await tester.pumpAndSettle();
    expect(find.text('شناسه یکتای حساب'), findsOneWidget);
    expect(find.text('شناسه عددی تلگرام'), findsOneWidget);
    expect(find.text('شماره کاربری در پنل'), findsNothing);
    expect(find.textContaining('کاربر شماره'), findsNothing);
    expect(
      find.byKey(const PageStorageKey<String>('account-tab-content-profile')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
