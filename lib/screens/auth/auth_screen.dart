import 'package:flutter/material.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../config/api_config.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme.dart';

/// Sign-in / create-account screen. One form that flips between the two modes -
/// register just adds a name field. On success it pops `true` so the caller can
/// react (refresh the header, retry the save the user was attempting, ...).
class AuthScreen extends StatefulWidget {
  final AuthService auth;

  /// Optional line shown at the top, e.g. "Sign in to save this ad".
  final String? reason;

  const AuthScreen({super.key, required this.auth, this.reason});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _register = false;
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      if (_register) {
        await widget.auth.register(
          name: _name.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
        );
      } else {
        await widget.auth.login(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _facebook() async {
    setState(() => _busy = true);
    try {
      final result = await FacebookAuth.instance
          .login(permissions: const ['public_profile', 'email']);
      if (result.status == LoginStatus.success && result.accessToken != null) {
        await widget.auth.loginWithFacebook(result.accessToken!.tokenString);
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else if (result.status == LoginStatus.cancelled) {
        // User backed out - not an error, just do nothing.
      } else {
        _snack((result.message ?? '').isNotEmpty
            ? result.message!
            : 'Facebook sign-in failed. Please try again.');
      }
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack("Facebook sign-in isn't available right now.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() => _busy = true);
    try {
      final gsi = GoogleSignIn(
        serverClientId: ApiConfig.googleServerClientId,
        scopes: const ['email', 'profile'],
      );
      // Sign out first so the account picker always appears (no silent reuse).
      await gsi.signOut();
      final account = await gsi.signIn();
      if (account == null) return; // user backed out
      final tokens = await account.authentication;
      final idToken = tokens.idToken;
      if (idToken == null || idToken.isEmpty) {
        _snack('Google sign-in failed. Please try again.');
        return;
      }
      await widget.auth.loginWithGoogle(idToken);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack("Google sign-in isn't available right now.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppColors.ink,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _logo(),
                const SizedBox(height: 8),
                Text(
                  _register ? 'Create your account' : 'Welcome back',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.reason ??
                      (_register
                          ? 'Join Listit to save, message and sell.'
                          : 'Sign in to save, message and sell.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.slate, fontSize: 14),
                ),
                if (widget.auth.sessionExpired) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      border: Border.all(color: const Color(0xFFFED7AA)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 18, color: Color(0xFFB45309)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Your session expired — please sign in again.',
                            style: TextStyle(
                                color: Color(0xFFB45309), fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                if (_register) ...[
                  _field(
                    controller: _name,
                    label: 'Full name',
                    icon: Icons.person_outline,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Please enter your name'
                        : null,
                  ),
                  const SizedBox(height: 14),
                ],
                _field(
                  controller: _email,
                  label: 'Email',
                  icon: Icons.mail_outline,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return 'Please enter your email';
                    if (!s.contains('@') || !s.contains('.')) {
                      return 'Enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                _field(
                  controller: _password,
                  label: 'Password',
                  icon: Icons.lock_outline,
                  obscure: _obscure,
                  suffix: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: AppColors.muted,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Please enter a password';
                    if (_register && v.length < 6) {
                      return 'Use at least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.4, color: Colors.white),
                          )
                        : Text(
                            _register ? 'Create account' : 'Sign in',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: const [
                    Expanded(child: Divider(color: AppColors.line)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or',
                          style: TextStyle(color: AppColors.muted, fontSize: 13)),
                    ),
                    Expanded(child: Divider(color: AppColors.line)),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _facebook,
                    icon: const Icon(Icons.facebook, color: Color(0xFF1877F2)),
                    label: const Text(
                      'Continue with Facebook',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.line),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _google,
                    icon: const Text(
                      'G',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF4285F4),
                      ),
                    ),
                    label: const Text(
                      'Continue with Google',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.line),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _register
                          ? 'Already have an account?'
                          : "New to Listit?",
                      style: const TextStyle(color: AppColors.slate),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _register = !_register),
                      child: Text(
                        _register ? 'Sign in' : 'Sign up',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _logo() {
    return Image.asset(
      'assets/listit_logo.png',
      height: 46,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.slate),
        suffixIcon: suffix,
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}
