import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/portal_loading.dart';
import '../widgets/portal_widgets.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key, required this.apiService});

  final ApiService apiService;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.apiService.register(
        name: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text,
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const brandColor = Color(0xFF253B8C);
    const creatingBackground = Color.fromARGB(255, 6, 9, 21);
    final accentColor = Theme.of(context).brightness == Brightness.dark
        ? colors.primary
        : brandColor;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create account'),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(
            color: brandColor,
          ),
        ),
      ),
      body: PortalGradientBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 150,
                        maxHeight: 110,
                      ),
                      child: Image.asset(
                        'assets/images/ntccsl_logo_big.png',
                        key: const Key('register-logo'),
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'NTCCSL FINANCE SYSTEM',
                      key: const Key('register-system-name'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: accentColor,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.5,
                          ),
                    ),
                    const SizedBox(height: 20),
                    Card(
                      key: const Key('register-account-card'),
                      color: Color.alphaBlend(
                        accentColor.withValues(alpha: .07),
                        colors.surface,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(
                          color: accentColor.withValues(alpha: .22),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 18),
                              Text(
                                'Create your account',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      color: accentColor,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -.6,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Create your individual member account to access the NTCCSL.',
                                style:
                                    TextStyle(color: colors.onSurfaceVariant),
                              ),
                              const SizedBox(height: 24),
                              TextFormField(
                                key: const Key('register-name'),
                                controller: _nameController,
                                textCapitalization: TextCapitalization.words,
                                autofillHints: const [AutofillHints.name],
                                decoration: const InputDecoration(
                                  labelText: 'Full name',
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                        ? 'Enter your name'
                                        : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                key: const Key('register-email'),
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                decoration: const InputDecoration(
                                  labelText: 'Email address',
                                  prefixIcon: Icon(Icons.email_outlined),
                                ),
                                validator: (value) =>
                                    value == null || !value.trim().contains('@')
                                        ? 'Enter a valid email address'
                                        : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                key: const Key('register-password'),
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                autofillHints: const [
                                  AutofillHints.newPassword
                                ],
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  helperText: 'Use at least 8 characters.',
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
                                    value == null || value.length < 8
                                        ? 'Use at least 8 characters'
                                        : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                key: const Key('register-confirm-password'),
                                controller: _confirmPasswordController,
                                obscureText: _obscureConfirmation,
                                decoration: InputDecoration(
                                  labelText: 'Confirm password',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    tooltip: _obscureConfirmation
                                        ? 'Show password'
                                        : 'Hide password',
                                    onPressed: () => setState(
                                      () => _obscureConfirmation =
                                          !_obscureConfirmation,
                                    ),
                                    icon: Icon(
                                      _obscureConfirmation
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                                validator: (value) =>
                                    value != _passwordController.text
                                        ? 'Passwords do not match'
                                        : null,
                                onFieldSubmitted: (_) => _register(),
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  key: const Key('register-error'),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: colors.errorContainer,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text(
                                    _error!,
                                    style: TextStyle(
                                        color: colors.onErrorContainer),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 20),
                              FilledButton(
                                key: const Key('register-submit'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: _loading
                                      ? creatingBackground
                                      : brandColor,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: _loading
                                      ? creatingBackground
                                      : brandColor,
                                  disabledForegroundColor: Colors.white,
                                ),
                                onPressed: _loading ? null : _register,
                                child: _loading
                                    ? const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          PortalOrbitLoader(
                                            size: 25,
                                            semanticsLabel: 'Creating account',
                                            // accentColor: Colors.white,
                                          ),
                                          SizedBox(width: 10),
                                          Text('Creating account…'),
                                        ],
                                      )
                                    : const Text('Register'),
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    'Already have an account?',
                                    style: TextStyle(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                  TextButton(
                                    key: const Key('register-sign-in'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: accentColor,
                                      backgroundColor:
                                          accentColor.withValues(alpha: .08),
                                      side: BorderSide(
                                        color: accentColor.withValues(
                                          alpha: .35,
                                        ),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                    ),
                                    onPressed: _loading
                                        ? null
                                        : () =>
                                            Navigator.of(context).pop(false),
                                    child: const Text('Sign in'),
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
