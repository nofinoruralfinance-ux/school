import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../widgets/portal_loading.dart';
import '../widgets/portal_widgets.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.apiService,
    required this.session,
    required this.onNavigate,
  });

  final ApiService apiService;
  final AuthSession session;
  final ValueChanged<int> onNavigate;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<_DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _fetchData();
  }

  bool get _isMember => widget.session.role.toLowerCase() == 'member';

  Future<_DashboardData> _fetchData() async {
    final canReadLedger = !_isMember &&
        (widget.session.hasPermission('shared_data_read') ||
            widget.session.hasPermission('ledger_manage'));
    final canReadCollections =
        widget.session.hasPermission('shared_data_read') ||
            widget.session.hasPermission('own_collection_read') ||
            widget.session.hasPermission('collection_manage');
    final canReadUsers = !_isMember &&
        (widget.session.hasPermission('shared_data_read') ||
            widget.session.hasPermission('user_manage'));
    final canReadDepositAccounts =
        widget.session.hasPermission('deposit_view') ||
            widget.session.hasPermission('deposit_manage');
    final canReadRolePermissions =
        canReadUsers && widget.session.role.toLowerCase() == 'admin';
    const depositReports = <(String, String, int)>[
      ('FD', 'monthly', 7),
      ('RD', 'weekly', 8),
      ('RD', 'monthly', 9),
      ('DRD', 'daily', 10),
      ('DRD', 'weekly', 11),
      ('DRD', 'monthly', 12),
    ];
    final availableDepositReports = canReadDepositAccounts
        ? depositReports
            .where((report) => widget.session.canViewReport(report.$2))
            .toList()
        : const <(String, String, int)>[];

    final roleAccessFuture = canReadRolePermissions
        ? _loadRolePermissions()
        : Future.value(
            _RoleAccessData(
              error: canReadUsers
                  ? 'Only Admins can view permissions for other roles.'
                  : null,
            ),
          );
    final results = await Future.wait([
      canReadLedger
          ? _loadRecords('getAmount', 'Ledger')
          : Future.value(const _DashboardRecords(label: 'Ledger')),
      canReadCollections && widget.session.canViewReport('daily')
          ? _loadRecords('getDaily', 'Daily collection')
          : Future.value(const _DashboardRecords(label: 'Daily collection')),
      canReadCollections && widget.session.canViewReport('weekly')
          ? _loadRecords('getWeekly', 'Weekly collection')
          : Future.value(const _DashboardRecords(label: 'Weekly collection')),
      canReadCollections && widget.session.canViewReport('monthly')
          ? _loadRecords('getMonthly', 'Monthly collection')
          : Future.value(const _DashboardRecords(label: 'Monthly collection')),
      canReadUsers
          ? _loadRecords('getUsers', 'Users')
          : Future.value(const _DashboardRecords(label: 'Users')),
    ]);
    final depositResults = await Future.wait(
      availableDepositReports.map(
        (report) => _loadDepositRecords(report.$1, report.$2),
      ),
    );
    final roleAccess = await roleAccessFuture;
    return _DashboardData(
      ledger: results[0],
      daily: results[1],
      weekly: results[2],
      monthly: results[3],
      users: results[4],
      deposits: [
        for (var index = 0; index < availableDepositReports.length; index++)
          _DashboardDepositReport(
            product: availableDepositReports[index].$1,
            cadence: availableDepositReports[index].$2,
            pageIndex: availableDepositReports[index].$3,
            result: depositResults[index],
          ),
      ],
      rolePermissions: roleAccess.permissions,
      rolePermissionsError: roleAccess.error,
    );
  }

  Future<_DashboardRecords> _loadDepositRecords(
    String product,
    String cadence,
  ) async {
    final label = '$product ${cadence[0].toUpperCase()}${cadence.substring(1)}';
    try {
      final records = await widget.apiService.fetchDepositAccounts(
        product: product,
        cadence: cadence,
        session: widget.session,
      );
      return _DashboardRecords(label: label, records: records);
    } catch (error) {
      return _DashboardRecords(label: label, error: error.toString());
    }
  }

  Future<_RoleAccessData> _loadRolePermissions() async {
    try {
      final permissions =
          await widget.apiService.fetchRolePermissions(widget.session);
      return _RoleAccessData(
        permissions: {
          for (final entry in permissions.entries)
            entry.key.toLowerCase(): entry.value,
        },
      );
    } on ApiException catch (error) {
      return _RoleAccessData(error: error.toString());
    }
  }

  Future<_DashboardRecords> _loadRecords(String action, String label) async {
    try {
      final value =
          await widget.apiService.fetchSheetData(action, widget.session);
      if (value is! List) {
        throw FormatException('The server returned invalid data for $action.');
      }
      return _DashboardRecords(
        label: label,
        records: value.whereType<Map>().where((record) {
          final isCollectionAction = action == 'getDaily' ||
              action == 'getWeekly' ||
              action == 'getMonthly';
          return !isCollectionAction ||
              widget.session.role.toLowerCase() != 'member' ||
              widget.session.matchesMemberName(record['memberName']);
        }).map<Map<String, dynamic>>((record) {
          return Map<String, dynamic>.from(record);
        }).toList(),
      );
    } catch (error) {
      return _DashboardRecords(label: label, error: error.toString());
    }
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return PortalGradientBackground(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: FutureBuilder<_DashboardData>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const PortalLoadingState(label: 'Loading dashboard');
              }
              if (!snapshot.hasData) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Unable to load dashboard data.',
                          key: Key('dashboard-error'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          key: const Key('dashboard-retry'),
                          onPressed: () => setState(_load),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final data = snapshot.data!;
              if (_isMember) return _buildMemberDashboard(data);

              final totalDeposits = data.ledger.error == null
                  ? _currency(_sum(data.ledger.records, 'deposit'))
                  : 'Unavailable';
              final totalWithdrawals = data.ledger.error == null
                  ? _currency(_sum(data.ledger.records, 'withdrawal'))
                  : 'Unavailable';
              final netBalance = data.ledger.records.isEmpty
                  ? 0
                  : _number(data.ledger.records.last['balance']);
              final collectionTotal = data.daily.error == null &&
                      data.weekly.error == null &&
                      data.monthly.error == null
                  ? _currency(
                      data.daily.received +
                          data.weekly.received +
                          data.monthly.received,
                    )
                  : 'Unavailable';
              final memberCount = {
                for (final item in [
                  ...data.daily.records,
                  ...data.weekly.records,
                  ...data.monthly.records
                ])
                  if ((item['memberName'] ?? '').toString().trim().isNotEmpty)
                    '${item['memberName']}'.trim().toLowerCase(),
              }.length;
              final failures = data.sources
                  .where((source) => source.error != null)
                  .toList(growable: false);
              final availableDeposits = data.deposits;

              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                  children: [
                    _DashboardHero(
                      name: widget.session.name,
                      title: 'Dashboard',
                      subtitle:
                          'Your finances, collections, and activity at a glance.',
                    ),
                    if (failures.isNotEmpty) ...[
                      Card(
                        key: const Key('dashboard-partial-error'),
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Some dashboard data could not be loaded.',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 6),
                              for (final source in failures)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child:
                                      Text('${source.label}: ${source.error}'),
                                ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  key: const Key('dashboard-retry'),
                                  onPressed: () => setState(_load),
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Retry all'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    _metricGrid(context, [
                      PortalMetricCard(
                        label: 'Ledger balance',
                        value: data.ledger.error == null
                            ? _currency(netBalance)
                            : 'Unavailable',
                        icon: Icons.account_balance_wallet_rounded,
                        accent: const Color(0xFF3458D4),
                      ),
                      PortalMetricCard(
                        label: 'Collections received',
                        value: collectionTotal,
                        icon: Icons.currency_rupee_rounded,
                        accent: const Color(0xFF078A6A),
                      ),
                      PortalMetricCard(
                        label: 'Deposits',
                        value: totalDeposits,
                        icon: Icons.south_west_rounded,
                        accent: const Color(0xFF078A6A),
                      ),
                      PortalMetricCard(
                        label: 'Withdrawals',
                        value: totalWithdrawals,
                        icon: Icons.north_east_rounded,
                        accent: const Color(0xFFD25858),
                      ),
                      PortalMetricCard(
                        label: 'Members',
                        value: data.daily.error == null &&
                                data.weekly.error == null &&
                                data.monthly.error == null
                            ? '$memberCount'
                            : 'Unavailable',
                        icon: Icons.groups_rounded,
                        accent: const Color(0xFF8E24AA),
                      ),
                      PortalMetricCard(
                        label: 'User accounts',
                        value: data.users.error == null
                            ? '${data.users.records.length}'
                            : 'Unavailable',
                        icon: Icons.people_alt_rounded,
                        accent: const Color(0xFF039BE5),
                      ),
                    ]),
                    const SizedBox(height: 24),
                    const _SectionTitle(
                      title: 'Collections',
                      trailing: 'Received across all periods',
                    ),
                    const SizedBox(height: 10),
                    _CollectionSummaryCard(
                      title: 'Daily collection',
                      icon: Icons.today_rounded,
                      color: const Color(0xFF3458D4),
                      result: data.daily,
                      onOpen: () => widget.onNavigate(2),
                    ),
                    _CollectionSummaryCard(
                      title: 'Weekly collection',
                      icon: Icons.calendar_view_week_rounded,
                      color: const Color(0xFF8A4FD0),
                      result: data.weekly,
                      onOpen: () => widget.onNavigate(3),
                    ),
                    _CollectionSummaryCard(
                      title: 'Monthly collection',
                      icon: Icons.calendar_month_rounded,
                      color: const Color(0xFF078A6A),
                      result: data.monthly,
                      onOpen: () => widget.onNavigate(4),
                    ),
                    if (availableDeposits.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const _SectionTitle(
                        title: 'Deposit accounts',
                        trailing: 'Estimated maturity value',
                      ),
                      const SizedBox(height: 10),
                      for (final report in availableDeposits)
                        _DepositSummaryCard(
                          report: report,
                          onOpen: () => widget.onNavigate(report.pageIndex),
                        ),
                    ],
                    const SizedBox(height: 12),
                    _SectionTitle(
                      title: 'Recent ledger activity',
                      trailing: data.ledger.error == null
                          ? '${data.ledger.records.length} records'
                          : 'Unavailable',
                    ),
                    const SizedBox(height: 10),
                    if (data.ledger.error != null)
                      _SourceErrorCard(
                        source: 'Ledger',
                        message: data.ledger.error!,
                      )
                    else if (data.ledger.records.isEmpty)
                      const Card(
                        child: ListTile(
                          leading: Icon(Icons.receipt_long_outlined),
                          title: Text('No ledger activity yet'),
                        ),
                      )
                    else
                      ...data.ledger.records.reversed.take(5).map((entry) {
                        final deposit = _number(entry['deposit']);
                        final withdrawal = _number(entry['withdrawal']);
                        final isDeposit = deposit > 0 || withdrawal == 0;
                        final amount = isDeposit ? deposit : withdrawal;
                        final color = isDeposit
                            ? const Color(0xFF078A6A)
                            : const Color(0xFFD25858);
                        final amountColor = isDeposit
                            ? Theme.of(context).colorScheme.tertiary
                            : Theme.of(context).colorScheme.error;
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: color.withValues(alpha: .12),
                              foregroundColor: color,
                              child: Icon(
                                isDeposit
                                    ? Icons.south_west_rounded
                                    : Icons.north_east_rounded,
                              ),
                            ),
                            title: Text(
                              (entry['byWhom'] ?? '').toString().isEmpty
                                  ? 'General account'
                                  : entry['byWhom'].toString(),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              '${entry['date'] ?? '-'} · ${entry['remarks'] ?? '-'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              '${isDeposit ? '+' : '-'}${_currency(amount)}',
                              style: TextStyle(
                                color: amountColor,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const Key('dashboard-open-ledger'),
                      onPressed: () => widget.onNavigate(1),
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Open full ledger'),
                    ),
                    const SizedBox(height: 20),
                    _SectionTitle(
                      title: 'Registered accounts',
                      trailing: data.users.error == null
                          ? '${data.users.records.length} accounts'
                          : 'Unavailable',
                    ),
                    const SizedBox(height: 10),
                    _RegisteredAccountsPanel(
                      users: data.users.records,
                      error: data.users.error,
                      rolePermissions: data.rolePermissions,
                      rolePermissionsError: data.rolePermissionsError,
                      currentRole: widget.session.role,
                      currentPermissions: widget.session.permissions,
                      onOpen: () => widget.onNavigate(5),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _metricGrid(BuildContext context, List<Widget> cards) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const columns = 3;
        final cardWidth = (constraints.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            for (final card in cards) SizedBox(width: cardWidth, child: card),
          ],
        );
      },
    );
  }

  Widget _buildMemberDashboard(_DashboardData data) {
    final collectionReports =
        <(String, String, IconData, Color, _DashboardRecords, int)>[
      (
        'daily',
        'Daily collection',
        Icons.today_rounded,
        const Color(0xFF3458D4),
        data.daily,
        2,
      ),
      (
        'weekly',
        'Weekly collection',
        Icons.calendar_view_week_rounded,
        const Color(0xFF8A4FD0),
        data.weekly,
        3,
      ),
      (
        'monthly',
        'Monthly collection',
        Icons.calendar_month_rounded,
        const Color(0xFF078A6A),
        data.monthly,
        4,
      ),
    ].where((report) => widget.session.canViewReport(report.$1)).toList();
    final collectionResults =
        collectionReports.map((report) => report.$5).toList();
    final totalReceived = collectionReports.isEmpty
        ? _currency(0)
        : collectionResults.any((result) => result.error != null)
            ? 'Unavailable'
            : _currency(
                collectionResults.fold<num>(
                  0,
                  (total, result) => total + result.received,
                ),
              );
    final depositReports = data.deposits;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        children: [
          _DashboardHero(
            name: widget.session.name,
            title: 'My dashboard',
            subtitle: 'Personal reports for ${widget.session.name}.',
          ),
          PortalMetricCard(
            label: 'My total contributions',
            value: totalReceived,
            icon: Icons.currency_rupee_rounded,
            accent: const Color(0xFF078A6A),
          ),
          const SizedBox(height: 24),
          const _SectionTitle(
            title: 'My collections',
            trailing: 'Name-matched reports',
          ),
          const SizedBox(height: 10),
          if (collectionReports.isEmpty)
            const PortalEmptyState(
              title: 'No active reports',
              subtitle:
                  'Ask an administrator to activate Daily, Weekly, or Monthly access.',
              icon: Icons.lock_outline_rounded,
            )
          else
            for (final report in collectionReports) ...[
              _CollectionSummaryCard(
                title: report.$2,
                icon: report.$3,
                color: report.$4,
                result: report.$5,
                onOpen: () => widget.onNavigate(report.$6),
                memberView: true,
              ),
              _MemberReportDetails(result: report.$5),
            ],
          if (depositReports.isNotEmpty) ...[
            const SizedBox(height: 16),
            const _SectionTitle(
              title: 'My deposit accounts',
              trailing: 'Estimated maturity value',
            ),
            const SizedBox(height: 10),
            for (final report in depositReports)
              _DepositSummaryCard(
                report: report,
                onOpen: () => widget.onNavigate(report.pageIndex),
                memberView: true,
              ),
          ],
        ],
      ),
    );
  }
}

