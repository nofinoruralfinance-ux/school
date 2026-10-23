import 'dart:async';

import 'package:flutter/material.dart';

import 'pages/collection_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/deposit_account_page.dart';
import 'pages/ledger_page.dart';
import 'pages/login_page.dart';
import 'pages/profile_page.dart';
import 'pages/roles_permissions_page.dart';
import 'pages/splash_page.dart';
import 'pages/users_page.dart';
import 'services/api_service.dart';
import 'widgets/portal_widgets.dart';

const _depositRoutes = <String, int>{
  'fd-monthly': 7,
  'rd-weekly': 8,
  'rd-monthly': 9,
  'drd-daily': 10,
  'drd-weekly': 11,
  'drd-monthly': 12,
};

void main() => runApp(NtccslAccountApp(showSplashScreen: true));

String _themeModeLabel(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.system:
      return 'System default';
    case ThemeMode.light:
      return 'Light';
    case ThemeMode.dark:
      return 'Dark';
  }
}

IconData _themeModeIcon(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.system:
      return Icons.settings_brightness_rounded;
    case ThemeMode.light:
      return Icons.light_mode_rounded;
    case ThemeMode.dark:
      return Icons.dark_mode_rounded;
  }
}

class NtccslAccountApp extends StatefulWidget {
  NtccslAccountApp({
    super.key,
    ApiService? apiService,
    this.showSplashScreen = false,
  }) : apiService = apiService ?? ApiService();

  final ApiService apiService;
  final bool showSplashScreen;

  @override
  State<NtccslAccountApp> createState() => _NtccslAccountAppState();
}

class _NtccslAccountAppState extends State<NtccslAccountApp> {
  AuthSession? _session;
  ThemeMode _themeMode = ThemeMode.system;
  late bool _showSplashScreen;
  Timer? _splashTimer;

  @override
  void initState() {
    super.initState();
    _showSplashScreen = widget.showSplashScreen;
    if (_showSplashScreen) {
      _splashTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _showSplashScreen = false);
      });
    }
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NTCCSL FINANCE SYSTEM',
      debugShowCheckedModeBanner: false,
      theme: _portalTheme(Brightness.light),
      darkTheme: _portalTheme(Brightness.dark),
      themeMode: _themeMode,
      home: _showSplashScreen
          ? const SplashPage()
          : _session == null
              ? LoginPage(
                  apiService: widget.apiService,
                  onLoggedIn: (session) => setState(() => _session = session),
                )
              : MainHomeScreen(
                  apiService: widget.apiService,
                  session: _session!,
                  onSessionUpdated: (session) =>
                      setState(() => _session = session),
                  themeMode: _themeMode,
                  onThemeModeChanged: (mode) => setState(() {
                    _themeMode = mode;
                  }),
                  onLogout: () => setState(() => _session = null),
                ),
    );
  }
}

