import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/wifi_provider.dart';

/// RainMaker login / signup screen.
///
/// Provides email + password fields and a toggle between Login and
/// Sign Up modes.  After sign up, the user must verify their email
/// before logging in.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();

  bool _isSignUp = false;
  bool _needsVerification = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wifi = context.watch<WiFiProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isSignUp ? 'Create Account' : 'Sign In'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Logo / description
            Icon(
              Icons.cloud_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'ESP RainMaker Account',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _isSignUp
                  ? 'Create an account to enable remote monitoring of your Loki PSU from anywhere.'
                  : 'Sign in to access your remotely provisioned Loki PSU devices.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Error banner
            if (wifi.authError != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        wifi.authError!,
                        style: TextStyle(color: Colors.red.shade900),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: wifi.clearAuthError,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Verification code flow
            if (_needsVerification) ...[
              Text(
                'A verification code was sent to your email. '
                'Enter it below to confirm your account.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _codeController,
                decoration: const InputDecoration(
                  labelText: 'Verification Code',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.pin),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: wifi.authLoading ? null : _confirmAccount,
                child: wifi.authLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Confirm Account'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _needsVerification = false),
                child: const Text('Back'),
              ),
            ] else ...[
              // Email field
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
              ),
              const SizedBox(height: 16),

              // Password field
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility
                        : Icons.visibility_off),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                obscureText: _obscurePassword,
                autofillHints: _isSignUp
                    ? const [AutofillHints.newPassword]
                    : const [AutofillHints.password],
              ),
              const SizedBox(height: 24),

              // Submit button
              FilledButton(
                onPressed: wifi.authLoading
                    ? null
                    : (_isSignUp ? _signUp : _login),
                child: wifi.authLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isSignUp ? 'Create Account' : 'Sign In'),
              ),
              const SizedBox(height: 12),

              // Toggle login / signup
              TextButton(
                onPressed: () {
                  setState(() {
                    _isSignUp = !_isSignUp;
                    wifi.clearAuthError();
                  });
                },
                child: Text(_isSignUp
                    ? 'Already have an account? Sign In'
                    : 'Need an account? Sign Up'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) return;

    final wifi = context.read<WiFiProvider>();
    await wifi.login(email, password);

    if (!mounted) return;
    if (wifi.isLoggedIn) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _signUp() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) return;

    final wifi = context.read<WiFiProvider>();
    try {
      await wifi.createAccount(email, password);
      if (mounted) {
        setState(() => _needsVerification = true);
      }
    } catch (_) {
      // Error is handled by the provider
    }
  }

  Future<void> _confirmAccount() async {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();
    if (email.isEmpty || code.isEmpty) return;

    final wifi = context.read<WiFiProvider>();
    try {
      await wifi.confirmAccount(email, code);
      if (mounted) {
        setState(() {
          _needsVerification = false;
          _isSignUp = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account verified! You can now sign in.')),
        );
      }
    } catch (_) {
      // Error is handled by the provider
    }
  }
}