class _DashboardHero extends StatelessWidget {
  const _DashboardHero({
    required this.name,
    required this.title,
    required this.subtitle,
  });

  final String name;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final displayName = name.trim().isEmpty ? 'there' : name.trim();
    final compact = MediaQuery.sizeOf(context).width < 380;
    final horizontalInset = compact ? 12.0 : 16.0;
    final contentInset = compact ? 16.0 : 20.0;
    final sectionGap = compact ? 14.0 : 20.0;
    final now = DateTime.now();
    final greeting = switch (now.hour) {
      < 12 => 'Good morning',
      < 17 => 'Good afternoon',
      _ => 'Good evening',
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalInset,
        compact ? 8 : 12,
        horizontalInset,
        compact ? 12 : 16,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: portalHeaderGradient(context),
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -46,
                right: -24,
                child: IgnorePointer(
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: .07),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(contentInset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .16),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .20),
                            ),
                          ),
                          child: const Icon(
                            Icons.account_balance_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'NTCCSL FINANCE SYSTEM',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: .88),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.1,
                                ),
                          ),
                        ),
                        if (!compact) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.auto_graph_rounded,
                            color: Colors.white.withValues(alpha: .72),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: sectionGap),
                    Text(
                      '$greeting, $displayName',
                      key: const Key('dashboard-greeting'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Colors.white.withValues(alpha: .78),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.4,
                              ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: .82),
                          ),
                    ),
                    SizedBox(height: compact ? 12 : 16),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 9 : 11,
                        vertical: compact ? 6 : 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .13),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .18),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 14,
                            color: Colors.white.withValues(alpha: .9),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            DateFormat(
                                    compact ? 'd MMM yyyy' : 'EEE, d MMM yyyy')
                                .format(now),
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberReportDetails extends StatelessWidget {
  const _MemberReportDetails({required this.result});

  final _DashboardRecords result;

  @override
  Widget build(BuildContext context) {
    if (result.error != null || result.records.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 12),
      child: Column(
        children: [
          for (final record in result.records)
            Card(
              key: Key(
                'member-report-detail-${result.label.toLowerCase().split(' ').first}-'
                '${record['rowIndex'] ?? record['__rowIndex'] ?? 'entry'}-'
                '${record['date'] ?? 'undated'}',
              ),
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                title: Text(
                  '${record['memberName'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  'Date: ${record['date'] ?? '-'} · '
                  'Entry: ${_currency(_number(record['depAmt']))} · '
                  'Received: ${_currency(_number(record['totalReceived']))}',
                ),
                trailing: Text(
                  '${_number(record['totalCount']).toInt()} paid',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DashboardData {
  const _DashboardData({
    required this.ledger,
    required this.daily,
    required this.weekly,
    required this.monthly,
    required this.users,
    required this.deposits,
    this.rolePermissions,
    this.rolePermissionsError,
  });

  final _DashboardRecords ledger;
  final _DashboardRecords daily;
  final _DashboardRecords weekly;
  final _DashboardRecords monthly;
  final _DashboardRecords users;
  final List<_DashboardDepositReport> deposits;
  final Map<String, Map<String, bool>>? rolePermissions;
  final String? rolePermissionsError;

  List<_DashboardRecords> get sources =>
      [
        ledger,
        daily,
        weekly,
        monthly,
        users,
        ...deposits.map((item) => item.result),
      ];
}

class _DashboardDepositReport {
  const _DashboardDepositReport({
    required this.product,
    required this.cadence,
    required this.pageIndex,
    required this.result,
  });

  final String product;
  final String cadence;
  final int pageIndex;
  final _DashboardRecords result;

  String get title => switch (product) {
        'FD' => 'Fixed Deposit — Monthly',
        'RD' => 'Recurring Deposit — ${_capitalize(cadence)}',
        _ => 'Daily Recurring Deposit — ${_capitalize(cadence)}',
      };

  static String _capitalize(String value) =>
      value[0].toUpperCase() + value.substring(1);
}

class _DepositSummaryCard extends StatelessWidget {
  const _DepositSummaryCard({
    required this.report,
    required this.onOpen,
    this.memberView = false,
  });

  final _DashboardDepositReport report;
  final VoidCallback onOpen;
  final bool memberView;

  @override
  Widget build(BuildContext context) {
    if (report.result.error != null) {
      return _SourceErrorCard(
        source: report.title,
        message: report.result.error!,
      );
    }
    final accounts = report.result.records;
    final maturity = accounts.fold<double>(
      0,
      (total, account) => total + _number(account['maturityAmount']),
    );
    final paid = accounts.fold<int>(
      0,
      (total, account) =>
          total +
          (account['payments'] is List
              ? (account['payments'] as List)
                  .where((payment) => payment == true || payment == 1)
                  .length
              : 0),
    );
    final scheduled = accounts.fold<int>(
      0,
      (total, account) =>
          total +
          (account['payments'] is List
              ? (account['payments'] as List).length
              : 0),
    );
    final accountSummary = accounts.isEmpty
        ? 'No accounts yet'
        : '${accounts.length} accounts · '
            '${memberView ? 'My' : 'Total'} estimated maturity '
            '${_currency(maturity)}'
            '${scheduled == 0 ? '' : ' · $paid/$scheduled installments paid'}';
    const color = Color(0xFF078A6A);
    return Card(
      key: Key(
        'dashboard-deposit-${report.product.toLowerCase()}-${report.cadence}',
      ),
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.savings_rounded, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      accountSummary,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleAccessData {
  const _RoleAccessData({this.permissions, this.error});

  final Map<String, Map<String, bool>>? permissions;
  final String? error;
}

class _DashboardRecords {
  const _DashboardRecords({
    required this.label,
    this.records = const [],
    this.error,
  });

  final String label;
  final List<Map<String, dynamic>> records;
  final String? error;

  num get received => records.fold<num>(
        0,
        (total, record) => total + _number(record['totalReceived']),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.trailing});

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final titleStyle = Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800);
          final trailingStyle = TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          );
          if (constraints.maxWidth < 360) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: titleStyle),
                const SizedBox(height: 2),
                Text(
                  trailing,
                  style: trailingStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  trailing,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: trailingStyle,
                ),
              ),
            ],
          );
        },
      );
}

