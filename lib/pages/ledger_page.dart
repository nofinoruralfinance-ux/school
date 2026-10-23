import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../widgets/portal_loading.dart';
import '../widgets/portal_widgets.dart';

class LedgerPage extends StatefulWidget {
  const LedgerPage({
    super.key,
    required this.apiService,
    required this.session,
  });

  final ApiService apiService;
  final AuthSession session;

  @override
  State<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage> {
  late Future<dynamic> _future;
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _ledgerEntries = [];
  String _query = '';

  bool get _canAddEntry => widget.session.hasPermission('ledger_manage');
  bool get _canManageEntries => _canAddEntry;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _load() {
    _future = widget.apiService.fetchSheetData('getAmount', widget.session);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      floatingActionButton: _canAddEntry
          ? FloatingActionButton.extended(
              heroTag: null,
              key: const Key('add-ledger-entry'),
              onPressed: _showAddEntry,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New'),
            )
          : null,
      body: PortalGradientBackground(
        child: FutureBuilder<dynamic>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const PortalLoadingState(label: 'Loading ledger');
            }
            if (snapshot.hasError || snapshot.data is! List) {
              return _LoadError(
                message: snapshot.error?.toString() ?? 'Failed to load ledger.',
                onRetry: () => setState(_load),
              );
            }

            final entries = (snapshot.data as List).whereType<Map>().toList();
            _ledgerEntries = entries
                .map((entry) => Map<String, dynamic>.from(entry))
                .toList();
            if (entries.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const PortalPageHeader(
                    title: 'Ledger overview',
                    subtitle: 'Track account activity in one place.',
                    icon: Icons.account_balance_wallet_rounded,
                  ),
                  SizedBox(
                    height: 340,
                    child: PortalEmptyState(
                      title: 'No transactions yet',
                      subtitle: _canAddEntry
                          ? 'Add your first ledger entry to get started.'
                          : 'Ledger activity will appear here.',
                      icon: Icons.receipt_long_outlined,
                    ),
                  ),
                ],
              );
            }
            final visibleEntries = entries.where(_matchesSearch).toList();
            final totalDeposits = entries.fold<num>(
              0,
              (total, item) => total + _number(item['deposit']),
            );
            final totalWithdrawals = entries.fold<num>(
              0,
              (total, item) => total + _number(item['withdrawal']),
            );
            return RefreshIndicator(
              onRefresh: () async {
                setState(_load);
                await _future;
              },
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 104),
                itemCount:
                    visibleEntries.isEmpty ? 5 : visibleEntries.length + 4,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return const PortalPageHeader(
                      title: 'Ledger overview',
                      subtitle: 'Track account activity in one place.',
                      icon: Icons.account_balance_wallet_rounded,
                    );
                  }
                  if (index == 1) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 22),
                      child: Row(
                        children: [
                          Expanded(
                            child: PortalMetricCard(
                              label: 'Total deposits',
                              value: '₹${_formatAmount(totalDeposits)}',
                              icon: Icons.south_west_rounded,
                              accent: const Color(0xFF078A6A),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: PortalMetricCard(
                              label: 'Withdrawals',
                              value: '₹${_formatAmount(totalWithdrawals)}',
                              icon: Icons.north_east_rounded,
                              accent: const Color(0xFFD25858),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  if (index == 2) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 18),
                      child: TextField(
                        key: const Key('ledger-search'),
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search by person, remarks, payment mode',
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
                    );
                  }
                  if (index == 3) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      child: Row(
                        children: [
                          Text(
                            'Recent activity',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const Spacer(),
                          Text(
                            _query.isEmpty
                                ? '${entries.length} records'
                                : '${visibleEntries.length} of ${entries.length} records',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    );
                  }
                  if (visibleEntries.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: PortalEmptyState(
                        title: 'No matching transactions',
                        subtitle: 'Try a different search or clear the filter.',
                        icon: Icons.search_off_rounded,
                      ),
                    );
                  }
                  final item =
                      Map<String, dynamic>.from(visibleEntries[index - 4]);
                  final deposit = _number(item['deposit']);
                  final withdrawal = _number(item['withdrawal']);
                  final isDeposit = deposit > 0 || withdrawal == 0;
                  final accent = isDeposit
                      ? const Color(0xFF078A6A)
                      : const Color(0xFFD25858);
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(
                          isDeposit
                              ? Icons.south_west_rounded
                              : Icons.north_east_rounded,
                          color: accent,
                        ),
                      ),
                      title: Text(
                          item['byWhom']?.toString().isNotEmpty == true
                              ? item['byWhom'].toString()
                              : 'General account',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      onTap: () => _showEntryDetails(item),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Date: ${item['date'] ?? '-'}'),
                            Text('Remarks: ${item['remarks'] ?? '-'}'),
                            Text('Payment mode: ${item['payMode'] ?? '-'}'),
                            Text('Entry by: ${item['entryBy'] ?? '-'}'),
                          ],
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                isDeposit
                                    ? '+₹${_formatAmount(deposit)}'
                                    : '-₹${_formatAmount(withdrawal)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: accent,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Bal ₹${_formatAmount(_number(item['balance']))}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          if (_canManageEntries)
                            PopupMenuButton<String>(
                              key: Key('manage-ledger-${item['__rowIndex']}'),
                              tooltip: 'Manage ledger entry',
                              onSelected: (action) {
                                switch (action) {
                                  case 'view':
                                    _showEntryDetails(item);
                                    break;
                                  case 'edit':
                                    _showEntryForm(item);
                                    break;
                                  case 'delete':
                                    _deleteEntry(item);
                                    break;
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'view',
                                  child: ListTile(
                                    leading: Icon(Icons.visibility_outlined),
                                    title: Text('View'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'edit',
                                  child: ListTile(
                                    leading: Icon(
                                      Icons.edit_outlined,
                                      color: portalEditColor,
                                    ),
                                    title: Text(
                                      'Edit',
                                      style: TextStyle(color: portalEditColor),
                                    ),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: ListTile(
                                    leading: Icon(
                                      Icons.delete_outline,
                                      color: portalDeleteColor,
                                    ),
                                    title: Text(
                                      'Delete',
                                      style:
                                          TextStyle(color: portalDeleteColor),
                                    ),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  bool _matchesSearch(Map entry) {
    if (_query.isEmpty) return true;
    return [
      entry['byWhom'],
      entry['remarks'],
      entry['payMode'],
      entry['entryBy'],
      entry['date'],
      entry['deposit'],
      entry['withdrawal'],
      entry['balance'],
    ].any((value) => value?.toString().toLowerCase().contains(_query) ?? false);
  }

  Future<void> _showAddEntry() async {
    await _showEntryForm();
  }

  Future<void> _showEntryForm([Map<String, dynamic>? entry]) async {
    if (entry != null && !_canManageEntries) return;
    try {
      final openingBalance = _openingBalanceFor(entry);
      final payload = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _LedgerEntryForm(
          entry: entry,
          openingBalance: openingBalance,
        ),
      );
      if (payload == null || !mounted) return;
      final saved = await withPortalLoading(
        context,
        label: entry == null ? 'Saving ledger entry' : 'Updating ledger entry',
        action: () =>
            widget.apiService.sendPostRequest(payload, widget.session),
      );
      if (!mounted) return;
      if (!saved) {
        throw const ApiException('Server did not save the entry.');
      }

      setState(_load);
      showPortalToast(
        context,
        entry == null ? 'Ledger entry added.' : 'Ledger entry updated.',
      );
    } on ApiException catch (error) {
      if (mounted) {
        showPortalToast(context, error.message, isError: true);
      }
    }
  }

  num _openingBalanceFor(Map<String, dynamic>? entry) {
    if (entry == null) {
      final latestEntry = _ledgerEntries.fold<Map<String, dynamic>?>(
        null,
        (latest, candidate) {
          final candidateRow = _number(candidate['__rowIndex']);
          final latestRow = latest == null ? -1 : _number(latest['__rowIndex']);
          return latest == null || candidateRow > latestRow
              ? candidate
              : latest;
        },
      );
      return _number(latestEntry?['balance']);
    }

    final rowIndex = _number(entry['__rowIndex']);
    final previousEntries = _ledgerEntries
        .where((candidate) => _number(candidate['__rowIndex']) < rowIndex);
    final previousEntry = previousEntries.fold<Map<String, dynamic>?>(
      null,
      (latest, candidate) {
        final candidateRow = _number(candidate['__rowIndex']);
        final latestRow = latest == null ? -1 : _number(latest['__rowIndex']);
        return latest == null || candidateRow > latestRow ? candidate : latest;
      },
    );
    if (previousEntry != null) return _number(previousEntry['balance']);
    return _number(entry['balance']) -
        _number(entry['deposit']) +
        _number(entry['withdrawal']);
  }

  Future<void> _showEntryDetails(Map<String, dynamic> entry) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ledger entry details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailLine('By whom', entry['byWhom']),
            _detailLine('Date', entry['date']),
            _detailLine('Remarks', entry['remarks']),
            _detailLine(
                'Deposit', '₹${_formatAmount(_number(entry['deposit']))}'),
            _detailLine(
              'Withdrawal',
              '₹${_formatAmount(_number(entry['withdrawal']))}',
            ),
            _detailLine(
                'Balance', '₹${_formatAmount(_number(entry['balance']))}'),
            _detailLine('Payment mode', entry['payMode']),
            _detailLine('Entry by', entry['entryBy']),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEntry(Map<String, dynamic> entry) async {
    if (!_canManageEntries) return;
    final rowIndex = entry['__rowIndex'];
    if (rowIndex == null) {
      _showLedgerMessage('Ledger record is missing its row ID.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete ledger entry?'),
        content: const Text(
          'This will permanently remove this ledger record.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-delete-ledger'),
            style: FilledButton.styleFrom(
              backgroundColor: portalDeleteColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final deleted = await withPortalLoading(
        context,
        label: 'Deleting ledger entry',
        action: () => widget.apiService.sendPostRequest({
          'action': 'deleteAmount',
          'rowIndex': rowIndex,
        }, widget.session),
      );
      if (!deleted) {
        throw const ApiException('The server did not delete this entry.');
      }
      if (mounted) {
        setState(_load);
        showPortalToast(
          context,
          'Ledger entry deleted.',
          isDestructive: true,
        );
      }
    } on ApiException catch (error) {
      if (mounted) _showLedgerMessage(error.message);
    }
  }

  void _showLedgerMessage(String message) {
    showPortalToast(context, message, isError: true);
  }
}

class _LedgerEntryForm extends StatefulWidget {
  const _LedgerEntryForm({
    this.entry,
    required this.openingBalance,
  });

  final Map<String, dynamic>? entry;
  final num openingBalance;

  @override
  State<_LedgerEntryForm> createState() => _LedgerEntryFormState();
}

class _LedgerEntryFormState extends State<_LedgerEntryForm> {
  static const _payModes = [
    'Cash',
    'G Pay',
    'Net Banking',
    'Others',
    'Pay Mode',
    'Phonepe',
    'QR',
    'UPI',
    'Bank',
  ];
  static const _entryByOptions = [
    'Bablu',
    'Mafidul',
    'Nur Mahammad',
    'Ashraful',
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _byWhom;
  late final TextEditingController _remarks;
  late final TextEditingController _deposit;
  late final TextEditingController _withdrawal;
  late final TextEditingController _balance;
  late String _payMode;
  late String _entryBy;
  late DateTime _date;
  String? _formError;

  bool get _editing => widget.entry != null;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _byWhom = TextEditingController(text: entry?['byWhom']?.toString() ?? '');
    _remarks = TextEditingController(text: entry?['remarks']?.toString() ?? '');
    _deposit = TextEditingController(text: entry?['deposit']?.toString() ?? '');
    _withdrawal =
        TextEditingController(text: entry?['withdrawal']?.toString() ?? '');
    _balance = TextEditingController(text: entry?['balance']?.toString() ?? '');
    if (!_editing) _balance.text = _formatAmount(widget.openingBalance);
    _deposit.addListener(_updateBalance);
    _withdrawal.addListener(_updateBalance);
    _updateBalance();
    _payMode = entry?['payMode']?.toString().isNotEmpty == true
        ? entry!['payMode'].toString()
        : 'Cash';
    _entryBy = entry?['entryBy']?.toString().isNotEmpty == true
        ? entry!['entryBy'].toString()
        : 'Mafidul';
    _date =
        DateTime.tryParse(entry?['date']?.toString() ?? '') ?? DateTime.now();
  }

  @override
  void dispose() {
    _byWhom.dispose();
    _remarks.dispose();
    _deposit.dispose();
    _withdrawal.dispose();
    _balance.dispose();
    super.dispose();
  }

  void _updateBalance() {
    final depositText = _deposit.text.trim();
    final withdrawalText = _withdrawal.text.trim();
    final deposit = depositText.isEmpty ? 0 : num.tryParse(depositText);
    final withdrawal =
        withdrawalText.isEmpty ? 0 : num.tryParse(withdrawalText);
    if (deposit == null || withdrawal == null) {
      _balance.clear();
      return;
    }
    final balance = widget.openingBalance + deposit - withdrawal;
    final formattedBalance = _formatAmount(balance);
    if (_balance.text != formattedBalance) _balance.text = formattedBalance;
  }

  void _save() {
    final depositText = _deposit.text.trim();
    final withdrawalText = _withdrawal.text.trim();
    final depositAmount = depositText.isEmpty ? 0 : num.tryParse(depositText);
    final withdrawalAmount =
        withdrawalText.isEmpty ? 0 : num.tryParse(withdrawalText);
    final balanceAmount = _balance.text.trim().isEmpty
        ? null
        : num.tryParse(_balance.text.trim());
    if (depositAmount == null ||
        withdrawalAmount == null ||
        depositAmount < 0 ||
        withdrawalAmount < 0 ||
        (depositAmount > 0) == (withdrawalAmount > 0) ||
        (_balance.text.trim().isNotEmpty &&
            (balanceAmount == null || balanceAmount < 0)) ||
        balanceAmount == null ||
        balanceAmount < 0) {
      setState(
        () => _formError =
            'Enter one positive deposit or withdrawal. The resulting balance must be zero or more.',
      );
      return;
    }

    Navigator.pop(context, {
      'action': _editing ? 'editAmount' : 'addAmount',
      if (_editing) 'rowIndex': widget.entry!['__rowIndex'],
      'date': DateFormat('yyyy-MM-dd').format(_date),
      'byWhom': _byWhom.text.trim(),
      'remarks': _remarks.text.trim(),
      'deposit': _deposit.text.trim(),
      'withdrawal': _withdrawal.text.trim(),
      'balance': _balance.text.trim(),
      'payMode': _payMode,
      'entryBy': _entryBy,
    });
  }

  @override
  Widget build(BuildContext context) {
    final balanceColor = Theme.of(context).colorScheme.error;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _editing ? 'Edit Ledger Entry' : 'New Ledger Entry',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('ledger-date'),
                  onPressed: () async {
                    final selected = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (selected != null) setState(() => _date = selected);
                  },
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(DateFormat('yyyy-MM-dd').format(_date)),
                ),
              ),
              const SizedBox(height: 12),
              _textField(
                _byWhom,
                'By Whom',
                key: const Key('ledger-by-whom'),
              ),
              _textField(
                _remarks,
                'Remarks',
                key: const Key('ledger-remarks'),
              ),
              Row(
                children: [
                  Expanded(
                    child: _textField(
                      _deposit,
                      'Deposit',
                      numeric: true,
                      key: const Key('ledger-deposit'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _textField(
                      _withdrawal,
                      'Withdrawal',
                      numeric: true,
                      key: const Key('ledger-withdrawal'),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextFormField(
                        key: const Key('ledger-balance'),
                        controller: _balance,
                        readOnly: true,
                        style: TextStyle(
                          color: balanceColor,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Updated Balance',
                          labelStyle: TextStyle(color: balanceColor),
                          prefixText: '₹ ',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: const Key('ledger-pay-mode'),
                      initialValue: _payMode,
                      items: [
                        ..._payModes,
                        if (!_payModes.contains(_payMode)) _payMode,
                      ]
                          .map((value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _payMode = value);
                      },
                      decoration: const InputDecoration(labelText: 'Pay Mode'),
                    ),
                  ),
                ],
              ),
              DropdownButtonFormField<String>(
                key: const Key('ledger-entry-by'),
                initialValue: _entryBy,
                items: [
                  ..._entryByOptions,
                  if (!_entryByOptions.contains(_entryBy)) _entryBy,
                ]
                    .map((value) => DropdownMenuItem(
                          value: value,
                          child: Text(value),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _entryBy = value);
                },
                decoration: const InputDecoration(labelText: 'Entry By'),
              ),
              if (_formError != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _formError!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('save-ledger-entry'),
                  onPressed: _save,
                  child: Text(_editing ? 'Save Changes' : 'Save Entry'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _textField(
  TextEditingController controller,
  String label, {
  bool numeric = false,
  Key? key,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      key: key,
      controller: controller,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(labelText: label),
    ),
  );
}

Widget _detailLine(String label, dynamic value) {
  final text = value?.toString().trim() ?? '';
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 105,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(child: Text(text.isEmpty ? '-' : text)),
      ],
    ),
  );
}

num _number(dynamic value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? 0;
}

String _formatAmount(num value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) =>
      PortalErrorState(message: message, onRetry: onRetry);
}
