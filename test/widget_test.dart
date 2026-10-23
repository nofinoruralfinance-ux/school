import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:intl/intl.dart';
import 'package:ntccsl/main.dart';
import 'package:ntccsl/pages/deposit_account_page.dart';
import 'package:ntccsl/pages/login_page.dart';
import 'package:ntccsl/pages/profile_page.dart';
import 'package:ntccsl/pages/register_page.dart';
import 'package:ntccsl/pages/splash_page.dart';
import 'package:ntccsl/services/api_service.dart';
import 'package:ntccsl/widgets/portal_loading.dart';
import 'package:ntccsl/widgets/portal_widgets.dart';
import 'package:ntccsl/widgets/profile_image.dart';

const _packageInfoChannel =
    MethodChannel('dev.fluttercommunity.plus/package_info');

void _mockPackageInfo() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    _packageInfoChannel,
    (call) async => <String, dynamic>{
      'appName': 'ntccsl',
      'packageName': 'ntccsl',
      'version': '1.2.2',
      'buildNumber': '2',
    },
  );
}

void main() {
  testWidgets('portal loading state uses the shared splash orbit loader',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PortalLoadingState(label: 'Loading accounts'),
      ),
    );

    expect(find.byKey(const Key('portal-loading-state')), findsOneWidget);
    expect(find.byType(PortalOrbitLoader), findsOneWidget);
    expect(find.text('Loading accounts'), findsOneWidget);
    expect(find.text('SECURE FINANCE PORTAL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('infinity loader animates and honors requested size',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: PortalOrbitLoader(
              key: Key('test-infinity-loader'),
              size: 64,
              semanticsLabel: 'Loading data',
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const Key('test-infinity-loader'))),
      const Size.square(64),
    );
    expect(find.bySemanticsLabel('Loading data'), findsOneWidget);
    final firstPainter = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byKey(const Key('test-infinity-loader')),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;

    await tester.pump(const Duration(milliseconds: 500));
    final nextPainter = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byKey(const Key('test-infinity-loader')),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    expect(firstPainter.shouldRepaint(nextPainter), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('portal loading feedback stays visible during async actions',
      (WidgetTester tester) async {
    final completion = Completer<void>();
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const Key('run-loading-action'),
              onPressed: () async {
                await withPortalLoading(
                  context,
                  label: 'Updating record',
                  action: () => completion.future,
                );
                finished = true;
              },
              child: const Text('Update'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('run-loading-action')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('portal-loading-state')), findsOneWidget);
    expect(find.text('Updating record'), findsOneWidget);
    expect(finished, isFalse);

    completion.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('portal-loading-state')), findsNothing);
    expect(finished, isTrue);
  });

  test('profile image data URLs use in-memory image providers', () {
    const image =
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jA9sAAAAASUVORK5CYII=';
    expect(profileImageProvider(image), isA<MemoryImage>());
    expect(profileImageProvider('data:image/png;base64,not-base64!'), isNull);
    expect(profileImageProvider('http://example.com/avatar.png'), isNull);
  });

  testWidgets('toastify styling distinguishes status and supports dismissal',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  key: const Key('show-success-toast'),
                  onPressed: () => showPortalToast(context, 'Saved.'),
                  child: const Text('Success'),
                ),
                TextButton(
                  key: const Key('show-error-toast'),
                  onPressed: () =>
                      showPortalToast(context, 'Failed.', isError: true),
                  child: const Text('Error'),
                ),
                TextButton(
                  key: const Key('show-delete-toast'),
                  onPressed: () => showPortalToast(
                    context,
                    'Deleted.',
                    isDestructive: true,
                  ),
                  child: const Text('Delete'),
                ),
                TextButton(
                  key: const Key('show-info-toast'),
                  onPressed: () =>
                      showPortalToast(context, 'Information.', isInfo: true),
                  child: const Text('Info'),
                ),
                TextButton(
                  key: const Key('show-warning-toast'),
                  onPressed: () => showPortalToast(
                    context,
                    'Warning.',
                    isWarning: true,
                  ),
                  child: const Text('Warning'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('show-success-toast')));
    await tester.pump();
    expect(
      tester.widget<Material>(find.byKey(const Key('portal-toast'))).color,
      Theme.of(tester.element(find.byKey(const Key('portal-toast'))))
          .colorScheme
          .surfaceContainerHigh,
    );
    expect(
      tester.widget<Icon>(find.byKey(const Key('portal-toast-icon'))).color,
      portalToastSuccessColor,
    );
    expect(
      tester
          .widget<Container>(find.byKey(const Key('portal-toast-timeout')))
          .color,
      portalToastSuccessColor,
    );
    expect(find.byKey(const Key('portal-toast-timeout')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('portal-toast-message')))
          .style
          ?.fontSize,
      Theme.of(tester.element(find.byKey(const Key('portal-toast-message'))))
          .textTheme
          .titleSmall
          ?.fontSize,
    );
    expect(
      tester.getSize(find.byKey(const Key('portal-toast-icon-container'))),
      const Size(48, 48),
    );

    await tester.tap(find.byKey(const Key('show-error-toast')));
    await tester.pump();
    expect(
      tester.widget<Material>(find.byKey(const Key('portal-toast'))).color,
      Theme.of(tester.element(find.byKey(const Key('portal-toast'))))
          .colorScheme
          .surfaceContainerHigh,
    );
    expect(
      tester.widget<Icon>(find.byKey(const Key('portal-toast-icon'))).color,
      portalToastErrorColor,
    );
    expect(
      tester
          .widget<Container>(find.byKey(const Key('portal-toast-timeout')))
          .color,
      portalToastErrorColor,
    );

    await tester.tap(find.byKey(const Key('show-delete-toast')));
    await tester.pump();
    expect(
      tester.widget<Material>(find.byKey(const Key('portal-toast'))).color,
      Theme.of(tester.element(find.byKey(const Key('portal-toast'))))
          .colorScheme
          .surfaceContainerHigh,
    );
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    await tester.tap(find.byKey(const Key('portal-toast-dismiss')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('portal-toast')), findsNothing);

    await tester.tap(find.byKey(const Key('show-info-toast')));
    await tester.pump();
    expect(
      tester.widget<Icon>(find.byKey(const Key('portal-toast-icon'))).color,
      portalToastInfoColor,
    );
    expect(
      tester
          .widget<Container>(find.byKey(const Key('portal-toast-timeout')))
          .color,
      portalToastInfoColor,
    );
    await tester.tap(find.byKey(const Key('portal-toast-dismiss')));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const Key('show-warning-toast')));
    await tester.pump();
    expect(
      tester.widget<Icon>(find.byKey(const Key('portal-toast-icon'))).color,
      portalToastWarningColor,
    );
    expect(
      tester
          .widget<Container>(find.byKey(const Key('portal-toast-timeout')))
          .color,
      portalToastWarningColor,
    );
    await tester.tap(find.byKey(const Key('portal-toast-dismiss')));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const Key('show-success-toast')));
    await tester.pump();
    expect(find.byKey(const Key('portal-toast')), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('portal-toast')), findsNothing);
  });

  testWidgets('registration has separate route and validates password',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(NtccslAccountApp(apiService: apiService));

    await tester.ensureVisible(find.byKey(const Key('open-register')));
    await tester.tap(find.byKey(const Key('open-register')));
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsOneWidget);
    expect(find.byKey(const Key('register-name')), findsOneWidget);
    expect(find.byKey(const Key('register-logo')), findsOneWidget);
    expect(find.text('NTCCSL FINANCE SYSTEM'), findsOneWidget);
    expect(find.text('Already have an account?'), findsOneWidget);
    expect(find.byKey(const Key('register-sign-in')), findsOneWidget);
    final signInButton = tester.widget<TextButton>(
      find.byKey(const Key('register-sign-in')),
    );
    expect(
      signInButton.style!.backgroundColor!.resolve({}),
      const Color(0xFF253B8C).withValues(alpha: .08),
    );
    expect(
      signInButton.style!.side!.resolve({})!.color,
      const Color(0xFF253B8C).withValues(alpha: .35),
    );
    final registerCard = tester.widget<Card>(
      find.byKey(const Key('register-account-card')),
    );
    final registerColors =
        Theme.of(tester.element(find.byType(RegisterPage))).colorScheme;
    expect(
      registerCard.color,
      Color.alphaBlend(
        const Color(0xFF253B8C).withValues(alpha: .07),
        registerColors.surface,
      ),
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('register-submit')))
          .style!
          .backgroundColor!
          .resolve({}),
      const Color(0xFF253B8C),
    );

    await tester.enterText(
        find.byKey(const Key('register-name')), 'Sam Member');
    await tester.enterText(
      find.byKey(const Key('register-email')),
      'sam@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('register-password')),
      'secure-pass',
    );
    await tester.enterText(
      find.byKey(const Key('register-confirm-password')),
      'different-pass',
    );
    await tester.ensureVisible(find.byKey(const Key('register-submit')));
    await tester.tap(find.byKey(const Key('register-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(apiService.didRegister, isFalse);

    await tester.enterText(
      find.byKey(const Key('register-confirm-password')),
      'secure-pass',
    );
    await tester.ensureVisible(find.byKey(const Key('register-submit')));
    await tester.tap(find.byKey(const Key('register-submit')));
    await tester.pumpAndSettle();
    expect(apiService.didRegister, isTrue);
    expect(
      find.text('Registration successful. You can now sign in.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<SegmentedButton<String>>(
            find.byKey(const Key('login-account-type')),
          )
          .selected,
      {'member'},
    );
  });

  testWidgets('registration sign-in link returns to login page',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      NtccslAccountApp(apiService: _FakeApiService()),
    );
    await tester.ensureVisible(find.byKey(const Key('open-register')));
    await tester.tap(find.byKey(const Key('open-register')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('register-sign-in')));
    await tester.tap(find.byKey(const Key('register-sign-in')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login-submit')), findsOneWidget);
    expect(find.byKey(const Key('register-name')), findsNothing);
  });

  testWidgets('registration accents adapt to light and dark themes',
      (WidgetTester tester) async {
    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF9EB4FF),
      brightness: Brightness.dark,
      surface: const Color(0xFF191B23),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: darkScheme,
          brightness: Brightness.dark,
        ),
        themeMode: ThemeMode.dark,
        home: RegisterPage(apiService: _FakeApiService()),
      ),
    );

    expect(
      tester
          .widget<Text>(find.byKey(const Key('register-system-name')))
          .style
          ?.color,
      darkScheme.primary,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('register-sign-in')))
          .style!
          .foregroundColor!
          .resolve({}),
      darkScheme.primary,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF3458D4),
            brightness: Brightness.light,
            surface: Colors.white,
          ),
          brightness: Brightness.light,
        ),
        themeMode: ThemeMode.light,
        home: RegisterPage(apiService: _FakeApiService()),
      ),
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('register-system-name')))
          .style
          ?.color,
      const Color(0xFF253B8C),
    );
  });

  testWidgets('login displays server error when login action is unsupported',
      (WidgetTester tester) async {
    final apiService = ApiService(
      client: _RecordingHttpClient([
        {'status': 'error', 'message': 'unknown post action'},
      ]),
    );
    await tester.pumpWidget(NtccslAccountApp(apiService: apiService));

    await tester.enterText(
      find.byKey(const Key('login-email')),
      'member@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'password123',
    );
    await tester.ensureVisible(find.byKey(const Key('login-submit')));
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('does not support email/password login yet'),
      findsOneWidget,
    );
    expect(find.text('Amount (Ledger)'), findsNothing);
  });

  testWidgets('registration button turns dark while creating account',
      (WidgetTester tester) async {
    final apiService = _PendingRegisterApiService();
    await tester.pumpWidget(
      MaterialApp(home: RegisterPage(apiService: apiService)),
    );
    await tester.enterText(
      find.byKey(const Key('register-name')),
      'Sam Member',
    );
    await tester.enterText(
      find.byKey(const Key('register-email')),
      'sam@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('register-password')),
      'secure-pass',
    );
    await tester.enterText(
      find.byKey(const Key('register-confirm-password')),
      'secure-pass',
    );

    await tester.ensureVisible(find.byKey(const Key('register-submit')));
    await tester.tap(find.byKey(const Key('register-submit')));
    await tester.pump();

    expect(find.text('Creating account…'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('register-submit')),
    );
    expect(button.onPressed, isNull);
    expect(
      button.style!.backgroundColor!.resolve({WidgetState.disabled}),
      const Color.fromARGB(255, 6, 9, 21),
    );

    apiService.completion.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('forgot password explains administrator reset process',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      NtccslAccountApp(apiService: _FakeApiService()),
    );

    await tester.ensureVisible(find.byKey(const Key('forgot-password')));
    await tester.tap(find.byKey(const Key('forgot-password')));
    await tester.pumpAndSettle();

    expect(find.text('Forgot your password?'), findsOneWidget);
    expect(find.textContaining('Contact your portal administrator'),
        findsOneWidget);
    expect(find.textContaining('existing passwords cannot be viewed'),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('forgot-password-dismiss')));
    await tester.pumpAndSettle();
  });

  testWidgets('login shows the NTCCSL logo', (WidgetTester tester) async {
    await tester.pumpWidget(
      NtccslAccountApp(apiService: _FakeApiService()),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ntccsl-login-logo')), findsOneWidget);
    final accountTypeButton = tester.widget<SegmentedButton<String>>(
      find.byKey(const Key('login-account-type')),
    );
    final loginCard = tester.widget<Card>(
      find.byKey(const Key('login-account-card')),
    );
    final colors = Theme.of(tester.element(find.byType(LoginPage))).colorScheme;
    expect(
      loginCard.color,
      Color.alphaBlend(
        portalRoleColor('Admin').withValues(alpha: .08),
        colors.surface,
      ),
    );
    expect(
      accountTypeButton.style!.foregroundColor!.resolve({WidgetState.selected}),
      portalRoleColor('Admin'),
    );
    final signUpButton = tester.widget<TextButton>(
      find.byKey(const Key('open-register')),
    );
    expect(
      signUpButton.style!.backgroundColor!.resolve({}),
      portalRoleColor('Admin').withValues(alpha: .08),
    );
    expect(
      signUpButton.style!.side!.resolve({})!.color,
      portalRoleColor('Admin').withValues(alpha: .35),
    );
    await tester.tap(find.text('Member Login'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Card>(find.byKey(const Key('login-account-card'))).color,
      Color.alphaBlend(
        portalRoleColor('Member').withValues(alpha: .08),
        colors.surface,
      ),
    );
    final memberAccountTypeButton = tester.widget<SegmentedButton<String>>(
      find.byKey(const Key('login-account-type')),
    );
    expect(
      memberAccountTypeButton.style!.foregroundColor!
          .resolve({WidgetState.selected}),
      portalRoleColor('Member'),
    );
    expect(
      memberAccountTypeButton.style!.backgroundColor!
          .resolve({WidgetState.selected}),
      Color.alphaBlend(
        portalRoleColor('Member').withValues(alpha: .12),
        colors.surface,
      ),
    );
  });

  testWidgets('member login opens the individual member account',
      (WidgetTester tester) async {
    final client = _RecordingHttpClient([
      {
        'status': 'success',
        'token': 'member-session-token',
        'user': {
          'id': 'member-1',
          'accountNo': 'DRD000000001',
          'name': 'Jordan Member',
          'email': 'jordan@example.com',
          'role': 'Member',
        },
        'permissions': {
          'shared_data_read': false,
          'own_collection_read': true,
          'collection_manage': false,
          'deposit_view': false,
          'deposit_manage': false,
          'ledger_manage': false,
          'user_manage': false,
        },
        'reportAccess': {
          'daily': true,
          'weekly': false,
          'monthly': false,
        },
      },
      [
        {
          'memberName': 'Jordan Member',
          'date': '2026-01-01',
          'depAmt': 25,
          'totalCount': 1,
          'totalReceived': 25,
          'periods': [true],
          'rowIndex': 2,
        },
      ],
      [
        {
          'memberName': 'Jordan Member',
          'date': '2026-01-01',
          'depAmt': 25,
          'totalCount': 1,
          'totalReceived': 25,
          'periods': [true],
          'rowIndex': 2,
        },
      ],
      <dynamic>[],
      [
        {
          'memberName': 'Jordan Member',
          'date': '2026-01-01',
          'depAmt': 25,
          'totalCount': 1,
          'totalReceived': 25,
          'periods': [true],
          'rowIndex': 2,
        },
      ],
    ]);
    await tester.pumpWidget(
      NtccslAccountApp(apiService: ApiService(client: client)),
    );

    await tester.tap(find.text('Member Login'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('login-email')),
      'jordan@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'member-password',
    );
    await tester.ensureVisible(find.byKey(const Key('login-submit')));
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(client.payloads.first['loginType'], 'member');
    expect(client.payloads.first['email'], 'jordan@example.com');
    expect(client.payloads.first['password'], 'member-password');
    expect(
      client.payloads.map((payload) => payload['action']),
      isNot(contains('getWeekly')),
    );
    expect(
      client.payloads.map((payload) => payload['action']),
      isNot(contains('getMonthly')),
    );
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byType(NavigationDestination),
      ),
      findsNWidgets(2),
    );
    expect(find.byKey(const Key('navigation-menu-weekly')), findsNothing);
    expect(find.byKey(const Key('navigation-menu-monthly')), findsNothing);
    await _openDrawerPage(tester, 'navigation-menu-daily');
    expect(find.text('Jordan Member'), findsOneWidget);
    expect(find.byKey(const Key('add-collection-entry')), findsNothing);
  });

  test('member collection matching normalizes case and whitespace', () {
    const session = AuthSession(
      token: 'member-token',
      userId: 'member-1',
      name: 'Jordan Member',
      email: 'jordan@example.com',
      role: 'Member',
    );

    expect(session.matchesMemberName('  jordan   member  '), isTrue);
    expect(session.matchesMemberName('Other Member'), isFalse);
    expect(session.matchesMemberName(null), isFalse);
  });

  testWidgets('startup splash centers fitted logo and shows society name',
      (WidgetTester tester) async {
    _mockPackageInfo();
    await tester.pumpWidget(
      NtccslAccountApp(
        apiService: _FakeApiService(),
        showSplashScreen: true,
      ),
    );

    expect(find.byType(SplashPage), findsOneWidget);
    expect(find.text(SplashPage.appName), findsOneWidget);
    await tester.pump();
    await tester.pump();
    expect(find.text('Version - 1.2.2'), findsOneWidget);
    expect(find.byKey(const Key('splash-logo')), findsOneWidget);
    expect(find.text('NoFino Thrift & Credit'), findsOneWidget);
    expect(find.text('Co-Operative Society Ltd.'), findsOneWidget);
    expect(find.text('Seeding Growth, Nurturing Futures'), findsOneWidget);
    final logo = tester.widget<Image>(find.byKey(const Key('splash-logo')));
    expect(logo.fit, BoxFit.contain);
    expect(
        tester.getCenter(find.byKey(const Key('splash-logo'))).dx,
        moreOrLessEquals(
            tester.view.physicalSize.width / tester.view.devicePixelRatio / 2));
    expect(find.byKey(const Key('splash-loading-indicator')), findsOneWidget);
    expect(find.byKey(const Key('splash-orbiting-loader')), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Getting things ready'), findsOneWidget);
    expect(find.text('SECURE FINANCE PORTAL'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 4999));
    expect(find.byType(SplashPage), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(find.byType(SplashPage), findsNothing);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('splash surfaces use dark theme colors',
      (WidgetTester tester) async {
    _mockPackageInfo();
    final darkTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF3458D4),
        brightness: Brightness.dark,
      ),
      brightness: Brightness.dark,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        darkTheme: darkTheme,
        themeMode: ThemeMode.dark,
        home: const SplashPage(),
      ),
    );

    final colors = darkTheme.colorScheme;
    final splashContext = tester.element(find.byType(SplashPage));
    expect(Theme.of(splashContext).brightness, Brightness.dark);
    expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor, isNull);
    expect(
      tester
          .widget<Container>(find.byKey(const Key('splash-logo-backdrop')))
          .decoration,
      isA<BoxDecoration>().having(
        (decoration) => decoration.color,
        'color',
        colors.surfaceContainerHighest,
      ),
    );
    expect(
      (tester
              .widget<Container>(
                find.byKey(const Key('splash-loading-indicator')),
              )
              .decoration as BoxDecoration)
          .color,
      colors.surfaceContainerHighest,
    );
  });

  testWidgets('signed-in app bar uses the new logo icon',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: _FakeApiService(),
          session: const AuthSession(
            token: 'test-token',
            userId: 'admin-1',
            name: 'Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ntccsl-app-icon')), findsOneWidget);
  });

  testWidgets('registration reports backend error without false success',
      (WidgetTester tester) async {
    final apiService = ApiService(
      client: _RecordingHttpClient(['unknown post action']),
    );
    await tester.pumpWidget(
      MaterialApp(home: RegisterPage(apiService: apiService)),
    );

    await tester.enterText(find.byKey(const Key('register-name')), 'Sam');
    await tester.enterText(
      find.byKey(const Key('register-email')),
      'sam@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('register-password')),
      'secure-pass',
    );
    await tester.enterText(
      find.byKey(const Key('register-confirm-password')),
      'secure-pass',
    );
    await tester.ensureVisible(find.byKey(const Key('register-submit')));
    await tester.tap(find.byKey(const Key('register-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('register-error')), findsOneWidget);
    expect(find.text('Registration successful.'), findsNothing);
  });

  testWidgets('users can sign in and see account navigation',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(NtccslAccountApp(apiService: apiService));

    expect(find.text('Continue'), findsOneWidget);
    await _signIn(tester);

    expect(find.text('Signed in successfully.'), findsOneWidget);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.byKey(const Key('open-navigation-menu')), findsOneWidget);
    expect(find.text('Daily'), findsOneWidget);
    expect(find.text('Weekly'), findsOneWidget);
    expect(find.text('Monthly'), findsOneWidget);
    expect(find.text('Users'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byType(NavigationDestination),
      ),
      findsNWidgets(5),
    );
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Accounts'),
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ntccsl-app-icon')), findsOneWidget);
    expect(find.byKey(const Key('navigation-menu-accounts')), findsOneWidget);
    await tester.tap(find.byKey(const Key('close-navigation-menu')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-profile')));
    await tester.pumpAndSettle();
    expect(find.text('My profile'), findsOneWidget);
    expect(find.byKey(const Key('profile-name')).evaluate().single.widget,
        isA<Text>());
    expect(find.byKey(const Key('profile-role')).evaluate().single.widget,
        isA<Text>());
    expect(find.text('Admin'), findsNWidgets(2));
    expect(find.text('admin@example.com'), findsOneWidget);
    expect(find.byKey(const Key('profile-account-number')), findsOneWidget);
    expect(
      (tester
          .widget<Text>(
            find.byKey(const Key('profile-account-number')),
          )
          .data!),
      matches(RegExp(r'^ADM\d{9}$')),
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Weekly'));
    await tester.pumpAndSettle();
    expect(find.text('Weekly Collection'), findsOneWidget);
  });

  testWidgets('top navigation menu opens, closes, and changes pages',
      (WidgetTester tester) async {
    var didLogout = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: _FakeApiService(),
          session: const AuthSession(
            token: 'test-token',
            userId: 'admin-1',
            name: 'Test Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onLogout: () => didLogout = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();
    final depositMenu = find.byKey(const Key('navigation-menu-deposit'));
    expect(depositMenu, findsOneWidget);
    expect(
      tester.getTopLeft(depositMenu).dy,
      greaterThan(
        tester.getTopLeft(find.byKey(const Key('navigation-menu-accounts'))).dy,
      ),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('navigation-menu-users'))).dy,
      greaterThan(tester.getTopLeft(depositMenu).dy),
    );
    await _expandDrawerTile(
      tester,
      depositMenu,
      find.byKey(const Key('navigation-menu-product-fd')),
    );
    expect(find.text('FD/RD/DRD'), findsNothing);

    final fdProduct = find.byKey(const Key('navigation-menu-product-fd'));
    final fdMonthly = find.byKey(const Key('navigation-menu-fd-monthly'));
    final fdProductTile = tester.widget<ExpansionTile>(fdProduct);
    final fdProductAvatar = fdProductTile.leading! as CircleAvatar;
    final fdProductIcon = fdProductAvatar.child! as Icon;
    expect(fdProductIcon.icon, Icons.savings_outlined);
    expect(fdProductIcon.color, const Color(0xFF3458D4));
    expect(
      fdProductAvatar.backgroundColor,
      const Color(0xFF3458D4).withValues(alpha: .12),
    );
    await _expandDrawerTile(tester, fdProduct, fdMonthly);
    expect(fdMonthly, findsOneWidget);
    final fdCadenceTile = tester.widget<ListTile>(fdMonthly);
    final fdCadenceAvatar = fdCadenceTile.leading! as CircleAvatar;
    final fdCadenceIcon = fdCadenceAvatar.child! as Icon;
    expect(fdCadenceIcon.icon, Icons.calendar_month_rounded);
    expect(fdCadenceIcon.color, const Color(0xFF3458D4));
    final rdProduct = find.byKey(const Key('navigation-menu-product-rd'));
    await _expandDrawerTile(tester, depositMenu, rdProduct);
    final rdProductTile = tester.widget<ExpansionTile>(rdProduct);
    final rdProductAvatar = rdProductTile.leading! as CircleAvatar;
    final rdProductIcon = rdProductAvatar.child! as Icon;
    expect(rdProductIcon.icon, Icons.event_repeat_rounded);
    expect(rdProductIcon.color, const Color(0xFF8E24AA));
    expect(
      rdProductAvatar.backgroundColor,
      const Color(0xFF8E24AA).withValues(alpha: .12),
    );
    final rdWeekly = find.byKey(const Key('navigation-menu-rd-weekly'));
    final rdMonthly = find.byKey(const Key('navigation-menu-rd-monthly'));
    await _expandDrawerTile(tester, rdProduct, rdWeekly);
    expect(rdWeekly, findsOneWidget);
    expect(rdMonthly, findsOneWidget);
    for (final cadence in ['weekly', 'monthly']) {
      final tile = tester.widget<ListTile>(
        find.byKey(Key('navigation-menu-rd-$cadence')),
      );
      final avatar = tile.leading! as CircleAvatar;
      final icon = avatar.child! as Icon;
      expect(
        icon.icon,
        cadence == 'weekly'
            ? Icons.calendar_view_week_rounded
            : Icons.calendar_month_rounded,
      );
      expect(icon.color, const Color(0xFF8E24AA));
    }
    final drdProduct = find.byKey(const Key('navigation-menu-product-drd'));
    await _expandDrawerTile(
      tester,
      depositMenu,
      drdProduct,
    );
    final drdProductTile = tester.widget<ExpansionTile>(drdProduct);
    final drdProductAvatar = drdProductTile.leading! as CircleAvatar;
    final drdProductIcon = drdProductAvatar.child! as Icon;
    expect(drdProductIcon.icon, Icons.calendar_month_rounded);
    expect(drdProductIcon.color, const Color(0xFF078A6A));
    expect(
      drdProductAvatar.backgroundColor,
      const Color(0xFF078A6A).withValues(alpha: .12),
    );
    await _ensureDrawerItemVisible(tester, drdProduct);
    await _expandDrawerTile(
      tester,
      drdProduct,
      find.byKey(const Key('navigation-menu-drd-daily')),
    );
    for (final cadence in ['daily', 'weekly', 'monthly']) {
      expect(
        find.byKey(Key('navigation-menu-drd-$cadence')),
        findsOneWidget,
      );
      final tile = tester.widget<ListTile>(
        find.byKey(Key('navigation-menu-drd-$cadence')),
      );
      final avatar = tile.leading! as CircleAvatar;
      final icon = avatar.child! as Icon;
      expect(
        icon.icon,
        switch (cadence) {
          'daily' => Icons.today_rounded,
          'weekly' => Icons.calendar_view_week_rounded,
          _ => Icons.calendar_month_rounded,
        },
      );
      expect(icon.color, const Color(0xFF078A6A));
    }
    expect(find.text('Test Admin'), findsOneWidget);

    await tester.tap(find.byKey(const Key('close-navigation-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('navigation-menu-drd-daily')), findsNothing);

    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();
    final collectionsMenu =
        find.byKey(const Key('navigation-menu-existing-collections'));
    expect(
      find.ancestor(
        of: collectionsMenu,
        matching: find.byKey(const Key('navigation-menu-deposit')),
      ),
      findsNothing,
    );
    await _expandDrawerTile(
      tester,
      collectionsMenu,
      find.byKey(const Key('navigation-menu-daily')),
    );
    await _ensureDrawerItemVisible(
      tester,
      find.byKey(const Key('navigation-menu-daily')),
    );
    await tester.tap(find.byKey(const Key('navigation-menu-daily')));
    await tester.pumpAndSettle();

    expect(find.text('Daily Collection'), findsOneWidget);
    expect(find.byKey(const Key('navigation-menu-daily')), findsNothing);

    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('navigation-menu-logout')));
    await tester.pumpAndSettle();
    expect(didLogout, isTrue);
    expect(find.text('Signed out successfully.'), findsOneWidget);
  });

  test('deposit maturity calculations follow the confirmed terms', () {
    final startDate = DateTime(2026, 1, 31);
    final maturityDate = depositMaturityDate(startDate, 12);
    expect(maturityDate, DateTime(2027, 1, 31));
    expect(
      depositMaturityDate(startDate, 1),
      DateTime(2026, 2, 28),
    );
    expect(
      depositMaturityAmount(
        product: 'FD',
        cadence: 'monthly',
        amount: 10000,
        annualRate: 12,
        tenureMonths: 12,
        periodCount: 0,
      ),
      11268.25,
    );
    expect(
      depositMaturityAmount(
        product: 'RD',
        cadence: 'monthly',
        amount: 1000,
        annualRate: 12,
        tenureMonths: 12,
        periodCount: 12,
      ),
      12682.50,
    );
    expect(
      depositPeriodDates(
        startDate: DateTime(2026, 1, 31),
        maturityDate: DateTime(2026, 4, 30),
        cadence: 'monthly',
      ),
      [DateTime(2026, 2, 28), DateTime(2026, 3, 31), DateTime(2026, 4, 30)],
    );
  });

  testWidgets('deposit menu respects member cadence access',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: _FakeApiService(),
          session: const AuthSession(
            token: 'member-token',
            userId: 'member-1',
            name: 'Jordan Member',
            email: 'jordan@example.com',
            role: 'Member',
            permissions: {
              'own_collection_read': true,
              'deposit_view': true,
            },
            reportAccess: {
              'daily': true,
              'weekly': false,
              'monthly': false,
            },
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();
    final deposit = find.byKey(const Key('navigation-menu-deposit'));
    await tester.tap(deposit);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('navigation-menu-product-fd')), findsNothing);
    expect(find.byKey(const Key('navigation-menu-product-rd')), findsNothing);
    final drd = find.byKey(const Key('navigation-menu-product-drd'));
    await _expandDrawerTile(tester, deposit, drd);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('navigation-menu-drd-daily')), findsOneWidget);
    expect(find.byKey(const Key('navigation-menu-drd-weekly')), findsNothing);
    expect(find.byKey(const Key('navigation-menu-drd-monthly')), findsNothing);
  });

  testWidgets('deposit pages use dedicated view and manage permissions',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: _FakeApiService(),
          session: const AuthSession(
            token: 'member-token',
            userId: 'member-1',
            name: 'Jordan Member',
            email: 'jordan@example.com',
            role: 'Member',
            permissions: {'own_collection_read': true},
            reportAccess: {'daily': true, 'weekly': true, 'monthly': true},
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('navigation-menu-deposit')), findsNothing);
    final collections =
        find.byKey(const Key('navigation-menu-existing-collections'));
    await _expandDrawerTile(
      tester,
      collections,
      find.byKey(const Key('navigation-menu-daily')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('navigation-menu-daily')), findsOneWidget);
    expect(find.byKey(const Key('navigation-menu-weekly')), findsOneWidget);
    expect(find.byKey(const Key('navigation-menu-monthly')), findsOneWidget);
    await tester.tap(find.byKey(const Key('close-navigation-menu')));
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: _FakeApiService(),
          session: const AuthSession(
            token: 'collector-token',
            userId: 'collector-1',
            name: 'Collector',
            email: 'collector@example.com',
            role: 'Collector',
            permissions: {'deposit_view': true},
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openDrawerPage(tester, 'navigation-menu-drd-daily');
    expect(find.byKey(const Key('add-deposit-account')), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: _FakeApiService(),
          session: const AuthSession(
            token: 'collector-token',
            userId: 'collector-1',
            name: 'Collector',
            email: 'collector@example.com',
            role: 'Collector',
            permissions: {'deposit_manage': true},
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openDrawerPage(tester, 'navigation-menu-drd-daily');
    expect(find.byKey(const Key('add-deposit-account')), findsOneWidget);
  });

  testWidgets('deposit page supports retry and refresh from empty state',
      (WidgetTester tester) async {
    final apiService = _FakeApiService()
      ..depositFetchError = StateError('offline');
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: const AuthSession(
            token: 'test-token',
            userId: 'admin-1',
            name: 'Test Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openDrawerPage(tester, 'navigation-menu-fd-monthly');

    expect(find.text('Could not load this page'), findsOneWidget);
    expect(find.text('Bad state: offline'), findsOneWidget);

    apiService.depositFetchError = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('No Fixed Deposit accounts yet'), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);

    final initialFetchCount = apiService.depositFetchCount;
    final refresh = tester
        .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
        .show();
    await tester.pump();
    await tester.pumpAndSettle();
    await refresh;
    expect(apiService.depositFetchCount, initialFetchCount + 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('RD monthly accounts can be created and payments tracked',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: const AuthSession(
            token: 'test-token',
            userId: 'admin-1',
            name: 'Test Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openDrawerPage(tester, 'navigation-menu-rd-monthly');
    expect(find.text('Recurring Deposit — Monthly'), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-deposit-account')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('deposit-member-name')),
      'Jordan Member',
    );
    await tester.enterText(find.byKey(const Key('deposit-amount')), '1000');
    await tester.enterText(
      find.byKey(const Key('deposit-annual-rate')),
      '12',
    );
    await tester.enterText(
      find.byKey(const Key('deposit-tenure-months')),
      '12',
    );
    expect(find.byKey(const Key('deposit-maturity-estimate')), findsOneWidget);
    await tester.tap(find.byKey(const Key('save-deposit-account')));
    await tester.pumpAndSettle();

    expect(apiService.depositAccounts, hasLength(1));
    expect(apiService.depositAccounts.single['product'], 'RD');
    expect(apiService.depositAccounts.single['cadence'], 'monthly');
    expect(apiService.depositAccounts.single['maturityAmount'], 12682.5);
    expect(apiService.depositAccounts.single['payments'], hasLength(12));

    final editButton = find.byKey(const Key('edit-deposit-deposit-1'));
    final deleteButton = find.byKey(const Key('delete-deposit-deposit-1'));
    expect(
      tester.widget<IconButton>(editButton).style!.foregroundColor!.resolve({}),
      portalEditColor,
    );
    expect(
      tester
          .widget<IconButton>(deleteButton)
          .style!
          .foregroundColor!
          .resolve({}),
      portalDeleteColor,
    );

    final scheduleButton = find.byKey(const Key('deposit-schedule-deposit-1'));
    await tester.ensureVisible(scheduleButton);
    await tester.pumpAndSettle();
    await tester.tap(scheduleButton);
    await tester.pumpAndSettle();
    final firstPayment = find.byKey(const Key('deposit-payment-deposit-1-0'));
    await tester.tap(firstPayment);
    await tester.pumpAndSettle();
    expect(apiService.depositAccounts.single['payments'][0], isTrue);
    expect(
      apiService.depositActions.last['action'],
      'toggleDepositPayment',
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(editButton);
    await tester.tap(editButton);
    await tester.pumpAndSettle();
    expect(find.text('Edit Recurring Deposit account'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('deposit-member-name')))
          .controller!
          .text,
      'Jordan Member',
    );
    await tester.enterText(find.byKey(const Key('deposit-amount')), '1500');
    await tester.ensureVisible(find.byKey(const Key('save-deposit-account')));
    final editCompleter = Completer<bool>();
    apiService.depositMutationCompleter = editCompleter;
    await tester.tap(find.byKey(const Key('save-deposit-account')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Updating deposit account'), findsOneWidget);
    expect(find.byKey(const Key('portal-loading-state')), findsOneWidget);
    editCompleter.complete(true);
    await tester.pumpAndSettle();
    expect(apiService.depositActions.last['action'], 'editDepositAccount');
    expect(apiService.depositActions.last['id'], 'deposit-1');
    expect(apiService.depositAccounts.single['amount'], 1500);
    expect(apiService.depositAccounts.single['payments'][0], isTrue);

    await tester.tap(find.byKey(const Key('delete-deposit-deposit-1')));
    await tester.pumpAndSettle();
    final deleteConfirmation = tester
        .widget<FilledButton>(find.byKey(const Key('confirm-delete-deposit')));
    expect(
      deleteConfirmation.style!.backgroundColor!.resolve({}),
      portalDeleteColor,
    );
    final deleteCompleter = Completer<bool>();
    apiService.depositMutationCompleter = deleteCompleter;
    await tester.tap(find.byKey(const Key('confirm-delete-deposit')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Deleting deposit account'), findsOneWidget);
    expect(find.byKey(const Key('portal-loading-state')), findsOneWidget);
    deleteCompleter.complete(true);
    await tester.pumpAndSettle();
    expect(apiService.depositAccounts, isEmpty);
  });

  testWidgets('FD monthly accounts use a one-time principal and no schedule',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: const AuthSession(
            token: 'test-token',
            userId: 'admin-1',
            name: 'Test Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openDrawerPage(tester, 'navigation-menu-fd-monthly');
    expect(find.text('Fixed Deposit — Monthly'), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-deposit-account')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('deposit-member-name')),
      'Jordan Member',
    );
    await tester.enterText(find.byKey(const Key('deposit-amount')), '10000');
    await tester.enterText(
      find.byKey(const Key('deposit-annual-rate')),
      '12',
    );
    await tester.enterText(
      find.byKey(const Key('deposit-tenure-months')),
      '12',
    );
    await tester.tap(find.byKey(const Key('save-deposit-account')));
    await tester.pumpAndSettle();

    expect(apiService.depositAccounts.single['product'], 'FD');
    expect(apiService.depositAccounts.single['amount'], 10000);
    expect(apiService.depositAccounts.single['maturityAmount'], 11268.25);
    expect(apiService.depositAccounts.single['payments'], isEmpty);
  });

  testWidgets('appearance menu switches between system, light, and dark',
      (WidgetTester tester) async {
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );
    await tester.pumpWidget(
      NtccslAccountApp(apiService: _FakeApiService()),
    );
    await _signIn(tester);

    for (final mode in ThemeMode.values) {
      await tester.tap(find.byKey(const Key('open-navigation-menu')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('open-theme-mode')));
      await tester.tap(find.byKey(const Key('open-theme-mode')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('theme-mode-dialog')), findsOneWidget);

      await tester.tap(find.byKey(Key('theme-mode-${mode.name}')));
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, mode);
      expect(app.theme!.brightness, Brightness.light);
      expect(app.darkTheme!.brightness, Brightness.dark);
      expect(
        app.theme!.appBarTheme.foregroundColor,
        Colors.white,
      );
      expect(
        app.darkTheme!.appBarTheme.foregroundColor,
        Colors.white,
      );
      expect(
        app.theme!.appBarTheme.backgroundColor,
        app.theme!.colorScheme.primary,
      );
      expect(
        app.darkTheme!.appBarTheme.backgroundColor,
        const Color(0xFF253B8C),
      );
      for (final theme in [app.theme!, app.darkTheme!]) {
        expect(
          _contrastRatio(
            theme.appBarTheme.foregroundColor!,
            theme.appBarTheme.backgroundColor!,
          ),
          greaterThan(4.5),
        );
      }
      expect(
        app.theme!.primaryIconTheme.color,
        app.theme!.colorScheme.onPrimary,
      );
      expect(
        app.darkTheme!.primaryIconTheme.color,
        app.darkTheme!.colorScheme.onPrimary,
      );
      expect(
        app.theme!.iconTheme.color,
        app.theme!.colorScheme.tertiary,
      );
      expect(
        app.darkTheme!.iconTheme.color,
        app.darkTheme!.colorScheme.tertiary,
      );
      expect(
        app.theme!.iconButtonTheme.style!.foregroundColor!.resolve(const {}),
        app.theme!.colorScheme.secondary,
      );
      expect(
        app.darkTheme!.iconButtonTheme.style!.foregroundColor!
            .resolve(const {}),
        app.darkTheme!.colorScheme.secondary,
      );
      expect(
        app.theme!.colorScheme.primary,
        isNot(app.darkTheme!.colorScheme.primary),
      );
      expect(
        app.theme!.navigationBarTheme.iconTheme!
            .resolve({WidgetState.selected})!.color,
        app.theme!.colorScheme.primary,
      );
      expect(
        app.darkTheme!.navigationBarTheme.iconTheme!
            .resolve({WidgetState.selected})!.color,
        app.darkTheme!.colorScheme.primary,
      );
      final effectiveTheme = Theme.of(
        tester.element(find.byKey(const Key('open-navigation-menu'))),
      );
      final expectedBrightness =
          mode == ThemeMode.dark ? Brightness.dark : Brightness.light;
      expect(effectiveTheme.brightness, expectedBrightness);
      expect(app.darkTheme!.scaffoldBackgroundColor, const Color(0xFF11131A));
      expect(
        app.darkTheme!.cardTheme.color,
        app.darkTheme!.colorScheme.surface,
      );
      final headerColors = portalHeaderGradient(
        tester.element(find.byKey(const Key('open-navigation-menu'))),
      );
      expect(headerColors, hasLength(2));
      for (final color in headerColors) {
        expect(_contrastRatio(Colors.white, color), greaterThan(4.5));
      }
      if (mode == ThemeMode.system) {
        tester.binding.platformDispatcher.platformBrightnessTestValue =
            Brightness.dark;
        await tester.pumpAndSettle();
        expect(
          Theme.of(
            tester.element(find.byKey(const Key('open-navigation-menu'))),
          ).brightness,
          Brightness.dark,
        );
        tester.binding.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        await tester.pumpAndSettle();
      }
      if (find
          .byKey(const Key('close-navigation-menu'))
          .evaluate()
          .isNotEmpty) {
        await tester.tap(find.byKey(const Key('close-navigation-menu')));
        await tester.pumpAndSettle();
      }
    }
  });

  testWidgets('dashboard summarizes account and collection data',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    apiService.depositAccounts.addAll([
      {
        'id': 'dashboard-fd-1',
        'product': 'FD',
        'cadence': 'monthly',
        'memberName': 'Jordan Member',
        'maturityAmount': 11268.25,
        'payments': <bool>[],
      },
      {
        'id': 'dashboard-rd-1',
        'product': 'RD',
        'cadence': 'monthly',
        'memberName': 'Jordan Member',
        'maturityAmount': 12682.50,
        'payments': <bool>[true, false],
      },
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: const AuthSession(
            token: 'test-token',
            userId: 'admin-1',
            name: 'Test Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ledger balance'), findsOneWidget);
    expect(find.text('₹100'), findsNWidgets(2));
    expect(find.text('Collections received'), findsOneWidget);
    expect(find.text('Members'), findsOneWidget);
    expect(find.text('User accounts'), findsOneWidget);
    final fdSummary = find.byKey(const Key('dashboard-deposit-fd-monthly'));
    final dashboardList = find.byType(ListView).first;
    await _scrollUntilBuilt(tester, fdSummary, dashboardList);
    await tester.ensureVisible(fdSummary);
    expect(
        find.byKey(const Key('dashboard-deposit-fd-monthly')), findsOneWidget);
    expect(
      find.textContaining('Total estimated maturity ₹11,268'),
      findsOneWidget,
    );
    await tester.drag(dashboardList, const Offset(0, 500));
    await tester.pumpAndSettle();
    final dailySummary = find.byKey(const Key('dashboard-collection-daily'));
    await _scrollUntilBuilt(
      tester,
      dailySummary,
      dashboardList,
    );
    await tester.ensureVisible(dailySummary);
    await tester.pumpAndSettle();
    expect(find.text('Daily collection'), findsOneWidget);
    final ledgerEntry = find.text('Office');
    await _scrollUntilBuilt(tester, ledgerEntry, dashboardList);
    await tester.ensureVisible(ledgerEntry);
    await tester.pumpAndSettle();
    expect(find.text('Office'), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();
    final existingCollections =
        find.byKey(const Key('navigation-menu-existing-collections'));
    final dailyMenuItem = find.byKey(const Key('navigation-menu-daily'));
    await _expandDrawerTile(
      tester,
      existingCollections,
      dailyMenuItem,
    );
    await _ensureDrawerItemVisible(tester, dailyMenuItem);
    await tester.tap(dailyMenuItem);
    await tester.pumpAndSettle();
    expect(find.text('Daily Collection'), findsOneWidget);
    expect(
        apiService.fetchActions,
        containsAll([
          'getAmount',
          'getDaily',
          'getWeekly',
          'getMonthly',
          'getUsers',
          'getDepositAccounts:FD:monthly',
          'getDepositAccounts:RD:weekly',
          'getDepositAccounts:RD:monthly',
          'getDepositAccounts:DRD:daily',
          'getDepositAccounts:DRD:weekly',
          'getDepositAccounts:DRD:monthly',
        ]));
  });

  testWidgets('dashboard shows available data when a source fails',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: _DashboardFailingApiService(),
          session: const AuthSession(
            token: 'test-token',
            userId: 'admin-1',
            name: 'Test Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dashboard-partial-error')), findsOneWidget);
    expect(
      find.textContaining('Weekly collection: Weekly sheet is unavailable.'),
      findsOneWidget,
    );
  });

  testWidgets('dashboard and profile fit narrow phone screens',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const session = AuthSession(
      token: 'test-token',
      userId: 'admin-1',
      name: 'A Very Long Account Holder Name',
      email: 'a.very.long.email.address@example.com',
      role: 'Admin',
      accountNumber: 'ADM123456789',
    );
    final apiService = _FakeApiService();

    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: session,
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final dashboardMetrics = find.byType(PortalMetricCard);
    expect(dashboardMetrics, findsNWidgets(6));
    final topRowY = tester.getTopLeft(dashboardMetrics.first).dy;
    for (var index = 1; index < 3; index++) {
      expect(tester.getTopLeft(dashboardMetrics.at(index)).dy, topRowY);
    }
    for (var index = 3; index < 6; index++) {
      expect(tester.getTopLeft(dashboardMetrics.at(index)).dy,
          greaterThan(topRowY));
    }
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        home: ProfilePage(apiService: apiService, session: session),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-name')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard metrics use two rows on wide screens',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: _FakeApiService(),
          session: const AuthSession(
            token: 'test-token',
            userId: 'admin-1',
            name: 'Test Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final metrics = find.byType(PortalMetricCard);
    expect(metrics, findsNWidgets(6));
    final firstRowY = tester.getTopLeft(metrics.at(0)).dy;
    for (var index = 1; index < 3; index++) {
      expect(tester.getTopLeft(metrics.at(index)).dy, firstRowY);
    }
    for (var index = 3; index < 6; index++) {
      expect(tester.getTopLeft(metrics.at(index)).dy, greaterThan(firstRowY));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('registered accounts chart reflects user roles',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    apiService.users.addAll([
      {
        'id': 'user-3',
        'accountNo': 'EMP000000001',
        'name': 'Alex Collector',
        'email': 'alex@example.com',
        'role': 'Collector',
        'dailyAccess': false,
        'weeklyAccess': true,
        'monthlyAccess': false,
      },
      {
        'id': 'user-4',
        'accountNo': 'ADM123456789',
        'name': 'Riley Admin',
        'email': 'riley@example.com',
        'role': 'Admin',
      },
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: const AuthSession(
            token: 'test-token',
            userId: 'admin-1',
            name: 'Test Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final roleChart = find.byKey(const Key('registered-accounts-role-chart'));
    final dashboardList = find.descendant(
      of: find.byType(RefreshIndicator).first,
      matching: find.byType(ListView),
    );
    for (var attempt = 0;
        roleChart.evaluate().isEmpty && attempt < 8;
        attempt++) {
      await tester.drag(dashboardList.first, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('registered-accounts-role-chart')),
        findsOneWidget);
    expect(find.byIcon(Icons.pie_chart_rounded), findsOneWidget);
    expect(find.byKey(const Key('registered-accounts-pie')), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(
        find.byKey(const Key('registered-role-count-admin')), findsOneWidget);
    expect(find.byKey(const Key('registered-role-count-collector')),
        findsOneWidget);
    expect(
        find.byKey(const Key('registered-role-count-member')), findsOneWidget);
    expect(
        tester
            .widget<Text>(
              find.byKey(const Key('registered-role-count-admin')),
            )
            .data,
        '1');
    expect(
        tester
            .widget<Text>(
              find.byKey(const Key('registered-role-count-collector')),
            )
            .data,
        '1');
    expect(
        tester
            .widget<Text>(
              find.byKey(const Key('registered-role-count-member')),
            )
            .data,
        '2');
    expect(find.byKey(const Key('registered-accounts-list')), findsOneWidget);
    expect(find.byKey(const Key('registered-accounts-table')), findsOneWidget);
    expect(find.text('Account No.'), findsOneWidget);
    expect(find.text('EMP000000001'), findsOneWidget);
    expect(find.text('ADM123456789'), findsOneWidget);
    expect(
      find.byKey(const Key('registered-account-user-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('registered-account-user-2')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const Key('registered-account-permissions-user-3'),
            ),
          )
          .data,
      contains('Manage collections'),
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('registered-account-reports-user-3')),
          )
          .data,
      'Reports: Daily Off · Weekly On · Monthly Off',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('registered-role-share-admin')),
          )
          .data,
      '25%',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('registered-role-share-collector')),
          )
          .data,
      '25%',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('registered-role-share-member')),
          )
          .data,
      '50%',
    );
    expect(find.byKey(const Key('dashboard-open-users')), findsOneWidget);
    expect(tester.takeException(), isNull);

    for (var attempt = 0;
        find
                .byKey(const Key('dashboard-greeting'))
                .hitTestable()
                .evaluate()
                .isEmpty &&
            attempt < 8;
        attempt++) {
      await tester.drag(dashboardList.first, const Offset(0, 400));
      await tester.pumpAndSettle();
    }
    apiService.users.add({
      'id': 'user-5',
      'name': 'Casey New Member',
      'email': 'casey@example.com',
      'role': 'Member',
    });
    final refresh = tester
        .state<RefreshIndicatorState>(find.byType(RefreshIndicator).first)
        .show();
    await tester.pump();
    await tester.pumpAndSettle();
    await refresh;
    for (var attempt = 0;
        roleChart.evaluate().isEmpty && attempt < 8;
        attempt++) {
      await tester.drag(dashboardList.first, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('registered-accounts-pie-total')),
          )
          .data,
      '5',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('registered-role-share-member')),
          )
          .data,
      '60%',
    );
    expect(
      find.byKey(const Key('registered-account-user-5')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('role permission fetch failures are visible on account cards',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: _DashboardFailingRolePermissionsApiService(),
          session: const AuthSession(
            token: 'test-token',
            userId: 'admin-1',
            name: 'Test Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dashboardList = find.descendant(
      of: find.byType(RefreshIndicator).first,
      matching: find.byType(ListView),
    );
    final permissionSummary = find.byKey(
      const Key('registered-account-permissions-user-1'),
    );
    for (var attempt = 0;
        permissionSummary.evaluate().isEmpty && attempt < 8;
        attempt++) {
      await tester.drag(dashboardList.first, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    expect(
      tester.widget<Text>(permissionSummary).data,
      contains('Unavailable: Role permissions are offline.'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('portal theme gives default and form icons accent colors',
      (WidgetTester tester) async {
    await tester.pumpWidget(NtccslAccountApp(apiService: _FakeApiService()));
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));

    expect(app.theme!.iconTheme.color, app.theme!.colorScheme.tertiary);
    expect(
      app.theme!.inputDecorationTheme.prefixIconColor,
      app.theme!.colorScheme.primary,
    );
    expect(
      app.theme!.inputDecorationTheme.suffixIconColor,
      app.theme!.colorScheme.tertiary,
    );
  });

  testWidgets('ledger search filters records without hiding account totals',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(NtccslAccountApp(apiService: apiService));
    await _signIn(tester);
    await _openDrawerPage(tester, 'navigation-menu-accounts');

    expect(find.text('Total deposits'), findsOneWidget);
    expect(find.text('Office'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('ledger-search')),
      'opening balance',
    );
    await tester.pumpAndSettle();
    expect(find.text('Office'), findsOneWidget);
    expect(find.text('1 of 1 records'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('ledger-search')),
      'no matching transaction',
    );
    await tester.pumpAndSettle();
    expect(find.text('No matching transactions'), findsOneWidget);
    expect(find.text('Total deposits'), findsOneWidget);
  });

  testWidgets('collectors can view shared data but cannot manage collections',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    const session = AuthSession(
      token: 'test-token',
      userId: 'test-collector',
      name: 'Test Collector',
      email: 'collector@example.com',
      role: 'Collector',
      accountNumber: '100002',
      permissions: {
        'shared_data_read': true,
        'own_collection_read': true,
        'collection_manage': false,
        'deposit_view': true,
        'deposit_manage': false,
        'ledger_manage': false,
        'user_manage': false,
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: session,
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byType(NavigationDestination),
      ),
      findsNWidgets(5),
    );
    expect(find.text('Users'), findsOneWidget);
    expect(find.byKey(const Key('add-ledger-entry')), findsNothing);

    await _openDrawerPage(tester, 'navigation-menu-accounts');
    expect(find.text('Ledger overview'), findsOneWidget);
    await _openDrawerPage(tester, 'navigation-menu-daily');
    expect(find.byKey(const Key('add-collection-entry')), findsNothing);
    await tester.tap(find.text('Jordan Member'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit-collection-2')), findsNothing);
    expect(find.byKey(const Key('delete-collection-2')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('payment-schedule-2')));
    await tester.tap(find.byKey(const Key('payment-schedule-2')));
    await tester.pumpAndSettle();
    final paymentChip =
        tester.widget<FilterChip>(find.byKey(const Key('schedule-chip-2-0')));
    expect(paymentChip.onSelected, isNull);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jordan Member'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();
    await tester.drag(
      find
          .descendant(
            of: find.byType(Drawer),
            matching: find.byType(ListView),
          )
          .first,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('navigation-menu-users')));
    await tester.pumpAndSettle();
    expect(find.text('Morgan Member'), findsOneWidget);
    expect(find.text('Account No: DRD000000001'), findsOneWidget);
    expect(find.byKey(const Key('add-user')), findsNothing);
    expect(find.byKey(const Key('manage-user-user-1')), findsNothing);
  });

  testWidgets('members only see their own collections and cannot edit them',
      (WidgetTester tester) async {
    final apiService = _FakeApiService()
      ..collections['Daily_Collection']!.add({
        'memberName': 'Other Member',
        'date': '2026-01-02',
        'depAmt': 30,
        'totalCount': 1,
        'totalReceived': 30,
        'periods': [true],
        'rowIndex': 3,
      });
    const session = AuthSession(
      token: 'test-token',
      userId: 'test-member',
      name: 'Jordan Member',
      email: 'jordan@example.com',
      role: 'Member',
      accountNumber: '100003',
      permissions: {
        'shared_data_read': false,
        'own_collection_read': true,
        'collection_manage': false,
        'deposit_view': false,
        'deposit_manage': false,
        'ledger_manage': false,
        'user_manage': false,
      },
      reportAccess: {
        'daily': true,
        'weekly': false,
        'monthly': false,
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: session,
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byType(NavigationDestination),
      ),
      findsNWidgets(2),
    );
    expect(find.byKey(const Key('navigation-menu-accounts')), findsNothing);
    expect(find.byKey(const Key('navigation-menu-users')), findsNothing);
    expect(find.byKey(const Key('navigation-menu-weekly')), findsNothing);
    expect(find.byKey(const Key('navigation-menu-monthly')), findsNothing);
    expect(apiService.fetchActions, isNot(contains('getAmount')));
    expect(apiService.fetchActions, isNot(contains('getUsers')));
    expect(apiService.fetchActions, isNot(contains('getWeekly')));
    expect(apiService.fetchActions, isNot(contains('getMonthly')));

    await _openDrawerPage(tester, 'navigation-menu-daily');
    expect(find.text('Jordan Member'), findsOneWidget);
    expect(find.text('Other Member'), findsNothing);
    expect(find.byKey(const Key('add-collection-entry')), findsNothing);
    await tester.tap(find.text('Jordan Member'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('payment-schedule-2')));
    await tester.tap(find.byKey(const Key('payment-schedule-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit-collection-2')), findsNothing);
    expect(find.byKey(const Key('delete-collection-2')), findsNothing);
    final scheduleChip =
        tester.widget<FilterChip>(find.byKey(const Key('schedule-chip-2-0')));
    expect(scheduleChip.onSelected, isNull);
  });

  testWidgets('member dashboard shows matching report details only',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    for (final sheetName in [
      'Daily_Collection',
      'Weekly_Collection',
      'Monthly_Collection',
    ]) {
      apiService.collections[sheetName]!.add({
        'memberName': '  jordan   member ',
        'date': '2026-02-01',
        'depAmt': 35,
        'totalCount': 2,
        'totalReceived': 70,
        'periods': [true, true],
        'rowIndex': 2,
      });
      apiService.collections[sheetName]!.add({
        'memberName': 'Other Member',
        'date': '2026-01-02',
        'depAmt': 99,
        'totalCount': 3,
        'totalReceived': 297,
        'periods': [true, true, true],
        'rowIndex': 3,
      });
    }
    apiService.depositAccounts.addAll([
      {
        'id': 'member-deposit-own',
        'product': 'RD',
        'cadence': 'monthly',
        'memberName': '  jordan   member ',
        'maturityAmount': 420,
        'payments': <bool>[true, false],
      },
      {
        'id': 'member-deposit-other',
        'product': 'RD',
        'cadence': 'monthly',
        'memberName': 'Other Member',
        'maturityAmount': 999,
        'payments': <bool>[true],
      },
    ]);
    const session = AuthSession(
      token: 'member-token',
      userId: 'member-1',
      name: 'Jordan Member',
      email: 'jordan@example.com',
      role: 'Member',
      permissions: {
        'shared_data_read': true,
        'own_collection_read': true,
        'collection_manage': true,
        'deposit_view': true,
        'deposit_manage': true,
        'ledger_manage': true,
        'user_manage': true,
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: session,
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('My dashboard'), findsOneWidget);
    expect(find.text('My total contributions'), findsOneWidget);
    final dashboardList = find.byType(ListView).first;
    final dailyDetails =
        find.byKey(const Key('member-report-detail-daily-2-2026-02-01'));
    await _scrollUntilBuilt(
      tester,
      dailyDetails,
      dashboardList,
    );
    await tester.ensureVisible(dailyDetails);
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const Key('member-report-detail-daily-2-2026-02-01'),
      ),
      findsOneWidget,
    );
    final weeklyDetails =
        find.byKey(const Key('member-report-detail-weekly-2-2026-02-01'));
    await _scrollUntilBuilt(
      tester,
      weeklyDetails,
      dashboardList,
    );
    await tester.ensureVisible(weeklyDetails);
    expect(
      find.byKey(
        const Key('member-report-detail-weekly-2-2026-02-01'),
      ),
      findsOneWidget,
    );
    final monthlyDetails =
        find.byKey(const Key('member-report-detail-monthly-2-2026-02-01'));
    await _scrollUntilBuilt(
      tester,
      monthlyDetails,
      dashboardList,
    );
    await tester.ensureVisible(monthlyDetails);
    expect(
      find.byKey(
        const Key('member-report-detail-monthly-2-2026-02-01'),
      ),
      findsOneWidget,
    );
    final rdSummary = find.byKey(const Key('dashboard-deposit-rd-monthly'));
    await _scrollUntilBuilt(tester, rdSummary, dashboardList);
    await tester.ensureVisible(rdSummary);
    expect(
      find.textContaining('My estimated maturity ₹420'),
      findsOneWidget,
    );
    expect(find.text('Other Member'), findsNothing);
    expect(apiService.fetchActions, isNot(contains('getAmount')));
    expect(apiService.fetchActions, isNot(contains('getUsers')));
  });

  testWidgets('member dashboard shows only reports enabled for the account',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    const session = AuthSession(
      token: 'member-token',
      userId: 'member-1',
      name: 'Jordan Member',
      email: 'jordan@example.com',
      role: 'Member',
      permissions: {
        'own_collection_read': true,
      },
      reportAccess: {
        'daily': true,
        'weekly': false,
        'monthly': false,
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: session,
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Jordan Member'), findsNWidgets(2));
    await tester.scrollUntilVisible(
      find.byKey(const Key('dashboard-collection-daily')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Daily collection'), findsOneWidget);
    expect(find.text('Weekly collection'), findsNothing);
    expect(find.text('Monthly collection'), findsNothing);
    expect(apiService.fetchActions, contains('getDaily'));
    expect(apiService.fetchActions, isNot(contains('getWeekly')));
    expect(apiService.fetchActions, isNot(contains('getMonthly')));
    expect(apiService.fetchActions, isNot(contains('getAmount')));
    expect(apiService.fetchActions, isNot(contains('getUsers')));
  });

  testWidgets('ledger entry uses staff dropdown and saves selected person',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(NtccslAccountApp(apiService: apiService));
    await _signIn(tester);
    await _openDrawerPage(tester, 'navigation-menu-accounts');

    await tester.tap(find.byKey(const Key('add-ledger-entry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ledger-entry-by')), findsOneWidget);
    expect(find.byKey(const Key('ledger-pay-mode')), findsOneWidget);
    final balanceField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('ledger-balance')),
        matching: find.byType(TextField),
      ),
    );
    expect(balanceField.readOnly, isTrue);
    expect(
      balanceField.style?.color,
      Theme.of(tester.element(find.byKey(const Key('ledger-balance'))))
          .colorScheme
          .error,
    );
    await tester.enterText(find.byKey(const Key('ledger-by-whom')), 'Office');
    await tester.enterText(find.byKey(const Key('ledger-deposit')), '250');
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('ledger-balance')),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      '350',
    );
    await tester.tap(find.byKey(const Key('ledger-pay-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('G Pay').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ledger-entry-by')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nur Mahammad').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-ledger-entry')));
    await tester.pumpAndSettle();

    expect(apiService.ledgerRequests, hasLength(1));
    expect(apiService.ledgerRequests.single['action'], 'addAmount');
    expect(apiService.ledgerRequests.single['payMode'], 'G Pay');
    expect(apiService.ledgerRequests.single['entryBy'], 'Nur Mahammad');
    expect(apiService.ledgerRequests.single['deposit'], '250');
    expect(apiService.ledgerRequests.single['balance'], '350');
    expect(find.text('Ledger entry added.'), findsOneWidget);
  });

  testWidgets('ledger withdrawal subtracts from previous balance',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(NtccslAccountApp(apiService: apiService));
    await _signIn(tester);
    await _openDrawerPage(tester, 'navigation-menu-accounts');

    await tester.tap(find.byKey(const Key('add-ledger-entry')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ledger-withdrawal')), '40');

    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('ledger-balance')),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      '60',
    );
    await tester.tap(find.byKey(const Key('save-ledger-entry')));
    await tester.pumpAndSettle();

    expect(apiService.ledgerRequests.single['withdrawal'], '40');
    expect(apiService.ledgerRequests.single['balance'], '60');
  });

  testWidgets('ledger entry can be viewed, edited, and deleted',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(NtccslAccountApp(apiService: apiService));
    await _signIn(tester);
    await _openDrawerPage(tester, 'navigation-menu-accounts');

    await tester.tap(find.text('Office'));
    await tester.pumpAndSettle();
    expect(find.text('Ledger entry details'), findsOneWidget);
    expect(find.text('Opening balance'), findsOneWidget);
    expect(find.text('Entry by'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('manage-ledger-2')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Icon>(find.byIcon(Icons.edit_outlined)).color,
      portalEditColor,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.delete_outline)).color,
      portalDeleteColor,
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Ledger Entry'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('ledger-remarks')), 'Updated note');
    await tester.enterText(find.byKey(const Key('ledger-deposit')), '350');
    await tester.ensureVisible(find.byKey(const Key('save-ledger-entry')));
    await tester.tap(find.byKey(const Key('save-ledger-entry')));
    await tester.pumpAndSettle();

    expect(apiService.ledgerActions.last['action'], 'editAmount');
    expect(apiService.ledgerActions.last['rowIndex'], 2);
    expect(apiService.ledgerEntries.single['remarks'], 'Updated note');
    expect(apiService.ledgerEntries.single['deposit'], '350');
    expect(find.text('Ledger entry updated.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('manage-ledger-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete ledger entry?'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('confirm-delete-ledger')))
          .style!
          .backgroundColor!
          .resolve({}),
      portalDeleteColor,
    );
    await tester.tap(find.byKey(const Key('confirm-delete-ledger')));
    await tester.pumpAndSettle();

    expect(apiService.ledgerEntries, isEmpty);
    expect(apiService.ledgerActions.last['action'], 'deleteAmount');
    expect(find.text('Ledger entry deleted.'), findsOneWidget);
  });

  testWidgets('profile changes password after confirming new password',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(NtccslAccountApp(apiService: apiService));
    await _signIn(tester);
    await tester.tap(find.byKey(const Key('open-profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('change-password')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('profile-current-password')),
      'old-password',
    );
    await tester.enterText(
      find.byKey(const Key('profile-new-password')),
      'new-password',
    );
    await tester.enterText(
      find.byKey(const Key('profile-confirm-password')),
      'not-the-same',
    );
    await tester.ensureVisible(find.byKey(const Key('save-profile-password')));
    await tester.tap(find.byKey(const Key('save-profile-password')));
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(apiService.passwordChanges, isEmpty);

    await tester.enterText(
      find.byKey(const Key('profile-confirm-password')),
      'new-password',
    );
    await tester.ensureVisible(find.byKey(const Key('save-profile-password')));
    await tester.tap(find.byKey(const Key('save-profile-password')));
    await tester.pumpAndSettle();

    expect(apiService.passwordChanges, hasLength(1));
    expect(
        apiService.passwordChanges.single['currentPassword'], 'old-password');
    expect(apiService.passwordChanges.single['newPassword'], 'new-password');
    expect(apiService.passwordChanges.single['token'], 'test-token');
    expect(find.text('Password changed successfully.'), findsOneWidget);
  });

  testWidgets('profile can update name, email, and profile image',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    final originalImagePicker = ImagePickerPlatform.instance;
    final imageBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADUlEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
    );
    ImagePickerPlatform.instance = _FakeImagePickerPlatform(imageBytes);
    addTearDown(() {
      ImagePickerPlatform.instance = originalImagePicker;
    });
    AuthSession? updatedSession;
    const session = AuthSession(
      token: 'test-token',
      userId: 'admin-1',
      name: 'Admin',
      email: 'admin@example.com',
      role: 'Admin',
      accountNumber: 'ADM123456789',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProfilePage(
          apiService: apiService,
          session: session,
          onSessionUpdated: (value) => updatedSession = value,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('edit-profile')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('edit-profile-name')),
      'Updated Admin',
    );
    await tester.enterText(
      find.byKey(const Key('edit-profile-email')),
      'updated@example.com',
    );
    await tester.tap(find.byKey(const Key('edit-profile-upload-image')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit-profile-image-preview')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('save-profile')));
    await tester.tap(find.byKey(const Key('save-profile')));
    await tester.pumpAndSettle();

    expect(find.text('Updated Admin'), findsOneWidget);
    expect(find.text('updated@example.com'), findsOneWidget);
    expect(updatedSession?.name, 'Updated Admin');
    expect(updatedSession?.email, 'updated@example.com');
    expect(
        updatedSession?.profileImageUrl, startsWith('data:image/png;base64,'));
    expect(apiService.profileUpdates.single['action'], 'updateMyProfile');
    expect(apiService.profileUpdates.single['profileImageChanged'], isTrue);
    expect(
      apiService.profileUpdates.single['profileImageData'],
      base64Encode(imageBytes),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('admins can add, edit, and delete users',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    final originalImagePicker = ImagePickerPlatform.instance;
    final imageBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADUlEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
    );
    ImagePickerPlatform.instance = _FakeImagePickerPlatform(imageBytes);
    addTearDown(() {
      ImagePickerPlatform.instance = originalImagePicker;
    });
    await tester.pumpWidget(NtccslAccountApp(apiService: apiService));
    await _signIn(tester);

    await tester.tap(find.text('Users'));
    await tester.pumpAndSettle();
    expect(find.text('Morgan Member'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-user')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const Key('user-password')),
              matching: find.byType(EditableText),
            ),
          )
          .obscureText,
      isTrue,
    );
    await tester.ensureVisible(
      find.byKey(const Key('user-password-visibility')),
    );
    await tester.tap(find.byKey(const Key('user-password-visibility')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const Key('user-password')),
              matching: find.byType(EditableText),
            ),
          )
          .obscureText,
      isFalse,
    );
    await tester.tap(find.byKey(const Key('user-password-visibility')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('user-name')), 'New Person');
    await tester.enterText(
      find.byKey(const Key('user-email')),
      'new@example.com',
    );
    await tester.ensureVisible(
      find.byKey(const Key('upload-user-profile-image')),
    );
    await tester.tap(find.byKey(const Key('upload-user-profile-image')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('user-profile-image-preview')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('user-password')),
      'temporary-pass',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
        apiService.users.any((user) => user['name'] == 'New Person'), isTrue);
    expect(apiService.userRequests.last['profileImageChanged'], isTrue);
    expect(apiService.userRequests.last['profileImageMimeType'], 'image/png');
    expect(
      apiService.userRequests.last['profileImageData'],
      base64Encode(imageBytes),
    );
    expect(find.text('User added.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('users-search')),
      'taylor@example.com',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('manage-user-user-2')));
    await tester.drag(find.byType(ListView).last, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manage-user-user-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('user-name')), 'Updated Person');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      apiService.users.any((user) => user['name'] == 'Updated Person'),
      isTrue,
    );
    expect(find.text('User updated.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('manage-user-user-2')));
    await tester.drag(find.byType(ListView).last, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manage-user-user-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(apiService.users.any((user) => user['id'] == 'user-2'), isFalse);
    expect(find.text('User deleted.'), findsOneWidget);
  });

  testWidgets('admin user tabs filter accounts and preselect role on add',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: const AuthSession(
            token: 'test-token',
            userId: 'admin-1',
            name: 'Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();
    await tester.drag(
      find
          .descendant(
            of: find.byType(Drawer),
            matching: find.byType(ListView),
          )
          .first,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('navigation-menu-users')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('users-search')),
      'taylor@example.com',
    );
    await tester.pumpAndSettle();
    expect(find.text('Taylor Member'), findsOneWidget);
    await tester.tap(find.byKey(const Key('users-search-clear')));
    await tester.pumpAndSettle();
    expect(find.text('Morgan Member'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('users-search')))
          .controller
          ?.text,
      isEmpty,
    );
    expect(find.byKey(const Key('users-overview-card')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('users-total-count'))).data,
      '2',
    );
    expect(find.text('D On'), findsOneWidget);
    expect(find.text('W On'), findsOneWidget);
    expect(find.text('M On'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('users-search')),
      'taylor@example.com',
    );
    await tester.pumpAndSettle();
    expect(find.text('Taylor Member'), findsOneWidget);
    expect(find.text('Morgan Member'), findsNothing);
    await tester.tap(find.byKey(const Key('users-search-clear')));
    await tester.pumpAndSettle();
    expect(find.text('Morgan Member'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('users-visible-count'))).data,
      '2 members',
    );
    await tester.enterText(
      find.byKey(const Key('users-search')),
      'DRD000000002',
    );
    await tester.pumpAndSettle();
    expect(find.text('Taylor Member'), findsOneWidget);
    expect(find.text('Morgan Member'), findsNothing);
    await tester.tap(find.byKey(const Key('users-search-clear')));
    await tester.pumpAndSettle();
    final memberRoleChip = tester
        .widget<FilterChip>(find.byKey(const Key('user-role-chip-member')));
    expect(memberRoleChip.selected, isTrue);
    expect(
      memberRoleChip.selectedColor,
      portalRoleColor('Member').withValues(alpha: .10),
    );
    expect(
      tester
          .widget<Container>(
            find.byKey(const Key('user-role-badge-user-1')),
          )
          .decoration,
      isA<BoxDecoration>().having(
        (decoration) => decoration.color,
        'member role tint',
        portalRoleColor('Member').withValues(alpha: .11),
      ),
    );
    await tester.tap(find.byKey(const Key('user-role-tab-collector')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilterChip>(
            find.byKey(const Key('user-role-chip-collector')),
          )
          .selectedColor,
      portalRoleColor('Collector').withValues(alpha: .10),
    );
    expect(find.text('No Collector accounts'), findsOneWidget);
    expect(find.text('Morgan Member'), findsNothing);
    await tester.tap(find.byKey(const Key('add-user')));
    await tester.pumpAndSettle();
    expect(find.text('Add User'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const Key('user-role')),
          )
          .initialValue,
      'Collector',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    tester
        .widget<FilterChip>(find.byKey(const Key('user-role-chip-member')))
        .onSelected!(true);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-user')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const Key('user-role')),
          )
          .initialValue,
      'Member',
    );
    expect(find.byKey(const Key('member-daily-access')), findsOneWidget);
    expect(find.byKey(const Key('member-weekly-access')), findsOneWidget);
    expect(find.byKey(const Key('member-monthly-access')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('user-name')), 'New Member');
    await tester.enterText(
      find.byKey(const Key('user-email')),
      'new.member@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('user-password')),
      'secure-pass',
    );
    await tester.ensureVisible(find.byKey(const Key('member-weekly-access')));
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('member-weekly-access')),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(apiService.userRequests.last['action'], 'addUser');
    expect(apiService.userRequests.last['dailyAccess'], isTrue);
    expect(apiService.userRequests.last['weeklyAccess'], isFalse);
    expect(apiService.userRequests.last['monthlyAccess'], isTrue);
  });

  testWidgets('admins can edit and save role permissions',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: const AuthSession(
            token: 'admin-token',
            userId: 'admin-1',
            name: 'Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();
    await tester.drag(
      find
          .descendant(
            of: find.byType(Drawer),
            matching: find.byType(ListView),
          )
          .first,
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const Key('navigation-menu-roles & permissions')));
    await tester.pumpAndSettle();

    expect(find.text('Roles & Permissions'), findsNWidgets(2));
    expect(
      tester
          .widget<Container>(
            find.byKey(const Key('role-permission-color-collector')),
          )
          .decoration,
      isA<BoxDecoration>().having(
        (decoration) => decoration.color,
        'collector role color',
        portalRoleColor('Collector').withValues(alpha: .12),
      ),
    );
    final collectorLedgerPermission = find.byKey(
      const Key('permission-collector-ledger_manage'),
    );
    await tester.scrollUntilVisible(
      collectorLedgerPermission,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    final collectorPermission =
        tester.widget<SwitchListTile>(collectorLedgerPermission);
    expect(collectorPermission.value, isTrue);
    expect(collectorPermission.activeTrackColor, portalRoleColor('Collector'));
    await tester.tap(collectorLedgerPermission);
    await tester.pumpAndSettle();
    final memberCollectionPermission = find.byKey(
      const Key('permission-member-collection_manage'),
    );
    await tester.scrollUntilVisible(
      memberCollectionPermission,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    final memberCollectionSwitch =
        tester.widget<SwitchListTile>(memberCollectionPermission);
    expect(memberCollectionSwitch.value, isFalse);
    expect(memberCollectionSwitch.onChanged, isNull);
    final memberSharedReadPermission = find.byKey(
      const Key('permission-member-shared_data_read'),
    );
    await tester.scrollUntilVisible(
      memberSharedReadPermission,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await Scrollable.ensureVisible(
      tester.element(memberSharedReadPermission),
      alignment: 0.4,
    );
    await tester.pumpAndSettle();
    final memberSharedReadSwitch =
        tester.widget<SwitchListTile>(memberSharedReadPermission);
    expect(memberSharedReadSwitch.value, isFalse);
    expect(memberSharedReadSwitch.onChanged, isNotNull);
    await tester.tap(
      find.descendant(
        of: memberSharedReadPermission,
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(memberSharedReadPermission).value,
      isTrue,
    );
    final memberOwnReadPermission = find.byKey(
      const Key('permission-member-own_collection_read'),
    );
    await tester.scrollUntilVisible(
      memberOwnReadPermission,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    final memberOwnReadSwitch =
        tester.widget<SwitchListTile>(memberOwnReadPermission);
    expect(memberOwnReadSwitch.value, isTrue);
    expect(memberOwnReadSwitch.onChanged, isNotNull);
    final memberDepositViewPermission = find.byKey(
      const Key('permission-member-deposit_view'),
    );
    await tester.scrollUntilVisible(
      memberDepositViewPermission,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await Scrollable.ensureVisible(
      tester.element(memberDepositViewPermission),
      alignment: 0.4,
    );
    await tester.pumpAndSettle();
    final memberDepositViewSwitch =
        tester.widget<SwitchListTile>(memberDepositViewPermission);
    expect(memberDepositViewSwitch.value, isTrue);
    expect(memberDepositViewSwitch.onChanged, isNotNull);
    await tester.tap(
      find.descendant(
        of: memberDepositViewPermission,
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    final savePermissionsButton =
        find.byKey(const Key('save-role-permissions'));
    await tester.ensureVisible(savePermissionsButton);
    await tester.tap(savePermissionsButton);
    await tester.pumpAndSettle();

    expect(apiService.savedRolePermissions, isNotNull);
    expect(apiService.savedRolePermissions!['Collector']!['ledger_manage'],
        isFalse);
    expect(apiService.savedRolePermissions!['Member'], {
      'shared_data_read': true,
      'own_collection_read': true,
      'collection_manage': false,
      'deposit_view': false,
      'deposit_manage': false,
      'ledger_manage': false,
      'user_manage': false,
    });
    expect(find.textContaining('should sign in again'), findsOneWidget);
  });

  testWidgets('daily, weekly, and monthly pages add collection entries',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(NtccslAccountApp(apiService: apiService));
    await _signIn(tester);

    const collectionPages = {
      'Daily': 'Daily_Collection',
      'Weekly': 'Weekly_Collection',
      'Monthly': 'Monthly_Collection',
    };
    for (final entry in collectionPages.entries) {
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('add-collection-entry')), findsOneWidget);
      if (entry.key == 'Daily') {
        expect(find.text('Amount received'), findsOneWidget);
        expect(find.text('₹25'), findsNWidgets(2));
        expect(find.text('1 payment marked'), findsOneWidget);
      }

      await tester.tap(find.byKey(const Key('add-collection-entry')));
      await tester.pumpAndSettle();
      expect(find.text('Add ${entry.key.toLowerCase()} entry'), findsOneWidget);
      expect(
        find.text('Select the periods that are already paid.'),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('collection-start-date'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('collection-member-name'))).dy,
        ),
      );
      expect(find.textContaining('Start date:'), findsOneWidget);
      expect(find.byKey(const Key('form-schedule-chip-0')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('form-schedule-chip-0')),
      );
      await tester.tap(find.byKey(const Key('form-schedule-chip-0')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const Key('form-schedule-chip-0')),
            )
            .selected,
        isTrue,
      );
      expect(
        tester.widget<GridView>(find.byType(GridView)).gridDelegate
            as SliverGridDelegateWithFixedCrossAxisCount,
        isA<SliverGridDelegateWithFixedCrossAxisCount>().having(
          (delegate) => delegate.crossAxisCount,
          'crossAxisCount',
          3,
        ),
      );

      await tester
          .ensureVisible(find.byKey(const Key('save-collection-entry')));
      await tester.tap(find.byKey(const Key('save-collection-entry')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a member name'), findsOneWidget);
      expect(
        apiService.collectionRequests.length,
        collectionPages.keys.toList().indexOf(entry.key),
      );

      await tester.enterText(
        find.byKey(const Key('collection-member-name')),
        'Jordan Member',
      );
      await tester.enterText(
        find.byKey(const Key('collection-amount')),
        '25',
      );
      await tester
          .ensureVisible(find.byKey(const Key('save-collection-entry')));
      await tester.tap(find.byKey(const Key('save-collection-entry')));
      await tester.pumpAndSettle();
      expect(find.text('Collection entry added.'), findsOneWidget);
    }

    expect(
      apiService.collectionRequests.map((request) => request['sheetName']),
      collectionPages.values,
    );
    expect(
      apiService.collectionRequests
          .every((request) => request['memberName'] == 'Jordan Member'),
      isTrue,
    );
    expect(
      apiService.collectionRequests.every((request) => request['depAmt'] == 25),
      isTrue,
    );
    expect(
      apiService.collectionRequests.every(
        (request) =>
            (request['periods'] as List).first == true &&
            (request['periods'] as List).skip(1).every((paid) => !paid),
      ),
      isTrue,
    );
    expect(
      apiService.collectionRequests.every(
        (request) =>
            RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(request['date'] as String),
      ),
      isTrue,
    );
  });

  testWidgets('collection entries can be edited and deleted',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(NtccslAccountApp(apiService: apiService));
    await _signIn(tester);
    await tester.tap(find.text('Daily'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Jordan Member'));
    await tester.pumpAndSettle();
    final grandTotal = tester.widget<Text>(
      find.byKey(const Key('collection-grand-total-2')),
    );
    expect(grandTotal.data, contains('Paid: 1 days'));
    final collectionColors = Theme.of(
            tester.element(find.byKey(const Key('collection-grand-total-2'))))
        .colorScheme;
    expect(grandTotal.style?.color, collectionColors.primary);
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const Key('payment-schedule-2'))),
      alignment: 0.3,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('payment-schedule-2')));
    await tester.pumpAndSettle();
    final paymentChips = tester.widgetList<FilterChip>(find.byType(FilterChip));
    final paidChip = paymentChips.singleWhere((chip) => chip.selected);
    expect(paidChip.selectedColor, collectionColors.primaryContainer);
    expect(paidChip.checkmarkColor, collectionColors.onPrimaryContainer);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jordan Member'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('edit-collection-2')));
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('edit-collection-2')),
          )
          .style!
          .foregroundColor!
          .resolve({}),
      portalEditColor,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('delete-collection-2')),
          )
          .style!
          .foregroundColor!
          .resolve({}),
      portalDeleteColor,
    );
    await tester.tap(find.byKey(const Key('edit-collection-2')));
    await tester.pumpAndSettle();
    expect(find.text('Edit daily entry'), findsOneWidget);
    expect(find.byKey(const Key('collection-grand-total')), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const Key('collection-start-date'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('collection-member-name'))).dy,
      ),
    );
    await tester.enterText(
      find.byKey(const Key('collection-member-name')),
      'Jordan Updated',
    );
    await tester.enterText(
      find.byKey(const Key('collection-amount')),
      '40',
    );
    await tester.ensureVisible(find.byKey(const Key('save-collection-entry')));
    await tester.tap(find.byKey(const Key('save-collection-entry')));
    await tester.pumpAndSettle();

    expect(apiService.collections['Daily_Collection']!.single['memberName'],
        'Jordan Updated');
    expect(apiService.collections['Daily_Collection']!.single['depAmt'], 40.0);
    expect(
      apiService.collections['Daily_Collection']!.single['grandTotal'],
      100,
    );
    expect(apiService.collectionActions.last['action'], 'editCollection');
    expect(
        apiService.collectionActions.last.containsKey('grandTotal'), isFalse);
    expect(find.text('Collection entry updated.'), findsOneWidget);

    await tester.tap(find.text('Jordan Updated'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('delete-collection-2')));
    await tester.tap(find.byKey(const Key('delete-collection-2')));
    await tester.pumpAndSettle();
    expect(find.text('Delete collection entry?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-delete-collection')));
    await tester.pumpAndSettle();

    expect(apiService.collections['Daily_Collection'], isEmpty);
    expect(apiService.collectionActions.last['action'], 'deleteCollection');
    expect(find.text('Collection entry deleted.'), findsOneWidget);
  });

  testWidgets('payment schedule popup lays out periods in three columns',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(NtccslAccountApp(apiService: apiService));
    await _signIn(tester);
    await tester.tap(find.text('Daily'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Jordan Member'));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const Key('payment-schedule-2'))),
      alignment: 0.3,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('payment-schedule-2')));
    await tester.pumpAndSettle();

    expect(find.text('Payment schedule'), findsOneWidget);
    final grid = tester.widget<GridView>(find.byType(GridView).last);
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      3,
    );
    expect(find.byKey(const Key('schedule-chip-2-0')), findsOneWidget);
    expect(find.byKey(const Key('schedule-chip-2-1')), findsOneWidget);
  });

  test('API login and authenticated actions use the session token', () async {
    final client = _RecordingHttpClient([
      {
        'status': 'success',
        'token': 'session-token',
        'user': {
          'id': 'admin-1',
          'accountNo': 'ADM123456789',
          'name': 'Admin',
          'profileImageUrl':
              'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jA9sAAAAASUVORK5CYII=',
          'email': 'admin@example.com',
          'role': 'Admin',
        },
      },
      [
        {
          'id': 'user-1',
          'accountNo': 'DRD000000001',
          'name': 'Morgan Member',
          'email': 'morgan@example.com',
          'role': 'Member',
          'profileImageUrl': '',
        },
      ],
      {'status': 'success'},
    ]);
    final apiService = ApiService(client: client);

    final session = await apiService.login('admin@example.com', 'password');
    expect(session.accountNumber, 'ADM123456789');
    expect(
      session.profileImageUrl,
      'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jA9sAAAAASUVORK5CYII=',
    );
    final users = await apiService.fetchSheetData('getUsers', session);
    final saved = await apiService.sendPostRequest({
      'action': 'editUser',
      'userId': 'user-1',
      'name': 'Morgan Updated',
    }, session);

    expect(users, hasLength(1));
    expect(saved, isTrue);
    expect(client.payloads.map((payload) => payload['action']), [
      'login',
      'getUsers',
      'editUser',
    ]);
    expect(client.payloads[0]['password'], 'password');
    expect(client.payloads[0]['loginType'], 'staff');
    expect(client.payloads[1]['token'], 'session-token');
    expect(client.payloads[2]['token'], 'session-token');
  });

  test('role permissions read and save through authenticated API actions',
      () async {
    final client = _RecordingHttpClient([
      {
        'status': 'success',
        'permissions': {
          for (final role in ['Collector', 'Member'])
            role: {
              'shared_data_read': role == 'Collector',
              'own_collection_read': true,
              'collection_manage': false,
              'deposit_view': role == 'Collector',
              'deposit_manage': false,
              'ledger_manage': false,
              'user_manage': false,
            },
        },
      },
      {'status': 'success'},
    ]);
    final apiService = ApiService(client: client);
    const session = AuthSession(
      token: 'admin-session-token',
      userId: 'admin-1',
      name: 'Admin',
      email: 'admin@example.com',
      role: 'Admin',
    );

    final permissions = await apiService.fetchRolePermissions(session);
    await apiService.saveRolePermissions(permissions, session);

    expect(permissions['Collector']!['shared_data_read'], isTrue);
    expect(permissions['Member']!['collection_manage'], isFalse);
    expect(client.payloads.map((payload) => payload['action']), [
      'getRolePermissions',
      'setRolePermissions',
    ]);
    expect(client.payloads.first['token'], 'admin-session-token');
    expect(client.payloads.last['token'], 'admin-session-token');
    expect(client.payloads.last['permissions'], permissions);
  });

  test('unsupported role permissions action explains how to update deployment',
      () async {
    final apiService = ApiService(
      client: _RecordingHttpClient([
        {
          'status': 'error',
          'message': 'Unknown post action: getRolePermissions'
        },
      ]),
    );
    const session = AuthSession(
      token: 'admin-session-token',
      userId: 'admin-1',
      name: 'Admin',
      email: 'admin@example.com',
      role: 'Admin',
    );

    await expectLater(
      apiService.fetchRolePermissions(session),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('does not support role permissions'),
            contains('deploy a new web-app version'),
          ),
        ),
      ),
    );
  });

  test('member login sends member type and rejects a staff response', () async {
    final client = _RecordingHttpClient([
      {
        'status': 'success',
        'token': 'session-token',
        'user': {
          'id': 'staff-1',
          'name': 'Collector',
          'email': 'collector@example.com',
          'role': 'Collector',
        },
      },
    ]);
    final apiService = ApiService(client: client);

    await expectLater(
      apiService.login(
        'collector@example.com',
        'password',
        loginType: 'member',
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('Choose Admin / Collector login instead'),
        ),
      ),
    );
    expect(client.payloads.single['loginType'], 'member');
  });

  test('registration sends account details without a client-selected role',
      () async {
    final client = _RecordingHttpClient([
      {'status': 'success'},
    ]);
    final apiService = ApiService(client: client);

    await apiService.register(
      name: 'Sam Member',
      email: 'sam@example.com',
      password: 'secure-pass',
    );

    expect(client.payloads.single, {
      'action': 'register',
      'name': 'Sam Member',
      'email': 'sam@example.com',
      'password': 'secure-pass',
    });
  });

  test('adding a collection entry sends its authenticated sheet fields',
      () async {
    final client = _RecordingHttpClient([
      {'status': 'success'},
    ]);
    final apiService = ApiService(client: client);
    const session = AuthSession(
      token: 'session-token',
      userId: 'admin-1',
      name: 'Admin',
      email: 'admin@example.com',
      role: 'Admin',
    );

    final saved = await apiService.sendPostRequest({
      'action': 'addCollection',
      'sheetName': 'Weekly_Collection',
      'memberName': 'Jordan Member',
      'date': '2026-01-02',
      'depAmt': 25,
    }, session);

    expect(saved, isTrue);
    expect(client.payloads.single, {
      'action': 'addCollection',
      'sheetName': 'Weekly_Collection',
      'memberName': 'Jordan Member',
      'date': '2026-01-02',
      'depAmt': 25,
      'token': 'session-token',
    });
  });

  test('deposit account reads include product, cadence, and session token',
      () async {
    final client = _RecordingHttpClient([
      [
        {
          'id': 'deposit-1',
          'product': 'RD',
          'cadence': 'monthly',
          'payments': [false],
        },
      ],
    ]);
    final apiService = ApiService(client: client);
    const session = AuthSession(
      token: 'session-token',
      userId: 'admin-1',
      name: 'Admin',
      email: 'admin@example.com',
      role: 'Admin',
    );

    final accounts = await apiService.fetchDepositAccounts(
      product: 'RD',
      cadence: 'monthly',
      session: session,
    );

    expect(accounts.single['id'], 'deposit-1');
    expect(client.payloads.single, {
      'action': 'getDepositAccounts',
      'token': 'session-token',
      'product': 'RD',
      'cadence': 'monthly',
    });
  });

  test('collection request retries once when the server lock is busy',
      () async {
    final client = _RecordingHttpClient([
      {'status': 'error', 'message': 'The service is busy. Please try again.'},
      {'status': 'success'},
    ]);
    final apiService = ApiService(client: client);
    const session = AuthSession(
      token: 'session-token',
      userId: 'admin-1',
      name: 'Admin',
      email: 'admin@example.com',
      role: 'Admin',
    );

    final saved = await apiService.sendPostRequest({
      'action': 'toggleCollection',
      'sheetName': 'Daily_Collection',
      'rowIndex': 2,
      'periodIndex': 365,
    }, session);

    expect(saved, isTrue);
    expect(client.payloads, hasLength(2));
    expect(client.payloads[0], client.payloads[1]);
  });

  test('editing and deleting collection entries include the session token',
      () async {
    final client = _RecordingHttpClient([
      {'status': 'success'},
      {'status': 'success'},
    ]);
    final apiService = ApiService(client: client);
    const session = AuthSession(
      token: 'session-token',
      userId: 'admin-1',
      name: 'Admin',
      email: 'admin@example.com',
      role: 'Admin',
    );

    await apiService.sendPostRequest({
      'action': 'editCollection',
      'sheetName': 'Daily_Collection',
      'rowIndex': 2,
      'memberName': 'Jordan Updated',
      'date': '2026-01-02',
      'depAmt': 40,
    }, session);
    await apiService.sendPostRequest({
      'action': 'deleteCollection',
      'sheetName': 'Daily_Collection',
      'rowIndex': 2,
    }, session);

    expect(
      client.payloads.map((payload) => payload['action']),
      ['editCollection', 'deleteCollection'],
    );
    expect(
      client.payloads.every((payload) => payload['token'] == 'session-token'),
      isTrue,
    );
  });

  test('change password sends current and new password with the session token',
      () async {
    final client = _RecordingHttpClient([
      {'status': 'success'},
    ]);
    final apiService = ApiService(client: client);
    const session = AuthSession(
      token: 'session-token',
      userId: 'admin-1',
      name: 'Admin',
      email: 'admin@example.com',
      role: 'Admin',
      accountNumber: 'ADM123456789',
    );

    final saved = await apiService.sendPostRequest({
      'action': 'changePassword',
      'currentPassword': 'current-password',
      'newPassword': 'new-password',
    }, session);

    expect(saved, isTrue);
    expect(client.payloads.single, {
      'action': 'changePassword',
      'currentPassword': 'current-password',
      'newPassword': 'new-password',
      'token': 'session-token',
    });
  });

  test('profile updates include authenticated identity and changed image',
      () async {
    final client = _RecordingHttpClient([
      {'status': 'success'},
    ]);
    final apiService = ApiService(client: client);
    const session = AuthSession(
      token: 'session-token',
      userId: 'member-1',
      name: 'Jordan Member',
      email: 'jordan@example.com',
      role: 'Member',
    );

    await apiService.updateMyProfile(
      session: session,
      name: 'Jordan Updated',
      email: 'updated@example.com',
      profileImageChanged: true,
      profileImageData: 'aW1hZ2U=',
      profileImageMimeType: 'image/png',
    );

    expect(client.payloads.single, {
      'action': 'updateMyProfile',
      'name': 'Jordan Updated',
      'email': 'updated@example.com',
      'profileImageChanged': true,
      'profileImageData': 'aW1hZ2U=',
      'profileImageMimeType': 'image/png',
      'token': 'session-token',
    });
  });

  test('unsupported login action reports that server setup is required',
      () async {
    for (final response in [
      {'status': 'error', 'message': 'Invalid action'},
      {'status': 'error', 'message': 'unknown post action'},
      'unknown post action',
    ]) {
      final apiService = ApiService(
        client: _RecordingHttpClient([response]),
      );

      await expectLater(
        apiService.login('admin@example.com', 'password'),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            contains('does not support email/password login yet'),
          ),
        ),
      );
    }
  });

  test('plain text unknown action response explains Apps Script setup',
      () async {
    final apiService = ApiService(
      client: _RecordingTextHttpClient('unknown post action'),
    );

    await expectLater(
      apiService.login('admin@example.com', 'password'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('Add a login action'),
        ),
      ),
    );
  });
}

