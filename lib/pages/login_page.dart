import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/portal_loading.dart';
import '../widgets/portal_widgets.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.apiService,
    required this.onLoggedIn,
  });

  final ApiService apiService;
  final ValueChanged<AuthSession> onLoggedIn;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _loginType = 'staff';
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await widget.apiService.login(
        _emailController.text,
        _passwordController.text,
        loginType: _loginType,
      );
      if (mounted) {
        showPortalToast(context, 'Signed in successfully.');
        widget.onLoggedIn(session);
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openRegistration() async {
    final registered = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RegisterPage(apiService: widget.apiService),
      ),
    );
    if (registered == true && mounted) {
      setState(() {
        _error = null;
        _loginType = 'member';
      });
      showPortalToast(context, 'Registration successful. You can now sign in.');
    }
  }

  Future<void> _showPasswordHelp() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forgot your password?'),
        content: const Text(
          'Contact your portal administrator to reset your password. '
          'An admin can open the Users page, choose Edit for your account, '
          'and set a new password. For security, existing passwords cannot be viewed.',
        ),
        actions: [
          FilledButton(
            key: const Key('forgot-password-dismiss'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final roleColor =
        portalRoleColor(_loginType == 'member' ? 'Member' : 'Admin');
    const signingInBackground = Color.fromARGB(255, 0, 0, 0);
    return Scaffold(
      body: PortalGradientBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 190,
                        maxHeight: 150,
                      ),
                      child: Image.asset(
                        'assets/images/ntccsl_logo_big.png',
                        key: const Key('ntccsl-login-logo'),
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'NTCCSL FINANCE SYSTEM',
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.7,
                              ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Your Trusted Financial and Secure Portal.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 28),
                    Card(
                      key: const Key('login-account-card'),
                      color: Color.alphaBlend(
                        roleColor.withValues(alpha: .08),
                        colors.surface,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: roleColor.withValues(alpha: .25),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Welcome back',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                _loginType == 'member'
                                    ? 'Sign in to view your individual member account.'
                                    : 'Sign in with your Admin or Collector account.',
                                style:
                                    TextStyle(color: colors.onSurfaceVariant),
                              ),
                              const SizedBox(height: 22),
                              SegmentedButton<String>(
                                key: const Key('login-account-type'),
                                style: ButtonStyle(
                                  backgroundColor:
                                      WidgetStateProperty.resolveWith(
                                    (states) => states
                                            .contains(WidgetState.selected)
                                        ? Color.alphaBlend(
                                            roleColor.withValues(alpha: .12),
                                            colors.surface,
                                          )
                                        : colors.surface,
                                  ),
                                  foregroundColor:
                                      WidgetStateProperty.resolveWith(
                                    (states) =>
                                        states.contains(WidgetState.selected)
                                            ? roleColor
                                            : colors.onSurfaceVariant,
                                  ),
                                  side: WidgetStateProperty.resolveWith(
                                    (states) => BorderSide(
                                      color:
                                          states.contains(WidgetState.selected)
                                              ? roleColor.withValues(alpha: .55)
                                              : colors.outlineVariant,
                                    ),
                                  ),
                                ),
                                segments: const [
                                  ButtonSegment(
                                    value: 'staff',
                                    label: Text('Staff Login'),
                                    icon: Icon(
                                        Icons.admin_panel_settings_outlined),
                                  ),
                                  ButtonSegment(
                                    value: 'member',
                                    label: Text('Member Login'),
                                    icon: Icon(Icons.person_outline_rounded),
                                  ),
                                ],
                                selected: {_loginType},
                                showSelectedIcon: false,
                                onSelectionChanged: _loading
                                    ? null
                                    : (selection) {
                                        setState(() {
                                          _loginType = selection.single;
                                          _error = null;
                                        });
                                      },
                              ),
                              const SizedBox(height: 18),
                              TextFormField(
                                key: const Key('login-email'),
                                controller: _emailController,
                                keyboardType: _loginType == 'member'
                                    ? TextInputType.text
                                    : TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.username],
                                decoration: InputDecoration(
                                  labelText: _loginType == 'member'
                                      ? 'Email or account number'
                                      : 'Email address',
                                  prefixIcon: Icon(
                                    _loginType == 'member'
                                        ? Icons.person_outline_rounded
                                        : Icons.email_outlined,
                                  ),
                                ),
                                validator: (value) {
                                  final identifier = value?.trim() ?? '';
                                  if (identifier.isEmpty) {
                                    return _loginType == 'member'
                                        ? 'Enter your email or account number'
                                        : 'Enter your email address';
                                  }
                                  if (_loginType == 'staff' &&
                                      !identifier.contains('@')) {
                                    return 'Enter a valid email address';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                key: const Key('login-password'),
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                autofillHints: const [AutofillHints.password],
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    tooltip: _obscurePassword
                                        ? 'Show password'
                                        : 'Hide password',
                                    onPressed: () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                                validator: (value) =>
                                    value == null || value.isEmpty
                                        ? 'Enter your password'
                                        : null,
                                onFieldSubmitted: (_) => _signIn(),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  key: const Key('forgot-password'),
                                  onPressed:
                                      _loading ? null : _showPasswordHelp,
                                  child: const Text('Forgot password?'),
                                ),
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  key: const Key('login-error'),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: colors.errorContainer,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text(
                                    _error!,
                                    style: TextStyle(
                                      color: colors.onErrorContainer,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 20),
                              FilledButton(
                                key: const Key('login-submit'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: _loading
                                      ? signingInBackground
                                      : colors.primary,
                                  foregroundColor: _loading
                                      ? Colors.white
                                      : colors.onPrimary,
                                  disabledBackgroundColor: _loading
                                      ? signingInBackground
                                      : colors.primary,
                                  disabledForegroundColor: _loading
                                      ? Colors.white
                                      : colors.onPrimary,
                                ),
                                onPressed: _loading ? null : _signIn,
                                child: _loading
                                    ? const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          PortalOrbitLoader(
                                            size: 24,
                                            semanticsLabel: 'Signing in...',
                                          ),
                                          SizedBox(width: 10),
                                          Text('Signing in...'),
                                        ],
                                      )
                                    : const Text('Continue'),
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    'Are you have a new Account?',
                                    style: TextStyle(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                  TextButton(
                                    key: const Key('open-register'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: roleColor,
                                      backgroundColor:
                                          roleColor.withValues(alpha: .08),
                                      side: BorderSide(
                                        color: roleColor.withValues(alpha: .35),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                    ),
                                    onPressed:
                                        _loading ? null : _openRegistration,
                                    child: const Text('Sign up'),
                                  ),
                                ],
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
        ),
      ),
    );
  }
}
