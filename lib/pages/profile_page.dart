import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../widgets/portal_loading.dart';
import '../widgets/portal_widgets.dart';
import '../widgets/profile_image.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.apiService,
    required this.session,
    this.onSessionUpdated,
  });

  final ApiService apiService;
  final AuthSession session;
  final ValueChanged<AuthSession>? onSessionUpdated;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late AuthSession _session;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
  }

  Future<void> _editProfile() async {
    final updatedSession = await showDialog<AuthSession>(
      context: context,
      builder: (_) => _EditProfileDialog(
        apiService: widget.apiService,
        session: _session,
      ),
    );
    if (updatedSession == null || !mounted) return;
    setState(() => _session = updatedSession);
    widget.onSessionUpdated?.call(updatedSession);
    showPortalToast(context, 'Profile updated successfully.');
  }

  Future<void> _changePassword() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ChangePasswordDialog(
        apiService: widget.apiService,
        session: _session,
      ),
    );

    if (changed == true && mounted) {
      showPortalToast(context, 'Password changed successfully.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final displayName =
        _session.name.trim().isEmpty ? 'Portal user' : _session.name;
    final initial = displayName.characters.first.toUpperCase();
    final accountNumber = _session.accountNumber;
    final profileImage = profileImageProvider(_session.profileImageUrl);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My profile'),
        flexibleSpace: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: portalHeaderGradient(context)),
          ),
        ),
      ),
      body: PortalGradientBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: portalHeaderGradient(context),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colors.primary.withValues(alpha: .18),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: -38,
                        right: -22,
                        child: IgnorePointer(
                          child: Container(
                            width: 150,
                            height: 150,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: .08),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(22),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: .20),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: .45),
                                  width: 2,
                                ),
                              ),
                              child: CircleAvatar(
                                radius: 38,
                                backgroundColor: colors.primaryContainer,
                                child: profileImage == null
                                    ? Text(
                                        initial,
                                        style: TextStyle(
                                          color: colors.onPrimaryContainer,
                                          fontSize: 30,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      )
                                    : ClipOval(
                                        child: Image(
                                          image: profileImage,
                                          key: const Key('profile-image'),
                                          width: 85,
                                          height: 85,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  Center(
                                            child: Text(
                                              initial,
                                              style: TextStyle(
                                                color:
                                                    colors.onPrimaryContainer,
                                                fontSize: 30,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ACCOUNT PROFILE',
                                    style: textTheme.labelSmall?.copyWith(
                                      color: Colors.white.withValues(alpha: .8),
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    displayName,
                                    key: const Key('profile-name'),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.titleLarge?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 11,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: .16),
                                      borderRadius: BorderRadius.circular(30),
                                      border: Border.all(
                                        color:
                                            Colors.white.withValues(alpha: .28),
                                      ),
                                    ),
                                    child: Text(
                                      _session.role,
                                      key: const Key('profile-role'),
                                      style: textTheme.labelMedium?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
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
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('edit-profile'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade400,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _editProfile,
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Edit profile'),
                ),
                const SizedBox(height: 20),
                Text(
                  'Account information',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final details = [
                      _ProfileDetailCard(
                        key: const Key('profile-email-card'),
                        icon: Icons.alternate_email_rounded,
                        label: 'Email address',
                        value: _session.email,
                        valueKey: const Key('profile-email'),
                      ),
                      _ProfileDetailCard(
                        key: const Key('profile-account-card'),
                        icon: Icons.badge_outlined,
                        label: 'Account number',
                        value: accountNumber,
                        valueKey: const Key('profile-account-number'),
                      ),
                    ];
                    if (constraints.maxWidth < 460) {
                      return Column(
                        children: [
                          details[0],
                          const SizedBox(height: 10),
                          details[1],
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: details[0]),
                        const SizedBox(width: 12),
                        Expanded(child: details[1]),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: const Key('change-password'),
                    onTap: _changePassword,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              Icons.lock_reset_rounded,
                              color: colors.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Change password',
                                  style: textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Verify your current password and choose a new one.',
                                  style: textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 16,
                            color: colors.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EditProfileDialog extends StatefulWidget {
  const _EditProfileDialog({
    required this.apiService,
    required this.session,
  });

  final ApiService apiService;
  final AuthSession session;

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  Uint8List? _imageBytes;
  String? _imageMimeType;
  bool _imageChanged = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.session.name);
    _email = TextEditingController(text: widget.session.email);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  String? _imageMimeTypeFor(Uint8List bytes) {
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

  Future<void> _pickImage() async {
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
        setState(() => _error = 'Choose an image smaller than 300 KB.');
        return;
      }
      final mimeType = _imageMimeTypeFor(bytes);
      if (mimeType == null) {
        setState(() => _error = 'Choose a JPEG, PNG, or WebP image.');
        return;
      }
      setState(() {
        _imageBytes = bytes;
        _imageMimeType = mimeType;
        _imageChanged = true;
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final encodedImage =
          _imageBytes == null ? null : base64Encode(_imageBytes!);
      await widget.apiService.updateMyProfile(
        session: widget.session,
        name: _name.text.trim(),
        email: _email.text.trim(),
        profileImageChanged: _imageChanged,
        profileImageData: encodedImage,
        profileImageMimeType: _imageMimeType,
      );
      if (!mounted) return;
      final imageUrl = !_imageChanged
          ? widget.session.profileImageUrl
          : encodedImage == null
              ? ''
              : 'data:$_imageMimeType;base64,$encodedImage';
      Navigator.of(context).pop(
        widget.session.copyWith(
          name: _name.text.trim(),
          email: _email.text.trim(),
          profileImageUrl: imageUrl,
        ),
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final existingImage = profileImageProvider(widget.session.profileImageUrl);
    final initial = _name.text.trim().isEmpty
        ? '?'
        : _name.text.trim().characters.first.toUpperCase();
    final image = _imageBytes != null
        ? Image.memory(
            _imageBytes!,
            key: const Key('edit-profile-image-preview'),
            width: 76,
            height: 76,
            fit: BoxFit.cover,
          )
        : !_imageChanged && existingImage != null
            ? Image(
                image: existingImage,
                key: const Key('edit-profile-image-preview'),
                width: 76,
                height: 76,
                fit: BoxFit.cover,
              )
            : null;
    return AlertDialog(
      title: const Text('Edit profile'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (image == null)
                CircleAvatar(
                  radius: 38,
                  backgroundColor: colors.primaryContainer,
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: colors.onPrimaryContainer,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              else
                ClipOval(child: image),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('edit-profile-upload-image'),
                    onPressed: _saving ? null : _pickImage,
                    icon: const Icon(Icons.photo_camera_back_outlined),
                    label: const Text('Change photo'),
                  ),
                  if (_imageBytes != null ||
                      (!_imageChanged && existingImage != null))
                    TextButton.icon(
                      key: const Key('edit-profile-remove-image'),
                      style: TextButton.styleFrom(
                        foregroundColor: portalDeleteColor,
                      ),
                      onPressed: _saving
                          ? null
                          : () => setState(() {
                                _imageBytes = null;
                                _imageMimeType = null;
                                _imageChanged = true;
                                _error = null;
                              }),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Remove'),
                    ),
                ],
              ),
              const Text('JPEG, PNG, or WebP · up to 300 KB'),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('edit-profile-name'),
                controller: _name,
                textCapitalization: TextCapitalization.words,
                readOnly: widget.session.role.toLowerCase() == 'member',
                decoration: InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                  helperText: widget.session.role.toLowerCase() == 'member'
                      ? 'Contact an administrator to change your name.'
                      : null,
                ),
                validator: (value) {
                  final name = value?.trim() ?? '';
                  if (name.isEmpty) return 'Enter your name';
                  if (name.length > 100) return 'Name is too long';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('edit-profile-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const Key('edit-profile-error'),
                  style: TextStyle(color: colors.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('save-profile'),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const PortalOrbitLoader(
                  size: 18,
                  semanticsLabel: 'Saving profile',
                )
              : const Text('Save profile'),
        ),
      ],
    );
  }
}

class _ProfileDetailCard extends StatelessWidget {
  const _ProfileDetailCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final IconData icon;
  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: colors.onSecondaryContainer, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    value.isEmpty ? 'Not available' : value,
                    key: valueKey,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
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

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({
    required this.apiService,
    required this.session,
  });

  final ApiService apiService;
  final AuthSession session;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.apiService.sendPostRequest({
        'action': 'changePassword',
        'currentPassword': _currentPassword.text,
        'newPassword': _newPassword.text,
      }, widget.session);
      if (!saved) {
        throw const ApiException('The server did not update your password.');
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (exception) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = exception.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('profile-current-password'),
                controller: _currentPassword,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Current password',
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show passwords' : 'Hide passwords',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'Enter your current password'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('profile-new-password'),
                controller: _newPassword,
                obscureText: _obscure,
                decoration: const InputDecoration(labelText: 'New password'),
                validator: (value) {
                  if (value == null || value.length < 8) {
                    return 'Use at least 8 characters';
                  }
                  if (value.length > 256) {
                    return 'Use no more than 256 characters';
                  }
                  if (value == _currentPassword.text) {
                    return 'Choose a different password';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('profile-confirm-password'),
                controller: _confirmPassword,
                obscureText: _obscure,
                decoration:
                    const InputDecoration(labelText: 'Confirm new password'),
                validator: (value) => value != _newPassword.text
                    ? 'Passwords do not match'
                    : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const Key('profile-password-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('save-profile-password'),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const PortalOrbitLoader(
                  size: 18,
                  semanticsLabel: 'Updating password',
                )
              : const Text('Update password'),
        ),
      ],
    );
  }
}
