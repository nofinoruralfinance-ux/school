// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/portal_loading.dart';
import '../widgets/portal_widgets.dart';

class RolesPermissionsPage extends StatefulWidget {
  const RolesPermissionsPage({
    super.key,
    required this.apiService,
    required this.session,
  });

  final ApiService apiService;
  final AuthSession session;

  @override
  State<RolesPermissionsPage> createState() => _RolesPermissionsPageState();
}

class _RolesPermissionsPageState extends State<RolesPermissionsPage> {
  static const _permissionLabels = {
    'shared_data_read': (
      'View shared data',
      'Read the shared ledger, collections, and user directory.',
    ),
    'own_collection_read': (
      'View own collections',
      'Read Daily, Weekly, and Monthly rows matching the account name.',
    ),
    'collection_manage': (
      'Manage collections',
      'Add, edit, and delete collection records and mark collection payments.',
    ),
    'deposit_view': (
      'View deposit accounts',
      'Read FD, RD, and DRD accounts allowed by the account cadence.',
    ),
    'deposit_manage': (
      'Manage deposit accounts',
      'Create and edit deposit accounts, track payments, and delete records.',
    ),
    'ledger_manage': (
      'Manage ledger',
      'Add, edit, and delete ledger entries.',
    ),
    'user_manage': (
      'Manage user accounts',
      'Add, edit, and delete accounts. Only Admins can assign roles.',
    ),
  };

  late Future<Map<String, Map<String, bool>>> _future;
  Map<String, Map<String, bool>>? _permissions;
  Map<String, Map<String, bool>>? _originalPermissions;
  bool _saving = false;

  bool get _isAdmin => widget.session.role.toLowerCase() == 'admin';