class _CollectionSummaryCard extends StatelessWidget {
  const _CollectionSummaryCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.result,
    required this.onOpen,
    this.memberView = false,
  });

  final String title;
  final IconData icon;
  final Color color;
  final _DashboardRecords result;
  final VoidCallback onOpen;
  final bool memberView;

  @override
  Widget build(BuildContext context) {
    if (result.error != null) {
      return _SourceErrorCard(source: title, message: result.error!);
    }
    final entries = result.records;
    final paid = entries.fold<int>(
      0,
      (total, entry) =>
          total +
          (entry['periods'] is List
              ? (entry['periods'] as List)
                  .where((period) => period == true || period == 1)
                  .length
              : 0),
    );
    final received = entries.fold<num>(
      0,
      (total, entry) => total + _number(entry['totalReceived']),
    );
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: color.withValues(alpha: .14)),
      ),
      child: InkWell(
        key:
            Key('dashboard-collection-${title.split(' ').first.toLowerCase()}'),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .11),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _currency(received),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _CollectionStat(
                    icon: Icons.people_alt_outlined,
                    label: memberView ? 'Entries' : 'Members',
                    value: '${entries.length}',
                  ),
                  const SizedBox(width: 10),
                  _CollectionStat(
                    icon: Icons.check_circle_outline_rounded,
                    label: 'Payments marked',
                    value: '$paid',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollectionStat extends StatelessWidget {
  const _CollectionStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(12),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 145) {
              return Row(
                children: [
                  Icon(icon, size: 16, color: colors.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                        ),
                        Text(
                          value,
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }
            return Row(
              children: [
                Icon(icon, size: 16, color: colors.onSurfaceVariant),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  value,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RegisteredAccountsPanel extends StatelessWidget {
  const _RegisteredAccountsPanel({
    required this.users,
    required this.error,
    required this.rolePermissions,
    required this.rolePermissionsError,
    required this.currentRole,
    required this.currentPermissions,
    required this.onOpen,
  });

  final List<Map<String, dynamic>> users;
  final String? error;
  final Map<String, Map<String, bool>>? rolePermissions;
  final String? rolePermissionsError;
  final String currentRole;
  final Map<String, bool> currentPermissions;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Column(
        children: [
          _SourceErrorCard(source: 'Users', message: error!),
          _openDirectoryButton(),
        ],
      );
    }
    if (users.isEmpty) {
      return Column(
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.person_search_rounded),
              title: Text('No user accounts found'),
            ),
          ),
          _openDirectoryButton(),
        ],
      );
    }

    final normalizedRoles = users
        .map((user) => (user['role'] ?? 'Other').toString().trim())
        .map((role) => role.isEmpty ? 'Other' : role)
        .toList();
    final roles = <String>[
      'Admin',
      'Collector',
      'Member',
      if (normalizedRoles.any(
        (role) => !const ['admin', 'collector', 'member']
            .contains(role.toLowerCase()),
      ))
        'Other',
    ];
    final counts = <String, int>{
      for (final role in roles)
        role: normalizedRoles
            .where(
              (candidate) => role == 'Other'
                  ? !const ['admin', 'collector', 'member']
                      .contains(candidate.toLowerCase())
                  : candidate.toLowerCase() == role.toLowerCase(),
            )
            .length,
    };
    final colors = Theme.of(context).colorScheme;
    const permissionLabels = <String, String>{
      'shared_data_read': 'View shared data',
      'own_collection_read': 'View own collections',
      'collection_manage': 'Manage collections',
      'deposit_view': 'View deposit accounts',
      'deposit_manage': 'Manage deposit accounts',
      'ledger_manage': 'Manage ledger',
      'user_manage': 'Manage users',
    };

    final chartCard = Card(
      key: const Key('registered-accounts-role-chart'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.pie_chart_rounded, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Accounts by role',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${users.length} total',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _RolePieChart(
              roles: roles,
              counts: counts,
              total: users.length,
              colors: portalRoleColors,
            ),
          ],
        ),
      ),
    );
    final accountTable = Card(
      margin: EdgeInsets.zero,
      child: SingleChildScrollView(
        key: const Key('registered-accounts-table'),
        scrollDirection: Axis.horizontal,
        child: DataTable(
          dataRowMinHeight: 64,
          dataRowMaxHeight: 80,
          columns: const [
            DataColumn(label: Text('Account No.')),
            DataColumn(label: Text('Account')),
            DataColumn(label: Text('Role')),
            DataColumn(label: Text('Access')),
          ],
          rows: [
            for (final user in users.take(5))
              _registeredAccountRow(
                context: context,
                user: user,
                colors: colors,
                permissionLabels: permissionLabels,
                rolePermissions: rolePermissions,
                rolePermissionsError: rolePermissionsError,
                currentRole: currentRole,
                currentPermissions: currentPermissions,
              ),
          ],
        ),
      ),
    );
    final accountList = Column(
      key: const Key('registered-accounts-list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Accounts',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                'Showing ${math.min(users.length, 5)} of ${users.length}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        accountTable,
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('dashboard-open-users'),
          onPressed: onOpen,
          icon: const Icon(Icons.people_alt_rounded),
          label: const Text('Open user directory'),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 760) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: chartCard),
              const SizedBox(width: 16),
              Expanded(flex: 6, child: accountList),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            chartCard,
            const SizedBox(height: 16),
            accountList,
          ],
        );
      },
    );
  }

  Widget _openDirectoryButton() => OutlinedButton.icon(
        key: const Key('dashboard-open-users'),
        onPressed: onOpen,
        icon: const Icon(Icons.people_alt_rounded),
        label: const Text('Open user directory'),
      );

  DataRow _registeredAccountRow({
    required BuildContext context,
    required Map<String, dynamic> user,
    required ColorScheme colors,
    required Map<String, String> permissionLabels,
    required Map<String, Map<String, bool>>? rolePermissions,
    required String? rolePermissionsError,
    required String currentRole,
    required Map<String, bool> currentPermissions,
  }) {
    final name = (user['name'] ?? 'Unnamed user').toString().trim();
    final role = (user['role'] ?? 'Member').toString().trim();
    final normalizedRole = role.isEmpty ? 'member' : role.toLowerCase();
    final isAdmin = normalizedRole == 'admin';
    final permissions = isAdmin
        ? permissionLabels.keys.toSet()
        : rolePermissions?[normalizedRole]
                ?.entries
                .where((entry) => entry.value)
                .map((entry) => entry.key)
                .toSet() ??
            (normalizedRole == currentRole.toLowerCase()
                ? currentPermissions.entries
                    .where((entry) => entry.value)
                    .map((entry) => entry.key)
                    .toSet()
                : null);
    final permissionSummary = permissions == null
        ? currentRole.toLowerCase() == 'admin' && rolePermissionsError != null
            ? 'Unavailable: $rolePermissionsError'
            : 'Admin-only role permission details'
        : permissions.isEmpty
            ? 'No role permissions enabled'
            : permissionLabels.entries
                .where((entry) => permissions.contains(entry.key))
                .map((entry) => entry.value)
                .join(' · ');
    final accountId = user['id'] ?? name;
    final reportAccess = [
      ('Daily', 'dailyAccess'),
      ('Weekly', 'weeklyAccess'),
      ('Monthly', 'monthlyAccess'),
    ].map((report) {
      final value = user[report.$2];
      final enabled =
          value == null || value.toString().toLowerCase() != 'false';
      return '${report.$1} ${enabled ? 'On' : 'Off'}';
    }).join(' · ');
    final roleColor = portalRoleColor(role);

    return DataRow(
      cells: [
        DataCell(
          Text(
            (user['accountNo'] ?? 'Not assigned').toString(),
            key: Key('registered-account-number-$accountId'),
          ),
        ),
        DataCell(
          SizedBox(
            width: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  name.isEmpty ? 'Unnamed user' : name,
                  key: Key('registered-account-$accountId'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  (user['email'] ?? '').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
        DataCell(
          Text(
            role.isEmpty ? 'Member' : role,
            style: TextStyle(
              color: roleColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: 260,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Role access: $permissionSummary',
                  key: Key('registered-account-permissions-$accountId'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: rolePermissionsError == null
                            ? colors.onSurfaceVariant
                            : colors.error,
                      ),
                ),
                Text(
                  'Reports: $reportAccess',
                  key: Key('registered-account-reports-$accountId'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RolePieChart extends StatelessWidget {
  const _RolePieChart({
    required this.roles,
    required this.counts,
    required this.total,
    required this.colors,
  });

  final List<String> roles;
  final Map<String, int> counts;
  final int total;
  final Map<String, Color> colors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segments = [
      for (final role in roles)
        if ((counts[role] ?? 0) > 0)
          _RolePieSegment(
            role: role,
            count: counts[role]!,
            color: colors[role.toLowerCase()] ?? colors['other']!,
          ),
    ];
    final description = roles.map((role) {
      final count = counts[role] ?? 0;
      final share = total == 0 ? 0 : (count * 100 / total).round();
      return '$role $count, $share percent';
    }).join('; ');

    return LayoutBuilder(
      builder: (context, constraints) {
        final chart = Semantics(
          key: const Key('registered-accounts-pie'),
          label: 'Account role pie chart. $description',
          child: SizedBox(
            width: 156,
            height: 156,
            child: CustomPaint(
              painter: _RolePiePainter(segments: segments, total: total),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$total',
                      key: const Key('registered-accounts-pie-total'),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'accounts',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        final legend = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final role in roles)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colors[role.toLowerCase()] ?? colors['other'],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        role,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '${counts[role] ?? 0}',
                      key: Key('registered-role-count-${role.toLowerCase()}'),
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 42,
                      child: Text(
                        '${total == 0 ? 0 : ((counts[role] ?? 0) * 100 / total).round()}%',
                        key: Key('registered-role-share-${role.toLowerCase()}'),
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );

        if (constraints.maxWidth >= 440) {
          return Row(
            children: [
              chart,
              const SizedBox(width: 20),
              Expanded(child: legend),
            ],
          );
        }
        return Column(
          children: [
            chart,
            const SizedBox(height: 8),
            legend,
          ],
        );
      },
    );
  }
}

class _RolePieSegment {
  const _RolePieSegment({
    required this.role,
    required this.count,
    required this.color,
  });

  final String role;
  final int count;
  final Color color;
}

class _RolePiePainter extends CustomPainter {
  const _RolePiePainter({required this.segments, required this.total});

  final List<_RolePieSegment> segments;
  final int total;

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0 || segments.isEmpty) return;
    final side = math.min(size.width, size.height);
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: side / 2,
    );
    var startAngle = -math.pi / 2;
    for (final segment in segments) {
      final sweepAngle = (segment.count / total) * math.pi * 2;
      final paint = Paint()
        ..color = segment.color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;
      canvas.drawArc(rect, startAngle, sweepAngle, true, paint);
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _RolePiePainter oldDelegate) =>
      total != oldDelegate.total ||
      segments.length != oldDelegate.segments.length ||
      segments.indexed.any((entry) {
        final oldSegment = oldDelegate.segments[entry.$1];
        final segment = entry.$2;
        return segment.role != oldSegment.role ||
            segment.count != oldSegment.count ||
            segment.color != oldSegment.color;
      });
}

class _SourceErrorCard extends StatelessWidget {
  const _SourceErrorCard({required this.source, required this.message});

  final String source;
  final String message;

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: ListTile(
          leading: Icon(
            Icons.error_outline_rounded,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text('$source data unavailable'),
          subtitle: Text(message),
        ),
      );
}

num _number(dynamic value) => num.tryParse(value?.toString() ?? '') ?? 0;

num _sum(List<Map<String, dynamic>> records, String field) =>
    records.fold<num>(0, (total, record) => total + _number(record[field]));

String _currency(num amount) => NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    ).format(amount);