ThemeData _portalTheme(Brightness brightness) {
  final isLight = brightness == Brightness.light;
  const darkAppBarBackground = Color(0xFF253B8C);
  final colorScheme = ColorScheme.fromSeed(
    seedColor: isLight ? const Color(0xFF3458D4) : const Color(0xFF9EB4FF),
    brightness: brightness,
    surface: isLight ? Colors.white : const Color(0xFF191B23),
  );
  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor:
        isLight ? const Color(0xFFF5F7FB) : const Color(0xFF11131A),
    visualDensity: VisualDensity.standard,
    iconTheme: IconThemeData(color: colorScheme.tertiary),
    primaryIconTheme: IconThemeData(color: colorScheme.onPrimary),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: colorScheme.secondary,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      prefixIconColor: colorScheme.primary,
      suffixIconColor: colorScheme.tertiary,
      filled: true,
      fillColor: colorScheme.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colorScheme.error),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: colorScheme.surface,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: .55)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 76,
      backgroundColor: colorScheme.surface,
      indicatorColor: colorScheme.primaryContainer,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        return IconThemeData(
          color: states.contains(WidgetState.selected)
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return TextStyle(
          color: states.contains(WidgetState.selected)
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
        );
      }),
      elevation: 8,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: isLight ? colorScheme.primary : darkAppBarBackground,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({
    super.key,
    required this.apiService,
    required this.session,
    this.onSessionUpdated,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    required this.onLogout,
  });

  final ApiService apiService;
  final AuthSession session;
  final ValueChanged<AuthSession>? onSessionUpdated;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final VoidCallback onLogout;

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _selectedIndex = 0;
  int _refreshVersion = 0;
  final Set<int> _visitedPages = {0};

  bool get _isAdmin => widget.session.role.toLowerCase() == 'admin';
  bool get _canViewLedger =>
      widget.session.hasPermission('shared_data_read') ||
      widget.session.hasPermission('ledger_manage');
  bool get _canViewCollections =>
      widget.session.hasPermission('shared_data_read') ||
      widget.session.hasPermission('own_collection_read') ||
      widget.session.hasPermission('collection_manage');
  bool get _canViewUsers =>
      widget.session.hasPermission('shared_data_read') ||
      widget.session.hasPermission('user_manage');
  bool get _canViewDepositAccounts =>
      widget.session.hasPermission('deposit_view') ||
      widget.session.hasPermission('deposit_manage');

  List<int> get _visiblePageIndices => [
        0,
        if (_canViewLedger) 1,
        if (_canViewCollections && widget.session.canViewReport('daily')) 2,
        if (_canViewCollections && widget.session.canViewReport('weekly')) 3,
        if (_canViewCollections && widget.session.canViewReport('monthly')) 4,
        if (_canViewDepositAccounts && widget.session.canViewReport('monthly'))
          7,
        if (_canViewDepositAccounts && widget.session.canViewReport('weekly'))
          8,
        if (_canViewDepositAccounts && widget.session.canViewReport('monthly'))
          9,
        if (_canViewDepositAccounts && widget.session.canViewReport('daily'))
          10,
        if (_canViewDepositAccounts && widget.session.canViewReport('weekly'))
          11,
        if (_canViewDepositAccounts && widget.session.canViewReport('monthly'))
          12,
        if (_canViewUsers) 5,
        if (_isAdmin) 6,
      ];
  List<int> get _bottomNavigationPageIndices => _visiblePageIndices
      .where((index) => index != 1 && index != 6 && index < 7)
      .toList();

  static const _navigationLabels = [
    'Dashboard',
    'Accounts',
    'Daily',
    'Weekly',
    'Monthly',
    'Users',
    'Roles & Permissions',
  ];

  void _selectPage(int index) {
    if (!_visiblePageIndices.contains(index)) return;
    setState(() {
      _selectedIndex = index;
      _visitedPages.add(index);
    });
  }

  void _selectBottomNavigationPage(int destinationIndex) {
    _selectPage(_bottomNavigationPageIndices[destinationIndex]);
  }

  Widget _navigationMenuTile(BuildContext context, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        key: Key('navigation-menu-${_navigationLabels[index].toLowerCase()}'),
        selected: _selectedIndex == index,
        selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: _navigationColors[index].withValues(alpha: .12),
          child: Icon(
            _navigationIcons[index],
            color: _navigationColors[index],
            size: 20,
          ),
        ),
        title: Text(_navigationLabels[index]),
        onTap: () {
          _selectPage(index);
          Navigator.of(context).pop();
        },
      ),
    );
  }

  Widget _depositRouteTile(
    BuildContext context,
    String product,
    String cadence,
  ) {
    final index = _depositRoutes['${product.toLowerCase()}-$cadence']!;
    if (!_visiblePageIndices.contains(index)) return const SizedBox.shrink();
    final color = _depositProductColor(product);
    return ListTile(
      key: Key('navigation-menu-${product.toLowerCase()}-$cadence'),
      selected: _selectedIndex == index,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withValues(alpha: .12),
        child: Icon(
          _depositCadenceIcon(cadence),
          color: color,
          size: 18,
        ),
      ),
      title: Text(cadence[0].toUpperCase() + cadence.substring(1)),
      onTap: () {
        _selectPage(index);
        Navigator.of(context).pop();
      },
    );
  }

  Color _depositProductColor(String product) => switch (product) {
        'FD' => const Color(0xFF3458D4),
        'RD' => const Color(0xFF8E24AA),
        _ => const Color(0xFF078A6A),
      };

  IconData _depositProductIcon(String product) => switch (product) {
        'FD' => Icons.savings_outlined,
        'RD' => Icons.event_repeat_rounded,
        _ => Icons.calendar_month_rounded,
      };

  IconData _depositCadenceIcon(String cadence) => switch (cadence) {
        'daily' => Icons.today_rounded,
        'weekly' => Icons.calendar_view_week_rounded,
        _ => Icons.calendar_month_rounded,
      };

  Widget _depositProductGroup(BuildContext context, String product) {
    final cadences = switch (product) {
      'FD' => const ['monthly'],
      'RD' => const ['weekly', 'monthly'],
      _ => const ['daily', 'weekly', 'monthly'],
    };
    final visibleCadences = cadences.where(
      (cadence) => _visiblePageIndices
          .contains(_depositRoutes['${product.toLowerCase()}-$cadence']),
    );
    if (visibleCadences.isEmpty) return const SizedBox.shrink();
    final color = _depositProductColor(product);
    return ExpansionTile(
      key: Key('navigation-menu-product-${product.toLowerCase()}'),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withValues(alpha: .12),
        child: Icon(
          _depositProductIcon(product),
          color: color,
          size: 18,
        ),
      ),
      title: Text(product),
      children: [
        for (final cadence in visibleCadences)
          _depositRouteTile(context, product, cadence),
      ],
    );
  }

  void _logout() {
    showPortalToast(context, 'Signed out successfully.');
    widget.onLogout();
  }

  Future<void> _selectThemeMode() async {
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        key: const Key('theme-mode-dialog'),
        title: const Text('Appearance'),
        children: [
          for (final option in ThemeMode.values)
            SimpleDialogOption(
              key: Key('theme-mode-${option.name}'),
              onPressed: () => Navigator.of(dialogContext).pop(option),
              child: Row(
                children: [
                  Icon(_themeModeIcon(option)),
                  const SizedBox(width: 16),
                  Expanded(child: Text(_themeModeLabel(option))),
                  if (widget.themeMode == option)
                    Icon(
                      Icons.check_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected != null) widget.onThemeModeChanged?.call(selected);
  }

  static const _navigationIcons = [
    Icons.dashboard_outlined,
    Icons.account_balance_wallet_outlined,
    Icons.today_outlined,
    Icons.calendar_view_week_outlined,
    Icons.calendar_month_outlined,
    Icons.people_outline,
    Icons.admin_panel_settings_outlined,
  ];

  static const _navigationSelectedIcons = [
    Icons.dashboard_rounded,
    Icons.account_balance_wallet_rounded,
    Icons.today,
    Icons.calendar_view_week,
    Icons.calendar_month,
    Icons.people,
    Icons.admin_panel_settings_rounded,
  ];

  static const _navigationColors = [
    Color(0xFF7C4DFF),
    Color(0xFF3458D4),
    Color(0xFF00897B),
    Color(0xFF8E24AA),
    Color(0xFFEF6C00),
    Color(0xFF039BE5),
    Color(0xFFB45309),
  ];

  static const _titles = [
    'Dashboard',
    'Amounts Ledger',
    'Daily Collection',
    'Weekly Collection',
    'Monthly Collection',
    'Users List',
    'Roles & Permissions',
    'FD Monthly',
    'RD Weekly',
    'RD Monthly',
    'DRD Daily',
    'DRD Weekly',
    'DRD Monthly',
  ];

  List<Widget> get _pages => [
        DashboardPage(
          key: ValueKey('dashboard-$_refreshVersion'),
          apiService: widget.apiService,
          session: widget.session,
          onNavigate: _selectPage,
        ),
        LedgerPage(
          key: ValueKey('ledger-$_refreshVersion'),
          apiService: widget.apiService,
          session: widget.session,
        ),
        CollectionPage(
          key: ValueKey('daily-$_refreshVersion'),
          apiService: widget.apiService,
          session: widget.session,
          type: 'Daily',
          sheetName: 'Daily_Collection',
          periodsCount: 365,
        ),
        CollectionPage(
          key: ValueKey('weekly-$_refreshVersion'),
          apiService: widget.apiService,
          session: widget.session,
          type: 'Weekly',
          sheetName: 'Weekly_Collection',
          periodsCount: 52,
        ),
        CollectionPage(
          key: ValueKey('monthly-$_refreshVersion'),
          apiService: widget.apiService,
          session: widget.session,
          type: 'Monthly',
          sheetName: 'Monthly_Collection',
          periodsCount: 12,
        ),
        UsersPage(
          key: ValueKey('users-$_refreshVersion'),
          apiService: widget.apiService,
          session: widget.session,
        ),
        RolesPermissionsPage(
          key: ValueKey('roles-permissions-$_refreshVersion'),
          apiService: widget.apiService,
          session: widget.session,
        ),
        for (final route in [
          ('FD', 'monthly'),
          ('RD', 'weekly'),
          ('RD', 'monthly'),
          ('DRD', 'daily'),
          ('DRD', 'weekly'),
          ('DRD', 'monthly'),
        ])
          DepositAccountPage(
            key: ValueKey(
              'deposit-${route.$1.toLowerCase()}-${route.$2}-$_refreshVersion',
            ),
            apiService: widget.apiService,
            session: widget.session,
            product: route.$1,
            cadence: route.$2,
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    final headerGradient = portalHeaderGradient(context);
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: headerGradient,
            ),
          ),
        ),
        leading: Builder(
          builder: (context) => IconButton(
            key: const Key('open-navigation-menu'),
            tooltip: 'Open navigation menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
            icon: const Icon(Icons.menu_rounded),
          ),
        ),
        title: Text(
          _titles[_selectedIndex],
        ),
        titleSpacing: 12,
        actions: [
          IconButton(
            tooltip: 'Reload page data',
            onPressed: () => setState(() => _refreshVersion++),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: .18),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
          IconButton(
            key: const Key('open-profile'),
            tooltip: 'My profile',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ProfilePage(
                    apiService: widget.apiService,
                    session: widget.session,
                    onSessionUpdated: widget.onSessionUpdated,
                  ),
                ),
              );
            },
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: .18),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.account_circle_outlined),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Sign out',
            onPressed: _logout,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: .18),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 12),
        ],
      ),
      drawer: Drawer(
        width: MediaQuery.sizeOf(context).width * .82,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 20),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: headerGradient,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          'assets/images/ntccsl_logo.png',
                          key: const Key('ntccsl-app-icon'),
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'NTCCSL FINANCE SYSTEM',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.session.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              widget.session.role,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: .82),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const Key('close-navigation-menu'),
                        tooltip: 'Close navigation menu',
                        onPressed: () => Navigator.of(context).pop(),
                        color: Colors.white,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'NAVIGATION',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final index in _visiblePageIndices)
                      if (index < 2) _navigationMenuTile(context, index),
                    if (_visiblePageIndices.any((index) => index >= 7))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: ExpansionTile(
                          key: const Key('navigation-menu-deposit'),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          collapsedShape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor:
                                const Color(0xFF00897B).withValues(alpha: .12),
                            child: const Icon(
                              Icons.savings_outlined,
                              color: Color(0xFF00897B),
                              size: 20,
                            ),
                          ),
                          title: const Text('Deposit'),
                          childrenPadding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          children: [
                            _depositProductGroup(context, 'FD'),
                            _depositProductGroup(context, 'RD'),
                            _depositProductGroup(context, 'DRD'),
                          ],
                        ),
                      ),
                    if (_visiblePageIndices.any(
                      (index) => index >= 2 && index <= 4,
                    ))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: ExpansionTile(
                          key: const Key(
                            'navigation-menu-existing-collections',
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          collapsedShape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor:
                                const Color(0xFF00897B).withValues(alpha: .12),
                            child: const Icon(
                              Icons.collections_bookmark_outlined,
                              color: Color(0xFF00897B),
                              size: 20,
                            ),
                          ),
                          title: const Text('D/W/M Collection'),
                          children: [
                            for (final index in _visiblePageIndices)
                              if (index >= 2 && index <= 4)
                                _navigationMenuTile(context, index),
                          ],
                        ),
                      ),
                    for (final index in _visiblePageIndices)
                      if (index == 5 || index == 6)
                        _navigationMenuTile(context, index),
                  ],
                ),
              ),
              ListTile(
                key: const Key('open-theme-mode'),
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Appearance'),
                subtitle: Text(_themeModeLabel(widget.themeMode)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _selectThemeMode,
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: ListTile(
                  key: const Key('navigation-menu-logout'),
                  leading: const Icon(Icons.logout_rounded),
                  title: const Text('Sign out'),
                  textColor: Theme.of(context).colorScheme.error,
                  iconColor: Theme.of(context).colorScheme.error,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  onTap: _logout,
                ),
              ),
            ],
          ),
        ),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          for (var index = 0; index < _titles.length; index++)
            if (_visitedPages.contains(index))
              pages[index]
            else
              const SizedBox(),
        ],
      ),
      bottomNavigationBar: _bottomNavigationPageIndices.length < 2
          ? null
          : NavigationBar(
              selectedIndex: _bottomNavigationPageIndices
                  .indexOf(_selectedIndex)
                  .clamp(0, _bottomNavigationPageIndices.length - 1),
              onDestinationSelected: _selectBottomNavigationPage,
              destinations: [
                for (final index in _bottomNavigationPageIndices)
                  NavigationDestination(
                    icon: Icon(
                      _navigationIcons[index],
                      color: _navigationColors[index],
                    ),
                    selectedIcon: Icon(
                      _navigationSelectedIcons[index],
                      color: _navigationColors[index],
                    ),
                    label: _navigationLabels[index],
                  ),
              ],
            ),
    );
  }
}
