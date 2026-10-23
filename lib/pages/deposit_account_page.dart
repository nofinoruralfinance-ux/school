import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../widgets/portal_loading.dart';
import '../widgets/portal_widgets.dart';

const int maxDepositTenureMonths = 120;

DateTime depositMaturityDate(DateTime startDate, int tenureMonths) {
  final monthIndex = startDate.month - 1 + tenureMonths;
  final year = startDate.year + monthIndex ~/ 12;
  final month = monthIndex % 12 + 1;
  final day = startDate.day.clamp(1, DateUtils.getDaysInMonth(year, month));
  return DateTime(year, month, day);
}

List<DateTime> depositPeriodDates({
  required DateTime startDate,
  required DateTime maturityDate,
  required String cadence,
}) {
  final dates = <DateTime>[];
  if (cadence == 'monthly') {
    for (var period = 1; period <= maxDepositTenureMonths; period++) {
      final date = depositMaturityDate(startDate, period);
      if (date.isAfter(maturityDate)) break;
      dates.add(date);
    }
    return dates;
  }
  final interval = cadence == 'weekly' ? 7 : 1;
  for (var date = DateTime(
    startDate.year,
    startDate.month,
    startDate.day + interval,
  );
      !date.isAfter(maturityDate);
      date = DateTime(date.year, date.month, date.day + interval)) {
    dates.add(date);
  }
  return dates;
}

double depositMaturityAmount({
  required String product,
  required String cadence,
  required double amount,
  required double annualRate,
  required int tenureMonths,
  required int periodCount,
}) {
  final rate = annualRate / 100;
  if (product == 'FD') {
    return (amount * _power(1 + rate / 12, tenureMonths) * 100).round() / 100;
  }
  final periodsPerYear = cadence == 'daily'
      ? 365
      : cadence == 'weekly'
          ? 52
          : 12;
  final periodRate = rate / periodsPerYear;
  final maturity = periodRate == 0
      ? amount * periodCount
      : amount * (_power(1 + periodRate, periodCount) - 1) / periodRate;
  return (maturity * 100).round() / 100;
}

double _power(double base, int exponent) {
  var value = 1.0;
  for (var i = 0; i < exponent; i++) {
    value *= base;
  }
  return value;
}

class DepositAccountPage extends StatefulWidget {
  const DepositAccountPage({
    super.key,
    required this.apiService,
    required this.session,
    required this.product,
    required this.cadence,
  });

  final ApiService apiService;
  final AuthSession session;
  final String product;
  final String cadence;

  @override
  State<DepositAccountPage> createState() => _DepositAccountPageState();
}

class _DepositAccountPageState extends State<DepositAccountPage> {
  late Future<List<Map<String, dynamic>>> _accounts;
  final _searchController = TextEditingController();
  final _memberController = TextEditingController();
  final _amountController = TextEditingController();
  final _rateController = TextEditingController();
  final _tenureController = TextEditingController(text: '12');
  final Set<String> _deletingAccountIds = {};
  bool _isRefreshing = false;
  String _query = '';

  bool get _canManage =>
      widget.session.hasPermission('deposit_manage') &&
      widget.session.role.toLowerCase() != 'member';

  String get _productName => switch (widget.product) {
        'FD' => 'Fixed Deposit',
        'RD' => 'Recurring Deposit',
        _ => 'Daily Recurring Deposit',
      };