  bool get _hasChanges {
    final current = _permissions;
    final original = _originalPermissions;
    if (current == null || original == null) return false;
    for (final role in current.keys) {
      for (final key in current[role]!.keys) {
        if (current[role]![key] != original[role]?[key]) return true;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _future = _loadPermissions();
  }

  Future<Map<String, Map<String, bool>>> _loadPermissions() async {
    final data = await widget.apiService.fetchRolePermissions(widget.session);
    // Deep copy so we can compare changes
    final copy = <String, Map<String, bool>>{};
    data.forEach((role, perms) {
      copy[role] = Map<String, bool>.from(perms);
    });
    _originalPermissions = copy;
    return data;
  }

  Future<void> _reload() async {
    setState(() {
      _permissions = null;
      _originalPermissions = null;
      _future = _loadPermissions();
    });
    try {
      await _future;
    } catch (_) {}
  }

  Future<void> _save() async {
    final permissions = _permissions;
    if (!_isAdmin || _saving || permissions == null || !_hasChanges) return;
    setState(() => _saving = true);
    try {
      await widget.apiService.saveRolePermissions(permissions, widget.session);
      // Update original so changes reset
      final copy = <String, Map<String, bool>>{};
      permissions.forEach((role, perms) {
        copy[role] = Map<String, bool>.from(perms);
      });
      _originalPermissions = copy;
      if (!mounted) return;
      showPortalToast(
        context,
        'Permissions saved. Other users should sign in again to refresh access.',
      );
    } on ApiException catch (error) {
      if (mounted) showPortalToast(context, error.message, isError: true);
    } catch (e) {
      if (mounted) {
        showPortalToast(context, 'Failed to save: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _setPermission(String role, String key, bool enabled) {
    final permissions = _permissions;
    if (!_isAdmin || _saving || permissions == null) return;
    setState(() => permissions[role]![key] = enabled);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return PortalErrorState(
        message: 'Only Admins can manage role permissions.',
        onRetry: _reload,
      );
    }

    final theme = Theme.of(context);

    return PortalGradientBackground(
      child: FutureBuilder<Map<String, Map<String, bool>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const PortalLoadingState(
              label: 'Loading permissions',
            );
          }
          if (snapshot.hasError) {
            return PortalErrorState(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }

          if (_permissions == null && snapshot.hasData) {
            _permissions = snapshot.data;
          }
          final permissions = _permissions;
          if (permissions == null) {
            return PortalErrorState(
              message: 'No permission data available.',
              onRetry: _reload,
            );
          }

          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                    children: [
                      const PortalPageHeader(
                        title: 'Roles & Permissions',
                        subtitle:
                            'Configure role access. Member accounts are view-only.',
                        icon: Icons.admin_panel_settings_rounded,
                      ),
                      const SizedBox(height: 8),
                      _AdminInfoCard(theme: theme),
                      for (final role in ['Collector', 'Member']) ...[
                        const SizedBox(height: 20),
                        _RoleHeader(
                          role: role,
                          enabledCount: _permissionLabels.keys
                              .where((k) => permissions[role]![k] ?? false)
                              .length,
                          totalCount: _permissionLabels.length,
                          theme: theme,
                        ),
                        const SizedBox(height: 8),
                        for (final entry in _permissionLabels.entries)
                          _PermissionCard(
                            role: role,
                            permissionKey: entry.key,
                            title: entry.value.$1,
                            subtitle: entry.value.$2,
                            value: permissions[role]![entry.key] ?? false,
                            enabled: !_saving &&
                                (role == 'Collector' ||
                                    entry.key == 'shared_data_read' ||
                                    entry.key == 'own_collection_read' ||
                                    entry.key == 'deposit_view'),
                            onChanged: (enabled) =>
                                _setPermission(role, entry.key, enabled),
                            theme: theme,
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              _SaveBar(
                saving: _saving,
                hasChanges: _hasChanges,
                onSave: _save,
                theme: theme,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AdminInfoCard extends StatelessWidget {
  const _AdminInfoCard({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer.withOpacity(0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.15)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.verified_user_rounded,
                color: theme.colorScheme.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Admin access is always enabled',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Only Admins can change permissions or assign account roles.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleHeader extends StatelessWidget {
  const _RoleHeader({
    required this.role,
    required this.enabledCount,
    required this.totalCount,
    required this.theme,
  });

  final String role;
  final int enabledCount;
  final int totalCount;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final isCollector = role == 'Collector';
    final roleColor = portalRoleColor(role);
    return Row(
      children: [
        Icon(
          isCollector ? Icons.engineering_rounded : Icons.person_rounded,
          size: 20,
          color: roleColor,
        ),
        const SizedBox(width: 8),
        Text(
          role,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 10),
        Container(
          key: Key('role-permission-color-${role.toLowerCase()}'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: roleColor.withValues(alpha: .12),
            border: Border.all(color: roleColor.withValues(alpha: .25)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$enabledCount / $totalCount',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: roleColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.role,
    required this.permissionKey,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.theme,
  });

  final String role;
  final String permissionKey;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final roleColor = portalRoleColor(role);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: value
              ? roleColor.withValues(alpha: .38)
              : theme.dividerColor.withOpacity(0.4),
        ),
      ),
      color: value ? roleColor.withValues(alpha: .035) : theme.cardColor,
      child: SwitchListTile.adaptive(
        key: Key('permission-${role.toLowerCase()}-$permissionKey'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.3,
            ),
          ),
        ),
        value: value,
        activeTrackColor: roleColor,
        activeThumbColor: theme.colorScheme.onPrimary,
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.saving,
    required this.hasChanges,
    required this.onSave,
    required this.theme,
  });

  final bool saving;
  final bool hasChanges;
  final VoidCallback onSave;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            key: const Key('save-role-permissions'),
            onPressed: (saving || !hasChanges) ? null : onSave,
            icon: saving
                ? const PortalOrbitLoader(
                    size: 18,
                    semanticsLabel: 'Saving permissions',
                  )
                : const Icon(Icons.save_rounded),
            label: Text(
              saving
                  ? 'Saving…'
                  : hasChanges
                      ? 'Save permissions'
                      : 'No changes to save',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}