Future<void> _signIn(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('login-email')),
    'admin@example.com',
  );
  await tester.enterText(
    find.byKey(const Key('login-password')),
    'correct-horse',
  );
  await tester.ensureVisible(find.byKey(const Key('login-submit')));
  await tester.tap(find.byKey(const Key('login-submit')));
  await tester.pumpAndSettle();
}

Future<void> _openDrawerPage(WidgetTester tester, String itemKey) async {
  await tester.tap(find.byKey(const Key('open-navigation-menu')));
  await tester.pumpAndSettle();
  final item = find.byKey(Key(itemKey));
  if (itemKey == 'navigation-menu-daily' ||
      itemKey == 'navigation-menu-weekly' ||
      itemKey == 'navigation-menu-monthly') {
    final collections =
        find.byKey(const Key('navigation-menu-existing-collections'));
    await _expandDrawerTile(tester, collections, item);
  }
  if (itemKey.startsWith('navigation-menu-fd-') ||
      itemKey.startsWith('navigation-menu-rd-') ||
      itemKey.startsWith('navigation-menu-drd-')) {
    final deposit = find.byKey(const Key('navigation-menu-deposit'));
    final product = find.byKey(
      Key(
        'navigation-menu-product-${itemKey.split('-')[2]}',
      ),
    );
    await _expandDrawerTile(tester, deposit, product);
    await _expandDrawerTile(tester, product, item);
  }
  await _ensureDrawerItemVisible(tester, item);
  await tester.tap(item);
  await tester.pumpAndSettle();
}