  String get _amountName =>
      widget.product == 'FD' ? 'Principal' : 'Installment';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _memberController.dispose();
    _amountController.dispose();
    _rateController.dispose();
    _tenureController.dispose();
    super.dispose();
  }

  void _load() {
    _accounts = widget.apiService.fetchDepositAccounts(
      product: widget.product,
      cadence: widget.cadence,
      session: widget.session,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _isRefreshing = true;
      _load();
    });
    try {
      await _accounts;
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              key: const Key('add-deposit-account'),
              onPressed: _showAccountForm,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New account'),
            )
          : null,
      body: PortalGradientBackground(
        child: Column(
          children: [
            PortalPageHeader(
              title: '$_productName — ${_capitalize(widget.cadence)}',
              subtitle: widget.product == 'FD'
                  ? 'One-time principal with monthly compounding.'
                  : 'Track installments and estimated maturity value.',
              icon: Icons.savings_rounded,
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _accounts,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return PortalLoadingState(
                      label: 'Loading ${widget.product} accounts',
                    );
                  }
                  if (snapshot.hasError) {
                    return PortalErrorState(
                      message: snapshot.error.toString(),
                      onRetry: () => setState(_load),
                    );
                  }
                  final accounts = snapshot.data;
                  if (accounts == null) {
                    return PortalErrorState(
                      message: 'The server returned no deposit account data.',
                      onRetry: () => setState(_load),
                    );
                  }
                  final visibleAccounts = accounts.where((account) {
                    if (_query.isEmpty) return true;
                    final memberName =
                        account['memberName']?.toString().toLowerCase() ?? '';
                    return memberName.contains(_query);
                  }).toList();
                  if (accounts.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: _refresh,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: PortalEmptyState(
                              title: 'No $_productName accounts yet',
                              subtitle: _canManage
                                  ? 'Create an account to start tracking deposits.'
                                  : 'Deposit accounts will appear here when available.',
                              icon: Icons.savings_outlined,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      children: [
                        if (_isRefreshing)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: PortalMetricCard(
                                label: 'Deposit accounts',
                                value: '${visibleAccounts.length}',
                                icon: Icons.account_balance_rounded,
                                accent: const Color(0xFF3458D4),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: PortalMetricCard(
                                label: 'Estimated maturity',
                                value: _money(visibleAccounts.fold<double>(
                                  0,
                                  (total, account) =>
                                      total +
                                      _number(account['maturityAmount']),
                                )),
                                icon: Icons.trending_up_rounded,
                                accent: const Color(0xFF078A6A),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          key: const Key('deposit-account-search'),
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search member accounts',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear search',
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _query = '');
                                    },
                                    icon: const Icon(Icons.clear_rounded),
                                  ),
                          ),
                          onChanged: (value) => setState(
                            () => _query = value.trim().toLowerCase(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (visibleAccounts.isEmpty)
                          const PortalEmptyState(
                            title: 'No matching accounts',
                            subtitle:
                                'Try another member name or clear search.',
                            icon: Icons.search_off_rounded,
                          )
                        else
                          for (final account in visibleAccounts)
                            _accountCard(account),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountCard(Map<String, dynamic> account) {
    final payments = account['payments'] is List
        ? account['payments'] as List
        : const <dynamic>[];
    final paidCount = payments.where(_isPaid).length;
    final amount = _number(account['amount']);
    final maturityAmount = _number(account['maturityAmount']);
    final accent = widget.product == 'FD'
        ? const Color(0xFF3458D4)
        : widget.product == 'RD'
            ? const Color(0xFF8E24AA)
            : const Color(0xFF078A6A);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.savings_rounded, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account['memberName']?.toString() ?? 'Unknown member',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _AccountTag(
                            label: widget.product,
                            color: accent,
                          ),
                          _AccountTag(
                            label: _capitalize(widget.cadence),
                            color: Theme.of(context).colorScheme.tertiary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_canManage)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: Key('edit-deposit-${account['id']}'),
                        tooltip: 'Edit account',
                        style: IconButton.styleFrom(
                          foregroundColor: portalEditColor,
                        ),
                        onPressed: () => _showAccountForm(account: account),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        key: Key('delete-deposit-${account['id']}'),
                        tooltip: 'Delete account',
                        style: IconButton.styleFrom(
                          foregroundColor: portalDeleteColor,
                        ),
                        onPressed:
                            _deletingAccountIds.contains('${account['id']}')
                                ? null
                                : () => _deleteAccount(account),
                        icon: _deletingAccountIds.contains('${account['id']}')
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: portalDeleteColor,
                                ),
                              )
                            : const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _AccountDetail(
                  icon: Icons.calendar_today_rounded,
                  label: 'Started',
                  value: account['startDate']?.toString() ?? '-',
                ),
                _AccountDetail(
                  icon: Icons.event_available_rounded,
                  label: 'Matures',
                  value: account['maturityDate']?.toString() ?? '-',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _AccountDetail(
                    icon: Icons.currency_rupee_rounded,
                    label: _amountName,
                    value: _money(amount),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AccountDetail(
                    icon: Icons.percent_rounded,
                    label: 'Annual rate',
                    value:
                        '${_number(account['annualRate']).toStringAsFixed(2)}%',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AccountDetail(
                    icon: Icons.timelapse_rounded,
                    label: 'Tenure',
                    value: '${account['tenureMonths']} mo.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accent.withValues(alpha: .16)),
              ),
              child: Row(
                children: [
                  Icon(Icons.account_balance_wallet_rounded, color: accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Estimated maturity',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _money(maturityAmount),
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: accent,
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (widget.product != 'FD') ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    'Installments',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const Spacer(),
                  Text('$paidCount of ${payments.length} paid'),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: payments.isEmpty ? 0 : paidCount / payments.length,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(8),
                      color: accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  key: Key('deposit-schedule-${account['id']}'),
                  onPressed: () => _showSchedule(account),
                  icon: const Icon(Icons.event_note_rounded),
                  label: const Text('View payment schedule'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showAccountForm({Map<String, dynamic>? account}) async {
    final isEditing = account != null;
    final initialDate = isEditing
        ? DateTime.tryParse(account['startDate']?.toString() ?? '')
        : DateTime.now();
    if (initialDate == null) {
      showPortalToast(
        context,
        'This account has an invalid start date and cannot be edited.',
        isError: true,
      );
      return;
    }
    _memberController.text =
        isEditing ? account['memberName']?.toString() ?? '' : '';
    _amountController.text =
        isEditing ? account['amount']?.toString() ?? '' : '';
    _rateController.text =
        isEditing ? account['annualRate']?.toString() ?? '' : '';
    _tenureController.text =
        isEditing ? account['tenureMonths']?.toString() ?? '12' : '12';
    var startDate = DateUtils.dateOnly(initialDate);
    var saving = false;
    String? errorMessage;
    var estimate = 0.0;
    var estimatePeriods = 0;

    void updateEstimate(void Function(void Function()) setDialogState) {
      final amount = double.tryParse(_amountController.text.trim());
      final rate = double.tryParse(_rateController.text.trim());
      final tenure = int.tryParse(_tenureController.text.trim());
      if (amount == null ||
          rate == null ||
          tenure == null ||
          amount <= 0 ||
          rate < 0 ||
          rate > 100 ||
          tenure < 1 ||
          tenure > maxDepositTenureMonths) {
        setDialogState(() {
          estimate = 0;
          estimatePeriods = 0;
        });
        return;
      }
      final dates = widget.product == 'FD'
          ? const <DateTime>[]
          : depositPeriodDates(
              startDate: startDate,
              maturityDate: depositMaturityDate(startDate, tenure),
              cadence: widget.cadence,
            );
      setDialogState(() {
        estimatePeriods = dates.length;
        estimate = depositMaturityAmount(
          product: widget.product,
          cadence: widget.cadence,
          amount: amount,
          annualRate: rate,
          tenureMonths: tenure,
          periodCount: dates.length,
        );
      });
    }

    if (isEditing) {
      final amount = double.tryParse(_amountController.text.trim()) ?? 0;
      final rate = double.tryParse(_rateController.text.trim()) ?? 0;
      final tenure = int.tryParse(_tenureController.text.trim()) ?? 0;
      final dates = widget.product == 'FD'
          ? const <DateTime>[]
          : depositPeriodDates(
              startDate: startDate,
              maturityDate: depositMaturityDate(startDate, tenure),
              cadence: widget.cadence,
            );
      estimatePeriods = dates.length;
      estimate = depositMaturityAmount(
        product: widget.product,
        cadence: widget.cadence,
        amount: amount,
        annualRate: rate,
        tenureMonths: tenure,
        periodCount: dates.length,
      );
    }

    final formKey = GlobalKey<FormState>();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            '${isEditing ? 'Edit' : 'New'} $_productName account',
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('deposit-start-date'),
                      onPressed: saving
                          ? null
                          : () async {
                              final selected = await showDatePicker(
                                context: context,
                                initialDate: startDate,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (selected != null) {
                                setDialogState(
                                  () =>
                                      startDate = DateUtils.dateOnly(selected),
                                );
                                updateEstimate(setDialogState);
                              }
                            },
                      icon: const Icon(Icons.calendar_today_rounded),
                      label: Text(
                        'Start date: ${DateFormat('yyyy-MM-dd').format(startDate)}',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const Key('deposit-member-name'),
                      controller: _memberController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Member name',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Enter a member name'
                              : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const Key('deposit-amount'),
                      controller: _amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: '$_amountName amount',
                        prefixText: '₹ ',
                      ),
                      onChanged: (_) => updateEstimate(setDialogState),
                      validator: (value) {
                        final amount = double.tryParse(value?.trim() ?? '');
                        return amount == null || !amount.isFinite || amount <= 0
                            ? 'Enter an amount greater than zero'
                            : null;
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const Key('deposit-annual-rate'),
                      controller: _rateController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Annual interest rate',
                        suffixText: '% p.a.',
                      ),
                      onChanged: (_) => updateEstimate(setDialogState),
                      validator: (value) {
                        final rate = double.tryParse(value?.trim() ?? '');
                        return rate == null ||
                                !rate.isFinite ||
                                rate < 0 ||
                                rate > 100
                            ? 'Enter a rate from 0% to 100%'
                            : null;
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const Key('deposit-tenure-months'),
                      controller: _tenureController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Tenure',
                        suffixText: 'months (1–120)',
                      ),
                      onChanged: (_) => updateEstimate(setDialogState),
                      validator: (value) {
                        final months = int.tryParse(value?.trim() ?? '');
                        return months == null ||
                                months < 1 ||
                                months > maxDepositTenureMonths
                            ? 'Enter a tenure from 1 to $maxDepositTenureMonths months'
                            : null;
                      },
                    ),
                    if (estimate > 0) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Estimated maturity on '
                          '${DateFormat('yyyy-MM-dd').format(depositMaturityDate(startDate, int.parse(_tenureController.text)))}: '
                          '${_money(estimate)}'
                          '${widget.product == 'FD' ? '' : ' · $estimatePeriods installments'}',
                          key: const Key('deposit-maturity-estimate'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Illustrative estimate only. Actual returns depend on the approved scheme terms and payment history.',
                        key: Key('deposit-estimate-disclaimer'),
                      ),
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorMessage!,
                        key: const Key('deposit-form-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  saving ? null : () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('save-deposit-account'),
              onPressed: saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      final tenure = int.parse(_tenureController.text.trim());
                      final periodDates = widget.product == 'FD'
                          ? const <DateTime>[]
                          : depositPeriodDates(
                              startDate: startDate,
                              maturityDate:
                                  depositMaturityDate(startDate, tenure),
                              cadence: widget.cadence,
                            );
                      setDialogState(() {
                        saving = true;
                        errorMessage = null;
                      });
                      try {
                        final saved = await withPortalLoading(
                          context,
                          label: isEditing
                              ? 'Updating deposit account'
                              : 'Creating deposit account',
                          action: () => widget.apiService.sendPostRequest({
                            'action': isEditing
                                ? 'editDepositAccount'
                                : 'addDepositAccount',
                            if (isEditing) 'id': account['id'],
                            'memberName': _memberController.text.trim(),
                            'product': widget.product,
                            'cadence': widget.cadence,
                            'startDate':
                                DateFormat('yyyy-MM-dd').format(startDate),
                            'amount':
                                double.parse(_amountController.text.trim()),
                            'annualRate':
                                double.parse(_rateController.text.trim()),
                            'tenureMonths': tenure,
                            if (!isEditing)
                              'payments': List<bool>.filled(
                                periodDates.length,
                                false,
                              ),
                          }, widget.session),
                        );
                        if (!saved) {
                          throw const ApiException(
                            'The server did not save the deposit account.',
                          );
                        }
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop(true);
                        }
                      } on ApiException catch (error) {
                        setDialogState(() {
                          saving = false;
                          errorMessage = error.message;
                        });
                      } catch (error) {
                        setDialogState(() {
                          saving = false;
                          errorMessage = 'Could not save the account: $error';
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isEditing ? 'Save changes' : 'Create account'),
            ),
          ],
        ),
      ),
    );
    if (created == true && mounted) {
      setState(_load);
      showPortalToast(
        context,
        isEditing ? 'Deposit account updated.' : 'Deposit account created.',
      );
    }
  }

  Future<void> _showSchedule(Map<String, dynamic> account) async {
    final rawDates = account['periodDates'];
    final rawPayments = account['payments'];
    if (rawDates is! List ||
        rawPayments is! List ||
        rawDates.length != rawPayments.length) {
      showPortalToast(
        context,
        'The server returned an invalid payment schedule.',
        isError: true,
      );
      return;
    }
    final dates = List<String>.from(rawDates.map((date) => date.toString()));
    final payments = List<bool>.from(rawPayments.map(_isPaid));
    final pending = <int>{};
    String? errorMessage;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${account['memberName']} — payments'),
          content: SizedBox(
            width: double.maxFinite,
            height: 420,
            child: Column(
              children: [
                Text(
                  '${payments.where((paid) => paid).length} / '
                  '${payments.length} payments · ${_money(_number(account['amount']))} each',
                ),
                if (errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      errorMessage!,
                      key: const Key('deposit-schedule-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    itemCount: dates.length,
                    itemBuilder: (context, index) => CheckboxListTile(
                      key: Key('deposit-payment-${account['id']}-$index'),
                      value: payments[index],
                      title: Text('Installment ${index + 1}'),
                      subtitle: Text(dates[index]),
                      secondary: pending.contains(index)
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                      onChanged: !_canManage || pending.contains(index)
                          ? null
                          : (value) async {
                              setDialogState(() {
                                pending.add(index);
                                errorMessage = null;
                              });
                              try {
                                final saved =
                                    await widget.apiService.sendPostRequest({
                                  'action': 'toggleDepositPayment',
                                  'id': account['id'],
                                  'periodIndex': index + 1,
                                }, widget.session);
                                if (!saved) {
                                  throw const ApiException(
                                    'The server did not save this payment.',
                                  );
                                }
                                setDialogState(() {
                                  payments[index] = value ?? false;
                                  pending.remove(index);
                                });
                                if (mounted) setState(_load);
                              } on ApiException catch (error) {
                                setDialogState(() {
                                  pending.remove(index);
                                  errorMessage = error.message;
                                });
                              } catch (error) {
                                setDialogState(() {
                                  pending.remove(index);
                                  errorMessage =
                                      'Could not update payment: $error';
                                });
                              }
                            },
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteAccount(Map<String, dynamic> account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete deposit account?'),
        content: Text(
          'Delete the ${account['product']} account for '
          '${account['memberName']} and its payment history?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-delete-deposit'),
            style: FilledButton.styleFrom(
              backgroundColor: portalDeleteColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final accountId = '${account['id']}';
    setState(() => _deletingAccountIds.add(accountId));
    try {
      final deleted = await withPortalLoading(
        context,
        label: 'Deleting deposit account',
        action: () => widget.apiService.sendPostRequest({
          'action': 'deleteDepositAccount',
          'id': account['id'],
        }, widget.session),
      );
      if (!deleted) {
        throw const ApiException('The server did not delete this account.');
      }
      if (mounted) {
        setState(() {
          _deletingAccountIds.remove(accountId);
          _load();
        });
        showPortalToast(context, 'Deposit account deleted.');
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _deletingAccountIds.remove(accountId));
        showPortalToast(context, error.message, isError: true);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _deletingAccountIds.remove(accountId));
        showPortalToast(
          context,
          'Could not delete the account: $error',
          isError: true,
        );
      }
    }
  }

  bool _isPaid(dynamic value) => value == true || value == 1;

  double _number(dynamic value) => double.tryParse('$value') ?? 0;

  String _money(double value) => NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: 2,
      ).format(value);

  String _capitalize(String value) =>
      value[0].toUpperCase() + value.substring(1);
}

class _AccountTag extends StatelessWidget {
  const _AccountTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _AccountDetail extends StatelessWidget {
  const _AccountDetail({
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
    return Container(
      constraints: const BoxConstraints(minHeight: 66),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: colors.onSurfaceVariant),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}
