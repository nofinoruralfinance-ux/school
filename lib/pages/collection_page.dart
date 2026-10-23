import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../widgets/portal_loading.dart';
import '../widgets/portal_widgets.dart';

class CollectionPage extends StatefulWidget {
  const CollectionPage({
    super.key,
    required this.apiService,
    required this.session,
    required this.type,
    required this.sheetName,
    required this.periodsCount,
  });

  final ApiService apiService;
  final AuthSession session;
  final String type;
  final String sheetName;
  final int periodsCount;

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  late Future<dynamic> _future;
  final _searchController = TextEditingController();
  final _entryNameController = TextEditingController();
  final _entryAmountController = TextEditingController();
  String _query = '';
  bool _isRefreshing = false;

  bool get _isMember => widget.session.role.toLowerCase() == 'member';
  bool get _canManageEntries =>
      widget.session.hasPermission('collection_manage');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _entryNameController.dispose();
    _entryAmountController.dispose();
    super.dispose();
  }

  void _load() {
    _future = widget.apiService.fetchSheetData(
      'get${widget.type}',
      widget.session,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _isRefreshing = true;
      _load();
    });
    try {
      await _future;
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _canManageEntries
          ? FloatingActionButton.extended(
              heroTag: null,
              key: const Key('add-collection-entry'),
              onPressed: _showAddEntry,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add'),
            )
          : null,
      body: PortalGradientBackground(
        child: Column(
          children: [
            PortalPageHeader(
              title: '${widget.type} collection',
              subtitle: _isMember
                  ? 'Your individual contribution and payment history.'
                  : 'Member contributions and payment history.',
              icon: widget.type == 'Daily'
                  ? Icons.today_rounded
                  : widget.type == 'Weekly'
                      ? Icons.calendar_view_week_rounded
                      : Icons.calendar_month_rounded,
            ),
            if (!_isMember)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search members',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.clear),
                          ),
                  ),
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                ),
              ),
            Expanded(
              child: FutureBuilder<dynamic>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return PortalLoadingState(
                      label: 'Loading ${widget.type.toLowerCase()} collection',
                    );
                  }
                  if (snapshot.hasError || snapshot.data is! List) {
                    return _ErrorView(
                      message: snapshot.error?.toString() ??
                          'Failed to load ${widget.type} collection.',
                      onRetry: () => setState(_load),
                    );
                  }

                  final members = (snapshot.data as List)
                      .whereType<Map>()
                      .where((member) =>
                          !_isMember ||
                          widget.session
                              .matchesMemberName(member['memberName']))
                      .where((member) => (member['memberName'] ?? '')
                          .toString()
                          .toLowerCase()
                          .contains(_query))
                      .toList();
                  if (members.isEmpty) {
                    return PortalEmptyState(
                      title: _query.isEmpty
                          ? 'No collection entries yet'
                          : 'No members found',
                      subtitle: _query.isEmpty
                          ? _isMember
                              ? 'Your collection records will appear here.'
                              : 'Member payment records will appear here.'
                          : 'Try another name or clear your search.',
                      icon: _query.isEmpty
                          ? Icons.groups_2_outlined
                          : Icons.search_off_rounded,
                    );
                  }
                  final totalMarked = members.fold<int>(
                    0,
                    (total, member) =>
                        total +
                        (member['periods'] is List
                            ? (member['periods'] as List)
                                .where(
                                    (period) => period == true || period == 1)
                                .length
                            : 0),
                  );
                  final totalReceived = members.fold<num>(
                    0,
                    (total, member) =>
                        total +
                        (num.tryParse('${member['totalReceived']}') ?? 0),
                  );
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
                                label: _isMember ? 'My entries' : 'Members',
                                value: '${members.length}',
                                icon: Icons.groups_2_rounded,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: PortalMetricCard(
                                label: 'Amount received',
                                value: NumberFormat.currency(
                                  locale: 'en_IN',
                                  symbol: '₹',
                                  decimalDigits: 0,
                                ).format(totalReceived),
                                icon: Icons.currency_rupee_rounded,
                                accent: const Color(0xFF078A6A),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Text(
                              _isMember ? 'My records' : 'Members',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const Spacer(),
                            Text(
                              '$totalMarked '
                              '${totalMarked == 1 ? 'payment' : 'payments'} marked',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...members.map((rawMember) {
                          final member = Map<String, dynamic>.from(rawMember);
                          return Card(
                            child: ExpansionTile(
                              leading: CircleAvatar(
                                child: Text(_initial(member['memberName'])),
                              ),
                              title: Text(
                                member['memberName']?.toString() ??
                                    'Unknown member',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                'Start: ${member['date'] ?? '-'} | '
                                'Rate: ₹${member['depAmt'] ?? 0}\n'
                                'Paid: ${member['totalCount'] ?? 0} $_unit\n',
                                key: Key(
                                  'collection-grand-total-${member['rowIndex']}',
                                ),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              trailing: Text(
                                '₹${member['totalReceived'] ?? 0}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade400,
                                ),
                              ),
                              children: [
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 0, 12, 8),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      if (_canManageEntries) ...[
                                        OutlinedButton.icon(
                                          key: Key(
                                            'edit-collection-${member['rowIndex']}',
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: portalEditColor,
                                            side: const BorderSide(
                                              color: portalEditColor,
                                            ),
                                          ),
                                          onPressed: () =>
                                              _showEntryForm(member),
                                          icon: const Icon(Icons.edit_outlined),
                                          label: const Text('Edit'),
                                        ),
                                        const SizedBox(width: 8),
                                        OutlinedButton.icon(
                                          key: Key(
                                            'delete-collection-${member['rowIndex']}',
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: portalDeleteColor,
                                            side: const BorderSide(
                                              color: portalDeleteColor,
                                            ),
                                          ),
                                          onPressed: () => _deleteEntry(member),
                                          icon:
                                              const Icon(Icons.delete_outline),
                                          label: const Text('Delete'),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                // Payment schedule button opens popup
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 0, 12, 8),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.tonalIcon(
                                      key: Key(
                                        'payment-schedule-${member['rowIndex']}',
                                      ),
                                      onPressed: () =>
                                          _openPaymentSchedulePopup(member),
                                      icon: const Icon(
                                          Icons.event_available_rounded),
                                      label:
                                          const Text('View payment schedule'),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ),
                          );
                        }),
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

  Future<void> _showAddEntry() async {
    if (!_canManageEntries) return;
    await _showEntryForm();
  }

  // Popup page for payment schedule
  Future<void> _openPaymentSchedulePopup(Map<String, dynamic> member) async {
    final rowIndex = member['rowIndex'];
    if (rowIndex == null) {
      _showMessage('Member record is missing its row ID.', isError: true);
      return;
    }

    var periods = List<dynamic>.from(
      member['periods'] is List ? member['periods'] as List : [],
    );
    final localPending = <int>{};
    var loading = false;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final marked = periods.where((p) => p == true || p == 1).length;
          final total = periods.length;
          final progress = total == 0 ? 0.0 : marked / total;

          return AlertDialog(
            title: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Payment schedule',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed:
                      loading ? null : () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      member['memberName']?.toString() ?? 'Unknown member',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Start: ${member['date'] ?? '-'} | '
                      'Rate: ₹${member['depAmt'] ?? 0} / ${_periodUnit(widget.type)}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '$marked / $total',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (dialogError != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .errorContainer
                              .withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          dialogError!,
                          key: const Key('payment-schedule-error'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (periods.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No periods configured.'),
                      )
                    else
                      GridView.count(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 2.1,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: List.generate(periods.length, (i) {
                          final isPaid = periods[i] == true || periods[i] == 1;
                          final isPending = localPending.contains(i);
                          return FilterChip(
                            key: Key('schedule-chip-${member['rowIndex']}-$i'),
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isPending) ...[
                                  const PortalOrbitLoader(
                                    size: 12,
                                    semanticsLabel: 'Updating payment',
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Flexible(
                                  child: Text(
                                    '${widget.type[0]}${i + 1}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            selected: isPaid,
                            selectedColor: Theme.of(dialogContext)
                                .colorScheme
                                .primaryContainer,
                            checkmarkColor: Theme.of(dialogContext)
                                .colorScheme
                                .onPrimaryContainer,
                            labelStyle: TextStyle(
                              color: isPaid
                                  ? Theme.of(dialogContext)
                                      .colorScheme
                                      .onPrimaryContainer
                                  : null,
                              fontWeight: isPaid ? FontWeight.w700 : null,
                            ),
                            showCheckmark: !isPending,
                            onSelected:
                                !_canManageEntries || isPending || loading
                                    ? null
                                    : (_) => _togglePeriodInPopup(
                                          dialogContext: dialogContext,
                                          setDialogState: setDialogState,
                                          member: member,
                                          periods: periods,
                                          index: i,
                                          localPending: localPending,
                                          setLocalLoading: (v) => loading = v,
                                          setError: (msg) => dialogError = msg,
                                          onPeriodsChanged: (updated) =>
                                              periods = updated,
                                        ),
                          );
                        }),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    loading ? null : () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );

    if (mounted) {
      setState(_load);
    }
  }

  Future<void> _togglePeriodInPopup({
    required BuildContext dialogContext,
    required StateSetter setDialogState,
    required Map<String, dynamic> member,
    required List<dynamic> periods,
    required int index,
    required Set<int> localPending,
    required ValueChanged<bool> setLocalLoading,
    required ValueChanged<String?> setError,
    required ValueChanged<List<dynamic>> onPeriodsChanged,
  }) async {
    if (!_canManageEntries) return;
    final rowIndex = member['rowIndex'];
    if (rowIndex == null) return;

    final wasPaid = periods.length > index &&
        (periods[index] == true || periods[index] == 1);

    setDialogState(() {
      localPending.add(index);
      setError(null);
    });
    setLocalLoading(true);

    try {
      final saved = await widget.apiService.sendPostRequest({
        'action': 'toggleCollection',
        'sheetName': widget.sheetName,
        'rowIndex': rowIndex,
        'periodIndex': index + 1,
      }, widget.session);
      if (!saved) {
        throw const ApiException('The server did not save this change.');
      }

      // Update local list optimistically
      final updated = List<dynamic>.from(periods);
      while (updated.length <= index) {
        updated.add(false);
      }
      updated[index] = !wasPaid;
      onPeriodsChanged(updated);

      // Keep member map in sync so toggles stay consistent
      member['periods'] = updated;

      if (mounted && dialogContext.mounted) {
        setDialogState(() {
          localPending.remove(index);
        });
        setLocalLoading(false);
        showPortalToast(
          dialogContext,
          wasPaid ? 'Payment unmarked.' : 'Payment marked.',
          isError: false,
        );
      }
    } on ApiException catch (error) {
      if (mounted && dialogContext.mounted) {
        setDialogState(() {
          localPending.remove(index);
          setError(error.message);
        });
        setLocalLoading(false);
        showPortalToast(dialogContext, error.message, isError: true);
      }
    } catch (error) {
      if (mounted && dialogContext.mounted) {
        setDialogState(() {
          localPending.remove(index);
          setError('Unexpected error: $error');
        });
        setLocalLoading(false);
        showPortalToast(dialogContext, 'Unexpected error.', isError: true);
      }
    }
  }

  Future<void> _showEntryForm([Map<String, dynamic>? member]) async {
    if (!_canManageEntries) return;
    final formKey = GlobalKey<FormState>();
    final editing = member != null;
    final rowIndex = member?['rowIndex'];
    if (editing && rowIndex == null) {
      _showMessage('Member record is missing its row ID.', isError: true);
      return;
    }
    _entryNameController.text = member?['memberName']?.toString() ?? '';
    _entryAmountController.text = member?['depAmt']?.toString() ?? '';
    var startDate = _parseDate(member?['date']) ?? DateTime.now();
    var saving = false;
    String? errorMessage;

    final configuredPeriods = member?['periods'];
    var formPeriods = List<dynamic>.from(
      editing
          ? configuredPeriods is List
              ? configuredPeriods
              : const []
          : List<bool>.filled(widget.periodsCount, false),
    );
    final formPending = <int>{};

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            '${editing ? 'Edit' : 'Add'} ${widget.type.toLowerCase()} entry',
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        key: const Key('collection-start-date'),
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
                                  setDialogState(() => startDate = selected);
                                }
                              },
                        icon: const Icon(Icons.calendar_today_rounded),
                        label: Text(
                          'Start date: ${DateFormat('yyyy-MM-dd').format(startDate)}',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('collection-member-name'),
                      controller: _entryNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration:
                          const InputDecoration(labelText: 'Member name'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Enter a member name'
                              : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const Key('collection-amount'),
                      controller: _entryAmountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Amount per ${_periodUnit(widget.type)}',
                        prefixText: '₹ ',
                      ),
                      validator: _validatePositiveAmount,
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Payment schedule',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (!editing)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Select the periods that are already paid.',
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (formPeriods.isEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'No periods configured for this member yet.',
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    else
                      GridView.count(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 2.1,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: List.generate(formPeriods.length, (i) {
                          final isPaid =
                              formPeriods[i] == true || formPeriods[i] == 1;
                          final isPending = formPending.contains(i);
                          return FilterChip(
                            key: Key('form-schedule-chip-$i'),
                            label: isPending
                                ? const PortalOrbitLoader(
                                    size: 14,
                                    semanticsLabel: 'Updating payment',
                                  )
                                : Text('${widget.type[0]}${i + 1}'),
                            selected: isPaid,
                            selectedColor:
                                Theme.of(context).colorScheme.primaryContainer,
                            checkmarkColor: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                            labelStyle: TextStyle(
                              color: isPaid
                                  ? Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer
                                  : null,
                              fontWeight: isPaid ? FontWeight.w700 : null,
                            ),
                            showCheckmark: !isPending,
                            onSelected: !_canManageEntries ||
                                    saving ||
                                    (editing && isPending)
                                ? null
                                : (_) async {
                                    if (!editing) {
                                      setDialogState(
                                        () => formPeriods[i] = !isPaid,
                                      );
                                      return;
                                    }
                                    setDialogState(() => formPending.add(i));
                                    try {
                                      final saved = await widget.apiService
                                          .sendPostRequest({
                                        'action': 'toggleCollection',
                                        'sheetName': widget.sheetName,
                                        'rowIndex': rowIndex,
                                        'periodIndex': i + 1,
                                      }, widget.session);
                                      if (!saved) {
                                        throw const ApiException(
                                            'The server did not save this change.');
                                      }
                                      setDialogState(() {
                                        formPeriods[i] = !isPaid;
                                        formPending.remove(i);
                                      });
                                    } on ApiException catch (error) {
                                      setDialogState(
                                          () => formPending.remove(i));
                                      if (dialogContext.mounted) {
                                        showPortalToast(
                                          dialogContext,
                                          error.message,
                                          isError: true,
                                        );
                                      }
                                    } finally {
                                      setDialogState(
                                          () => formPending.remove(i));
                                    }
                                  },
                          );
                        }),
                      ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorMessage!,
                        key: const Key('collection-entry-error'),
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
              key: const Key('save-collection-entry'),
              onPressed: saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() {
                        saving = true;
                        errorMessage = null;
                      });
                      try {
                        final saved = await widget.apiService.sendPostRequest({
                          'action':
                              editing ? 'editCollection' : 'addCollection',
                          'sheetName': widget.sheetName,
                          if (editing) 'rowIndex': rowIndex,
                          'date': DateFormat('yyyy-MM-dd').format(startDate),
                          'memberName': _entryNameController.text.trim(),
                          'depAmt':
                              double.parse(_entryAmountController.text.trim()),
                          if (!editing) 'periods': List<bool>.from(formPeriods),
                        }, widget.session);
                        if (!saved) {
                          throw const ApiException(
                            'The server did not save this entry.',
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
                          errorMessage = 'Unexpected error: $error';
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: PortalOrbitLoader(
                        size: 18,
                        semanticsLabel: 'Saving collection entry',
                      ),
                    )
                  : Text(editing ? 'Save changes' : 'Save entry'),
            ),
          ],
        ),
      ),
    );

    if (created == true && mounted) {
      setState(_load);
      _showMessage(
        editing ? 'Collection entry updated.' : 'Collection entry added.',
      );
    }
  }

  Future<void> _deleteEntry(Map<String, dynamic> member) async {
    if (!_canManageEntries) return;
    final rowIndex = member['rowIndex'];
    if (rowIndex == null) {
      _showMessage('Member record is missing its row ID.', isError: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete collection entry?'),
        content: Text(
          'This will permanently delete ${member['memberName'] ?? 'this member'} '
          'and its payment history from this collection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-delete-collection'),
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

    try {
      final deleted = await withPortalLoading(
        context,
        label: 'Deleting collection entry',
        action: () => widget.apiService.sendPostRequest({
          'action': 'deleteCollection',
          'sheetName': widget.sheetName,
          'rowIndex': rowIndex,
        }, widget.session),
      );
      if (!deleted) {
        throw const ApiException('The server did not delete this entry.');
      }
      if (mounted) {
        setState(_load);
        _showMessage('Collection entry deleted.', isDestructive: true);
      }
    } on ApiException catch (error) {
      if (mounted) _showMessage(error.message, isError: true);
    }
  }

  DateTime? _parseDate(dynamic value) {
    final dateText = value?.toString();
    if (dateText == null) return null;
    try {
      return DateFormat('yyyy-MM-dd').parseStrict(dateText);
    } on FormatException {
      return null;
    }
  }

  void _showMessage(
    String message, {
    bool isError = false,
    bool isDestructive = false,
  }) {
    showPortalToast(
      context,
      message,
      isError: isError,
      isDestructive: isDestructive,
    );
  }

  String? _validatePositiveAmount(String? value) {
    final amount = double.tryParse(value?.trim() ?? '');
    if (amount == null || !amount.isFinite || amount <= 0) {
      return 'Enter an amount greater than zero';
    }
    return null;
  }

  String _periodUnit(String type) {
    switch (type) {
      case 'Daily':
        return 'day';
      case 'Weekly':
        return 'week';
      default:
        return 'month';
    }
  }

  String get _unit {
    switch (widget.type) {
      case 'Daily':
        return 'days';
      case 'Weekly':
        return 'weeks';
      default:
        return 'months';
    }
  }

  String _initial(dynamic value) {
    final name = value?.toString() ?? '';
    return name.isEmpty ? 'M' : name.characters.first.toUpperCase();
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
}