Future<void> _expandDrawerTile(
  WidgetTester tester,
  Finder tile,
  Finder child,
) async {
  if (child.evaluate().isNotEmpty) return;
  await _ensureDrawerItemVisible(tester, tile);
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

Future<void> _ensureDrawerItemVisible(
  WidgetTester tester,
  Finder item,
) async {
  final drawerList = find
      .descendant(
        of: find.byType(Drawer),
        matching: find.byType(ListView),
      )
      .first;
  final drawerScrollable = find
      .descendant(
        of: drawerList,
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(item, 200, scrollable: drawerScrollable);
  final listRect = tester.getRect(drawerList);
  final itemRect = tester.getRect(item);
  if (itemRect.bottom > listRect.bottom) {
    await tester.drag(
      drawerScrollable,
      Offset(0, listRect.bottom - itemRect.bottom - 8),
    );
    await tester.pumpAndSettle();
  } else if (itemRect.top < listRect.top) {
    await tester.drag(
      drawerScrollable,
      Offset(0, listRect.top - itemRect.top + 8),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> _scrollUntilBuilt(
  WidgetTester tester,
  Finder target,
  Finder scrollable,
) async {
  for (var attempt = 0; target.evaluate().isEmpty && attempt < 12; attempt++) {
    await tester.drag(scrollable, const Offset(0, -360));
    await tester.pumpAndSettle();
  }
  // ignore: avoid_print
  expect(target, findsOneWidget);
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter =
      firstLuminance > secondLuminance ? firstLuminance : secondLuminance;
  final darker =
      firstLuminance > secondLuminance ? secondLuminance : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

class _FakeImagePickerPlatform extends ImagePickerPlatform {
  _FakeImagePickerPlatform(this.bytes);

  final Uint8List bytes;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async =>
      XFile.fromData(bytes, name: 'profile.png', mimeType: 'image/png');
}

class _FakeApiService extends ApiService {
  _FakeApiService() : super(client: _UnusedHttpClient());

  final List<Map<String, dynamic>> users = [
    {
      'id': 'user-1',
      'accountNo': 'DRD000000001',
      'name': 'Morgan Member',
      'email': 'morgan@example.com',
      'role': 'Member',
    },
    {
      'id': 'user-2',
      'accountNo': 'DRD000000002',
      'name': 'Taylor Member',
      'email': 'taylor@example.com',
      'role': 'Member',
      'profileImageUrl': '',
    },
  ];
  final List<Map<String, dynamic>> collectionRequests = [];
  final List<Map<String, dynamic>> collectionActions = [];
  final List<Map<String, dynamic>> depositRequests = [];
  final List<Map<String, dynamic>> depositActions = [];
  final List<Map<String, dynamic>> depositAccounts = [];
  Completer<bool>? depositMutationCompleter;
  Object? depositFetchError;
  int depositFetchCount = 0;
  final List<Map<String, dynamic>> userRequests = [];
  final List<Map<String, dynamic>> passwordChanges = [];
  final List<Map<String, dynamic>> profileUpdates = [];
  Map<String, Map<String, bool>>? savedRolePermissions;
  final List<Map<String, dynamic>> ledgerRequests = [];
  final List<Map<String, dynamic>> ledgerActions = [];
  final List<String> fetchActions = [];
  final List<Map<String, dynamic>> ledgerEntries = [
    {
      '__rowIndex': 2,
      'byWhom': 'Office',
      'remarks': 'Opening balance',
      'date': '2026-10-17',
      'deposit': 100,
      'withdrawal': 0,
      'balance': 100,
      'payMode': 'Cash',
      'entryBy': '1 mafidul',
    },
  ];
  final Map<String, List<Map<String, dynamic>>> collections = {
    'Daily_Collection': [
      {
        'memberName': 'Jordan Member',
        'date': '2026-01-01',
        'depAmt': 25,
        'totalCount': 1,
        'totalReceived': 25,
        'grandTotal': 100,
        'periods': [true, false],
        'rowIndex': 2,
      },
    ],
    'Weekly_Collection': [],
    'Monthly_Collection': [],
  };
  bool didRegister = false;

  @override
  Future<AuthSession> login(
    String email,
    String password, {
    String loginType = 'staff',
  }) async {
    return const AuthSession(
      token: 'test-token',
      userId: 'admin-1',
      name: 'Admin',
      email: 'admin@example.com',
      role: 'Admin',
      accountNumber: 'ADM123456789',
    );
  }

  @override
  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    didRegister = true;
  }

  @override
  Future<Map<String, Map<String, bool>>> fetchRolePermissions(
    AuthSession session,
  ) async =>
      {
        for (final role in ['Collector', 'Member'])
          role: {
            'shared_data_read': role == 'Collector',
            'own_collection_read': true,
            'collection_manage': role == 'Collector',
            'deposit_view': true,
            'deposit_manage': role == 'Collector',
            'ledger_manage': role == 'Collector',
            'user_manage': role == 'Collector',
          },
      };

  @override
  Future<void> saveRolePermissions(
    Map<String, Map<String, bool>> permissions,
    AuthSession session,
  ) async {
    savedRolePermissions = {
      for (final entry in permissions.entries)
        entry.key: Map<String, bool>.from(entry.value),
    };
  }

  @override
  Future<dynamic> fetchSheetData(String action, AuthSession session) async {
    fetchActions.add(action);
    if (action == 'getUsers') return users;
    if (action == 'getAmount') return ledgerEntries;
    if (action.startsWith('get')) {
      final sheetName = '${action.substring(3)}_Collection';
      final records = collections[sheetName] ?? <Map<String, dynamic>>[];
      if (session.role.toLowerCase() == 'member') {
        return records
            .where((record) => session.matchesMemberName(record['memberName']))
            .toList();
      }
      return records;
    }
    return <dynamic>[];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchDepositAccounts({
    required String product,
    required String cadence,
    required AuthSession session,
  }) async {
    depositFetchCount++;
    if (depositFetchError != null) throw depositFetchError!;
    fetchActions.add('getDepositAccounts:$product:$cadence');
    return depositAccounts
        .where(
          (account) =>
              account['product'] == product &&
              account['cadence'] == cadence &&
              (session.role.toLowerCase() != 'member' ||
                  session.matchesMemberName(account['memberName'])),
        )
        .toList();
  }

  @override
  Future<bool> sendPostRequest(
    Map<String, dynamic> body,
    AuthSession session,
  ) async {
    if (body['action'] == 'editDepositAccount' ||
        body['action'] == 'deleteDepositAccount') {
      final completer = depositMutationCompleter;
      if (completer != null) {
        depositMutationCompleter = null;
        await completer.future;
      }
    }
    switch (body['action']) {
      case 'changePassword':
        passwordChanges.add({...body, 'token': session.token});
        return true;
      case 'updateMyProfile':
        profileUpdates.add({...body, 'token': session.token});
        return true;
      case 'addAmount':
        ledgerRequests.add(Map<String, dynamic>.from(body));
        ledgerEntries.add({
          ...body,
          '__rowIndex': ledgerEntries.length + 2,
          'date': '2026-10-18',
          'balance': body['balance'],
        });
        ledgerActions.add(Map<String, dynamic>.from(body));
        return true;
      case 'editAmount':
        final entry = ledgerEntries.firstWhere(
          (item) => item['__rowIndex'] == body['rowIndex'],
        );
        entry
          ..['date'] = body['date']
          ..['byWhom'] = body['byWhom']
          ..['remarks'] = body['remarks']
          ..['deposit'] = body['deposit']
          ..['withdrawal'] = body['withdrawal']
          ..['balance'] = body['balance']
          ..['payMode'] = body['payMode']
          ..['entryBy'] = body['entryBy'];
        ledgerActions.add(Map<String, dynamic>.from(body));
        return true;
      case 'deleteAmount':
        ledgerEntries.removeWhere(
          (item) => item['__rowIndex'] == body['rowIndex'],
        );
        ledgerActions.add(Map<String, dynamic>.from(body));
        return true;
      case 'addCollection':
        collectionRequests.add(Map<String, dynamic>.from(body));
        final periods = List<bool>.from(
          body['periods'] as List? ?? const [],
        );
        final paidCount = periods.where((paid) => paid).length;
        collections[body['sheetName']]!.add({
          ...body,
          'rowIndex': collections[body['sheetName']]!.length + 2,
          'periods': periods,
          'totalCount': paidCount,
          'totalReceived': paidCount * (body['depAmt'] as num),
        });
        collectionActions.add(Map<String, dynamic>.from(body));
        return true;
      case 'editCollection':
        final entries = collections[body['sheetName']]!;
        final entry = entries.firstWhere(
          (item) => item['rowIndex'] == body['rowIndex'],
        );
        entry
          ..['memberName'] = body['memberName']
          ..['date'] = body['date']
          ..['depAmt'] = body['depAmt'];
        collectionActions.add(Map<String, dynamic>.from(body));
        return true;
      case 'deleteCollection':
        collections[body['sheetName']]!.removeWhere(
          (item) => item['rowIndex'] == body['rowIndex'],
        );
        collectionActions.add(Map<String, dynamic>.from(body));
        return true;
      case 'addDepositAccount':
        depositRequests.add(Map<String, dynamic>.from(body));
        depositAccounts.add({
          ...body,
          'id': 'deposit-${depositAccounts.length + 1}',
          'maturityDate': DateFormat('yyyy-MM-dd').format(
            depositMaturityDate(
              DateFormat('yyyy-MM-dd').parse(body['startDate'] as String),
              body['tenureMonths'] as int,
            ),
          ),
          'maturityAmount': depositMaturityAmount(
            product: body['product'] as String,
            cadence: body['cadence'] as String,
            amount: (body['amount'] as num).toDouble(),
            annualRate: (body['annualRate'] as num).toDouble(),
            tenureMonths: body['tenureMonths'] as int,
            periodCount: (body['payments'] as List).length,
          ),
          'periodDates': body['product'] == 'FD'
              ? <String>[]
              : depositPeriodDates(
                  startDate: DateFormat('yyyy-MM-dd')
                      .parse(body['startDate'] as String),
                  maturityDate: depositMaturityDate(
                    DateFormat('yyyy-MM-dd').parse(body['startDate'] as String),
                    body['tenureMonths'] as int,
                  ),
                  cadence: body['cadence'] as String,
                ).map((date) => DateFormat('yyyy-MM-dd').format(date)).toList(),
        });
        depositActions.add(Map<String, dynamic>.from(body));
        return true;
      case 'editDepositAccount':
        depositActions.add(Map<String, dynamic>.from(body));
        final account =
            depositAccounts.firstWhere((item) => item['id'] == body['id']);
        account
          ..['memberName'] = body['memberName']
          ..['startDate'] = body['startDate']
          ..['amount'] = body['amount']
          ..['annualRate'] = body['annualRate']
          ..['tenureMonths'] = body['tenureMonths'];
        final startDate =
            DateFormat('yyyy-MM-dd').parse(body['startDate'] as String);
        final maturityDate = depositMaturityDate(
          startDate,
          body['tenureMonths'] as int,
        );
        final periodDates = body['product'] == 'FD'
            ? <DateTime>[]
            : depositPeriodDates(
                startDate: startDate,
                maturityDate: maturityDate,
                cadence: body['cadence'] as String,
              );
        account
          ..['maturityDate'] = DateFormat('yyyy-MM-dd').format(maturityDate)
          ..['periodDates'] = periodDates
              .map((date) => DateFormat('yyyy-MM-dd').format(date))
              .toList()
          ..['maturityAmount'] = depositMaturityAmount(
            product: body['product'] as String,
            cadence: body['cadence'] as String,
            amount: (body['amount'] as num).toDouble(),
            annualRate: (body['annualRate'] as num).toDouble(),
            tenureMonths: body['tenureMonths'] as int,
            periodCount: periodDates.length,
          );
        return true;
      case 'toggleDepositPayment':
        depositActions.add(Map<String, dynamic>.from(body));
        final account =
            depositAccounts.firstWhere((item) => item['id'] == body['id']);
        final payments = account['payments'] as List<dynamic>;
        final index = (body['periodIndex'] as int) - 1;
        payments[index] = !(payments[index] == true);
        return true;
      case 'deleteDepositAccount':
        depositActions.add(Map<String, dynamic>.from(body));
        depositAccounts.removeWhere((item) => item['id'] == body['id']);
        return true;
      case 'addUser':
        userRequests.add(Map<String, dynamic>.from(body));
        users.add({
          'id': 'user-${users.length + 1}',
          'name': body['name'],
          'profileImageUrl': body['profileImageData'] == null
              ? ''
              : 'data:${body['profileImageMimeType']};base64,${body['profileImageData']}',
          'email': body['email'],
          'role': body['role'],
          'dailyAccess': body['dailyAccess'] ?? true,
          'weeklyAccess': body['weeklyAccess'] ?? true,
          'monthlyAccess': body['monthlyAccess'] ?? true,
        });
        return true;
      case 'editUser':
        userRequests.add(Map<String, dynamic>.from(body));
        final user = users.firstWhere((item) => item['id'] == body['userId']);
        user
          ..['name'] = body['name']
          ..['email'] = body['email']
          ..['profileImageUrl'] = body['profileImageChanged'] == true
              ? body['profileImageData'] == null
                  ? ''
                  : 'data:${body['profileImageMimeType']};base64,${body['profileImageData']}'
              : user['profileImageUrl'] ?? ''
          ..['role'] = body['role']
          ..['dailyAccess'] = body['dailyAccess'] ?? user['dailyAccess'] ?? true
          ..['weeklyAccess'] =
              body['weeklyAccess'] ?? user['weeklyAccess'] ?? true
          ..['monthlyAccess'] =
              body['monthlyAccess'] ?? user['monthlyAccess'] ?? true;
        return true;
      case 'deleteUser':
        users.removeWhere((item) => item['id'] == body['userId']);
        return true;
      default:
        return true;
    }
  }
}

class _PendingRegisterApiService extends _FakeApiService {
  final completion = Completer<void>();

  @override
  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) =>
      completion.future;
}

class _DashboardFailingApiService extends _FakeApiService {
  @override
  Future<dynamic> fetchSheetData(String action, AuthSession session) async {
    if (action == 'getWeekly') {
      fetchActions.add(action);
      throw const ApiException('Weekly sheet is unavailable.');
    }
    return super.fetchSheetData(action, session);
  }
}

class _DashboardFailingRolePermissionsApiService extends _FakeApiService {
  @override
  Future<Map<String, Map<String, bool>>> fetchRolePermissions(
    AuthSession session,
  ) async {
    throw const ApiException('Role permissions are offline.');
  }
}

class _UnusedHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnimplementedError('Network calls are replaced by the test service.');
  }
}

class _RecordingHttpClient extends http.BaseClient {
  _RecordingHttpClient(this.responses);

  final List<dynamic> responses;
  final List<Map<String, dynamic>> payloads = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = (request as http.Request).body;
    payloads.add(jsonDecode(body) as Map<String, dynamic>);
    final response = jsonEncode(responses.removeAt(0));
    return http.StreamedResponse(
      Stream.value(utf8.encode(response)),
      200,
      request: request,
    );
  }
}

class _RecordingTextHttpClient extends http.BaseClient {
  _RecordingTextHttpClient(this.responseBody);

  final String responseBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(utf8.encode(responseBody)),
      200,
      request: request,
    );
  }
}
