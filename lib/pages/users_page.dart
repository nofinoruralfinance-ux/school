import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../widgets/portal_loading.dart';
import '../widgets/portal_widgets.dart';
import '../widgets/profile_image.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({
    super.key,
    required this.apiService,
    required this.session,
  });

  final ApiService apiService;
  final AuthSession session;

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  late Future<dynamic> _future;
  String _selectedRole = 'Member';
  String _searchQuery = '';
  final _searchController = TextEditingController();

  Widget _userAvatar(BuildContext context, String name, String imageUrl) {
    final fallback = Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Text(
        name.isEmpty ? 'U' : name[0].toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    final imageProvider = profileImageProvider(imageUrl);
    if (imageProvider == null) {
      return fallback;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: Image(
        image: imageProvider,
        width: 46,
        height: 46,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }

  bool get _isAdmin => widget.session.role.toLowerCase() == 'admin';
  bool get _canManageUsers => widget.session.hasPermission('user_manage');

  bool _reportAccessEnabled(dynamic value) {
    if (value is bool) return value;
    if (value == null || value == '') return true;
    return value.toString().toLowerCase() == 'true';
  }

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
    _future = widget.apiService.fetchSheetData('getUsers', widget.session);
  }

  Future<void> _editUser({Map? user, String? role}) async {
    if (!_canManageUsers) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _UserEditor(
        apiService: widget.apiService,
        session: widget.session,
        user: user,
        initialRole: role,
      ),
    );
    if (saved != true || !mounted) return;
    setState(_load);
    showPortalToast(
      context,
      user == null ? 'User added.' : 'User updated.',
    );
  }

  Future<void> _deleteUser(Map user) async {
    if (!_canManageUsers) return;
    final id = user['id']?.toString() ?? '';
    if (id.isEmpty) {
      showPortalToast(
        context,
        'This user has no ID and cannot be deleted.',
        isError: true,
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete user?'),
        content: Text(
          'Delete ${user['name'] ?? user['email'] ?? 'this user'}? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-delete-user'),
            style: FilledButton.styleFrom(
              backgroundColor: portalDeleteColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final deleted = await withPortalLoading(
        context,
        label: 'Deleting user',
        action: () => widget.apiService.sendPostRequest({
          'action': 'deleteUser',
          'userId': id,
        }, widget.session),
      );
      if (!deleted) {
        throw const ApiException('The server did not delete this user.');
      }
      if (!mounted) return;
      setState(_load);
      showPortalToast(context, 'User deleted.', isDestructive: true);
    } on ApiException catch (error) {
      if (mounted) {
        showPortalToast(context, error.message, isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _canManageUsers
          ? FloatingActionButton.extended(
              heroTag: null,
              key: const Key('add-user'),
              onPressed: () => _editUser(role: _selectedRole),
              tooltip: 'Add $_selectedRole',
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: Text('Add $_selectedRole'),
            )
          : null,
      body: PortalGradientBackground(
        child: Column(
          children: [
            PortalPageHeader(
              title: 'People',
              subtitle: _canManageUsers
                  ? 'Manage portal access and team roles.'
                  : 'People with access to this portal.',
              icon: Icons.groups_rounded,
            ),
            Expanded(
              child: FutureBuilder<dynamic>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const PortalLoadingState(label: 'Loading accounts');
                  }
                  if (snapshot.hasError || snapshot.data is! List) {
                    return PortalErrorState(
                      message:
                          snapshot.error?.toString() ?? 'Failed to load users.',
                      onRetry: () => setState(_load),
                    );
                  }
                  final users = snapshot.data as List;
                  final roleCounts = {
                    for (final role in ['Admin', 'Collector', 'Member'])
                      role: users
                          .whereType<Map>()
                          .where((user) =>
                              user['role']?.toString().toLowerCase() ==
                              role.toLowerCase())
                          .length,
                  };
                  final visibleUsers = users
                      .whereType<Map>()
                      .where((user) =>
                          user['role']?.toString().toLowerCase() ==
                          _selectedRole.toLowerCase())
                      .where((user) {
                    final query = _searchQuery.trim().toLowerCase();
                    if (query.isEmpty) return true;
                    final name = user['name']?.toString().toLowerCase() ?? '';
                    final email = user['email']?.toString().toLowerCase() ?? '';
                    final accountNo =
                        user['accountNo']?.toString().toLowerCase() ?? '';
                    return name.contains(query) ||
                        email.contains(query) ||
                        accountNo.contains(query);
                  }).toList(growable: false);
                  return RefreshIndicator(
                    onRefresh: () async {
                      setState(_load);
                      await _future;
                    },
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 180),
                      children: [
                        _UsersOverviewCard(
                          total: users.length,
                          roleCounts: roleCounts,
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Text(
                              'Directory',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const Spacer(),
                            Text(
                              '${visibleUsers.length} ${_selectedRole.toLowerCase()}'
                              '${visibleUsers.length == 1 ? '' : 's'}',
                              key: const Key('users-visible-count'),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: portalRoleColor(_selectedRole),
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          key: const Key('users-search'),
                          controller: _searchController,
                          onChanged: (value) =>
                              setState(() => _searchQuery = value),
                          decoration: InputDecoration(
                            hintText: 'Search by name or email',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _searchQuery.isEmpty
                                ? null
                                : IconButton(
                                    key: const Key('users-search-clear'),
                                    tooltip: 'Clear search',
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                            filled: true,
                            fillColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerLow,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                              ),
                            ),
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          key: const Key('user-role-tabs'),
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final role in _isAdmin
                                ? const ['Admin', 'Collector', 'Member']
                                : const ['Member'])
                              Builder(
                                builder: (context) {
                                  final selected = _selectedRole == role;
                                  final roleColor = portalRoleColor(role);
                                  return FilterChip(
                                    key: Key(
                                      'user-role-chip-${role.toLowerCase()}',
                                    ),
                                    selected: selected,
                                    showCheckmark: false,
                                    avatar: Icon(
                                      switch (role) {
                                        'Admin' =>
                                          Icons.admin_panel_settings_rounded,
                                        'Collector' =>
                                          Icons.engineering_rounded,
                                        _ => Icons.person_rounded,
                                      },
                                      size: 18,
                                      color: selected
                                          ? roleColor
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                    ),
                                    label: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          role,
                                          key: Key(
                                            'user-role-tab-${role.toLowerCase()}',
                                          ),
                                        ),
                                        const SizedBox(width: 7),
                                        Container(
                                          key: Key(
                                            'user-role-count-${role.toLowerCase()}',
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: selected
                                                ? roleColor.withValues(
                                                    alpha: .13,
                                                  )
                                                : Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHighest,
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            '${roleCounts[role]}',
                                            style: TextStyle(
                                              color: selected
                                                  ? roleColor
                                                  : Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerLow,
                                    selectedColor:
                                        roleColor.withValues(alpha: .10),
                                    side: BorderSide(
                                      color: selected
                                          ? roleColor.withValues(alpha: .65)
                                          : Theme.of(context)
                                              .colorScheme
                                              .outlineVariant,
                                      width: selected ? 1.3 : 1,
                                    ),
                                    onSelected: !_isAdmin
                                        ? null
                                        : (_) => setState(
                                              () => _selectedRole = role,
                                            ),
                                    tooltip:
                                        '${roleCounts[role]} $role accounts',
                                  );
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (visibleUsers.isEmpty)
                          PortalEmptyState(
                            title: _searchQuery.trim().isNotEmpty
                                ? 'No matching accounts'
                                : 'No $_selectedRole accounts',
                            subtitle: _searchQuery.trim().isNotEmpty
                                ? 'Try another name or email, or clear your search.'
                                : _canManageUsers
                                    ? 'Add a $_selectedRole account to let them log in individually.'
                                    : '$_selectedRole accounts will appear here.',
                            icon: _searchQuery.trim().isNotEmpty
                                ? Icons.search_off_rounded
                                : Icons.person_search_outlined,
                          ),
                        ...visibleUsers.map((user) {
                          final id = user['id']?.toString() ?? '';
                          final name = user['name']?.toString() ?? 'Unnamed';
                          return Card(
                            clipBehavior: Clip.antiAlias,
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              leading: _userAvatar(
                                context,
                                name,
                                user['profileImageUrl']?.toString() ?? '',
                              ),
                              title: Text(
                                name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Account No: ${user['accountNo']?.toString().isNotEmpty == true ? user['accountNo'] : 'Not assigned'}',
                                    key: Key('user-account-number-$id'),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(user['email']?.toString() ??
                                      'No email specified'),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Builder(
                                        builder: (context) {
                                          final role =
                                              user['role']?.toString() ??
                                                  'Member';
                                          final roleColor =
                                              portalRoleColor(role);
                                          return Container(
                                            key: Key('user-role-badge-$id'),
                                            margin:
                                                const EdgeInsets.only(top: 4),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: roleColor.withValues(
                                                alpha: .11,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                color: roleColor.withValues(
                                                  alpha: .25,
                                                ),
                                              ),
                                            ),
                                            child: Text(
                                              role,
                                              style: TextStyle(
                                                color: roleColor,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      if (user['role']
                                              ?.toString()
                                              .toLowerCase() ==
                                          'member')
                                        for (final report in [
                                          ('D', 'dailyAccess'),
                                          ('W', 'weeklyAccess'),
                                          ('M', 'monthlyAccess'),
                                        ])
                                          _ReportAccessBadge(
                                            label: report.$1,
                                            enabled: _reportAccessEnabled(
                                              user[report.$2],
                                            ),
                                          ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: _canManageUsers
                                  ? PopupMenuButton<String>(
                                      key: Key('manage-user-$id'),
                                      tooltip: 'Manage user',
                                      onSelected: (action) {
                                        if (action == 'edit') {
                                          _editUser(user: user);
                                        } else {
                                          _deleteUser(user);
                                        }
                                      },
                                      itemBuilder: (context) => const [
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: ListTile(
                                            leading: Icon(
                                              Icons.edit_outlined,
                                              color: portalEditColor,
                                            ),
                                            title: Text(
                                              'Edit',
                                              style: TextStyle(
                                                color: portalEditColor,
                                              ),
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
                                              style: TextStyle(
                                                color: portalDeleteColor,
                                              ),
                                            ),
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                        ),
                                      ],
                                    )
                                  : null,
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
}

class _ReportAccessBadge extends StatelessWidget {
  const _ReportAccessBadge({
    required this.label,
    required this.enabled,
  });

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? Theme.of(context).colorScheme.tertiary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Text(
        '$label ${enabled ? 'On' : 'Off'}',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _UsersOverviewCard extends StatelessWidget {
  const _UsersOverviewCard({
    required this.total,
    required this.roleCounts,
  });

  final int total;
  final Map<String, int> roleCounts;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final roles = [
      ('Admin', Icons.admin_panel_settings_rounded),
      ('Collector', Icons.engineering_rounded),
      ('Member', Icons.person_rounded),
    ];
    return Container(
      key: const Key('users-overview-card'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.surface,
            colors.primaryContainer.withValues(
              alpha:
                  Theme.of(context).brightness == Brightness.dark ? .28 : .55,
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .65)),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: .07),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'People overview',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$total',
                      key: const Key('users-total-count'),
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: colors.onSurface,
                                fontWeight: FontWeight.w900,
                                height: 1,
                              ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Registered accounts',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.groups_2_rounded,
                  color: colors.primary,
                  size: 28,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (var index = 0; index < roles.length; index++) ...[
                if (index > 0) const SizedBox(width: 8),
                Expanded(
                  child: _RoleCountPill(
                    role: roles[index].$1,
                    icon: roles[index].$2,
                    count: roleCounts[roles[index].$1] ?? 0,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleCountPill extends StatelessWidget {
  const _RoleCountPill({
    required this.role,
    required this.icon,
    required this.count,
  });

  final String role;
  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    final roleColor = portalRoleColor(role);
    return Container(
      key: Key('users-overview-${role.toLowerCase()}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: roleColor.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: roleColor.withValues(alpha: .16)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: roleColor),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              role,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: roleColor,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: roleColor,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}

class _UserEditor extends StatefulWidget {
  const _UserEditor({
    required this.apiService,
    required this.session,
    this.user,
    this.initialRole,
  });

  final ApiService apiService;
  final AuthSession session;
  final Map? user;
  final String? initialRole;

  @override
  State<_UserEditor> createState() => _UserEditorState();
}

class _UserEditorState extends State<_UserEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  final _password = TextEditingController();
  Uint8List? _profileImageBytes;
  String? _profileImageMimeType;
  bool _profileImageChanged = false;
  late String _role;
  bool _saving = false;
  bool _obscurePassword = true;
  bool _dailyAccess = true;
  bool _weeklyAccess = true;
  bool _monthlyAccess = true;
  String? _error;

  bool get _editing => widget.user != null;
  bool get _isAdmin => widget.session.role.toLowerCase() == 'admin';

  bool _readAccessValue(String key) {
    final value = widget.user?[key];
    if (value is bool) return value;
    if (value == null || value == '') return true;
    return value.toString().toLowerCase() == 'true';
  }

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.user?['name']?.toString() ?? '');
    _email =
        TextEditingController(text: widget.user?['email']?.toString() ?? '');
    const roles = ['Admin', 'Collector', 'Member'];
    final initialRole = widget.user?['role']?.toString();
    final role = initialRole ?? widget.initialRole;
    _role = roles.contains(role) ? role! : 'Member';
    _dailyAccess = _readAccessValue('dailyAccess');
    _weeklyAccess = _readAccessValue('weeklyAccess');
    _monthlyAccess = _readAccessValue('monthlyAccess');
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _detectImageMimeType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'image/webp';
    }
    return null;
  }

  Future<void> _pickProfileImage() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );
      if (image == null || !mounted) return;
      final bytes = await image.readAsBytes();
      if (bytes.length > 307200) {
        setState(
          () => _error = 'Choose an image smaller than 300 KB.',
        );
        return;
      }
      final mimeType = _detectImageMimeType(bytes);
      if (mimeType == null) {
        setState(
          () => _error = 'Choose a JPEG, PNG, or WebP image.',
        );
        return;
      }
      setState(() {
        _profileImageBytes = bytes;
        _profileImageMimeType = mimeType;
        _profileImageChanged = true;
        _error = null;
      });
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.message ?? 'Could not open the image gallery.',
        );
      }
    } on Exception catch (error) {
      if (mounted) setState(() => _error = 'Could not read the image: $error');
    }
  }

  void _removeProfileImage() {
    setState(() {
      _profileImageBytes = null;
      _profileImageMimeType = null;
      _profileImageChanged = _editing;
      _error = null;
    });
  }

  Widget _profileImagePreview(BuildContext context) {
    final existingImage = widget.user?['profileImageUrl']?.toString() ?? '';
    final existingProvider =
        !_profileImageChanged ? profileImageProvider(existingImage) : null;
    final image = _profileImageBytes != null
        ? Image.memory(
            _profileImageBytes!,
            key: const Key('user-profile-image-preview'),
            width: 76,
            height: 76,
            fit: BoxFit.cover,
          )
        : existingProvider == null
            ? null
            : Image(
                image: existingProvider,
                key: const Key('user-profile-image-preview'),
                width: 76,
                height: 76,
                fit: BoxFit.cover,
              );
    return Column(
      children: [
        if (image != null)
          ClipOval(child: image)
        else
          CircleAvatar(
            radius: 38,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Icon(
              Icons.person_outline_rounded,
              size: 38,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            OutlinedButton.icon(
              key: const Key('upload-user-profile-image'),
              onPressed: _saving ? null : _pickProfileImage,
              icon: const Icon(Icons.upload_rounded),
              label: const Text('Upload image'),
            ),
            if (_profileImageBytes != null ||
                (!_profileImageChanged &&
                    profileImageProvider(existingImage) != null))
              TextButton.icon(
                key: const Key('remove-user-profile-image'),
                style: TextButton.styleFrom(
                  foregroundColor: portalDeleteColor,
                ),
                onPressed: _saving ? null : _removeProfileImage,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Remove'),
              ),
          ],
        ),
        const Text('JPEG, PNG, or WebP · up to 300 KB'),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final userId = widget.user?['id']?.toString() ?? '';
    if (_editing && userId.isEmpty) {
      setState(() => _error = 'This user record has no ID to edit.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.apiService.sendPostRequest({
        'action': _editing ? 'editUser' : 'addUser',
        if (_editing) 'userId': userId,
        'name': _name.text.trim(),
        'email': _email.text.trim(),
        'role': _role,
        if (_profileImageChanged) 'profileImageChanged': true,
        if (_profileImageBytes != null) ...{
          'profileImageData': base64Encode(_profileImageBytes!),
          'profileImageMimeType': _profileImageMimeType,
        },
        if (_isAdmin && _role == 'Member') ...{
          'dailyAccess': _dailyAccess,
          'weeklyAccess': _weeklyAccess,
          'monthlyAccess': _monthlyAccess,
        },
        if (_password.text.isNotEmpty) 'password': _password.text,
      }, widget.session);
      if (!saved) {
        throw const ApiException('The server did not save this user.');
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const savingBackground = Color(0xFF253B8C);
    return AlertDialog(
      title: Text(_editing ? 'Edit User' : 'Add User'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('user-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('user-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email address'),
                validator: (value) =>
                    value == null || !value.trim().contains('@')
                        ? 'Enter a valid email'
                        : null,
              ),
              const SizedBox(height: 12),
              _profileImagePreview(context),
              const SizedBox(height: 12),
              if (widget.session.role.toLowerCase() == 'admin')
                DropdownButtonFormField<String>(
                  key: const Key('user-role'),
                  initialValue: _role,
                  items: ['Admin', 'Collector', 'Member']
                      .map((role) =>
                          DropdownMenuItem(value: role, child: Text(role)))
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) setState(() => _role = value);
                        },
                  decoration: const InputDecoration(labelText: 'Role'),
                )
              else
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Role'),
                  subtitle: Text('Member'),
                ),
              if (_isAdmin && _role == 'Member') ...[
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Member report access',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                SwitchListTile(
                  key: const Key('member-daily-access'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Daily report'),
                  subtitle: Text(_dailyAccess ? 'Active' : 'Inactive'),
                  value: _dailyAccess,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _dailyAccess = value),
                ),
                SwitchListTile(
                  key: const Key('member-weekly-access'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Weekly report'),
                  subtitle: Text(_weeklyAccess ? 'Active' : 'Inactive'),
                  value: _weeklyAccess,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _weeklyAccess = value),
                ),
                SwitchListTile(
                  key: const Key('member-monthly-access'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Monthly report'),
                  subtitle: Text(_monthlyAccess ? 'Active' : 'Inactive'),
                  value: _monthlyAccess,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _monthlyAccess = value),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('user-password'),
                controller: _password,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText:
                      _editing ? 'New password (optional)' : 'Initial password',
                  helperText: _editing
                      ? 'Leave blank to keep the current password.'
                      : null,
                  suffixIcon: IconButton(
                    key: const Key('user-password-visibility'),
                    tooltip:
                        _obscurePassword ? 'Show password' : 'Hide password',
                    onPressed: () => setState(
                      () => _obscurePassword = !_obscurePassword,
                    ),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) {
                  if (!_editing && (value == null || value.isEmpty)) {
                    return 'Enter an initial password';
                  }
                  if (value != null && value.isNotEmpty && value.length < 8) {
                    return 'Use at least 8 characters';
                  }
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const Key('user-form-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('user-save-button'),
          style: FilledButton.styleFrom(
            backgroundColor: _saving
                ? savingBackground
                : Theme.of(context).colorScheme.primary,
            foregroundColor: _saving
                ? Colors.white
                : Theme.of(context).colorScheme.onPrimary,
            disabledBackgroundColor: _saving
                ? savingBackground
                : Theme.of(context).colorScheme.primary,
            disabledForegroundColor: _saving
                ? Colors.white
                : Theme.of(context).colorScheme.onPrimary,
          ),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PortalOrbitLoader(
                      size: 25,
                      semanticsLabel: 'Saving account',
                    ),
                    SizedBox(width: 8),
                    Text('Saving…'),
                  ],
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
