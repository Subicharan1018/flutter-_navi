// =============================================================================
// LoginScreen — first-launch credential entry for NaviVibe
//
// • Navidrome URL is hardcoded to https://music.subimusic.me
// • Smart Shuffle API is hardcoded to https://shuffle.subimusic.me
// • Only asks for username + password
// • Credentials are persisted in the encrypted Hive auth box (like cookies)
// • Once saved, the app goes directly to AppScaffold on every subsequent launch
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/hive_boxes.dart';
import '../core/theme.dart';
import '../providers/settings_provider.dart';
import '../widgets/app_scaffold.dart';

// Hardcoded base URLs — never exposed to user
const _kMusicUrl = 'https://subimusic.me';
const _kShuffleUrl = 'https://shuffle.subimusic.me';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final username = _userCtrl.text.trim();
    final password = _passCtrl.text;

    try {
      // Persist credentials using the same method as SettingsScreen
      await ref
          .read(settingsProvider.notifier)
          .saveSettings(_kMusicUrl, username, password);

      if (!mounted) return;
      // Replace the login screen with AppScaffold — no back navigation
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const AppScaffold(),
          transitionsBuilder: (context, anim, secondaryAnimation, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to save credentials. Please try again.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: tokens.bgBase,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Logo ───────────────────────────────────────────────
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tokens.accent.withValues(alpha: 0.12),
                      ),
                      child: Icon(
                        Icons.graphic_eq_rounded,
                        size: 40,
                        color: tokens.accent,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'NaviVibe',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: tokens.textPrimary,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sign in with your Navidrome account',
                      style: TextStyle(fontSize: 14, color: tokens.textMuted),
                    ),

                    const SizedBox(height: 36),

                    // ── Username ───────────────────────────────────────────
                    TextFormField(
                      controller: _userCtrl,
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      style: TextStyle(color: tokens.textPrimary),
                      decoration: _inputDecoration(
                        context,
                        label: 'Username',
                        icon: Icons.person_outline_rounded,
                        tokens: tokens,
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter your username'
                          : null,
                    ),

                    const SizedBox(height: 16),

                    // ── Password ───────────────────────────────────────────
                    TextFormField(
                      controller: _passCtrl,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _loading ? null : _login(),
                      style: TextStyle(color: tokens.textPrimary),
                      decoration:
                          _inputDecoration(
                            context,
                            label: 'Password',
                            icon: Icons.lock_outline_rounded,
                            tokens: tokens,
                          ).copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: tokens.textMuted,
                                size: 20,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Enter your password'
                          : null,
                    ),

                    // ── Error message ──────────────────────────────────────
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.errorContainer.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: cs.onErrorContainer,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 28),

                    // ── Sign In button ─────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        onPressed: _loading ? null : _login,
                        style: FilledButton.styleFrom(
                          backgroundColor: tokens.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Sign In',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── Server info footer ─────────────────────────────────
                    _ServerInfoRow(tokens: tokens),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    BuildContext context, {
    required String label,
    required IconData icon,
    required AppThemeTokens tokens,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: tokens.textMuted),
      prefixIcon: Icon(icon, color: tokens.textMuted, size: 20),
      filled: true,
      fillColor: tokens.bgElevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: tokens.outline.withValues(alpha: 0.3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: tokens.outline.withValues(alpha: 0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: tokens.accent, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.error,
          width: 1.5,
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Small footer showing the hardcoded server endpoints
// ──────────────────────────────────────────────────────────────────────────────
class _ServerInfoRow extends StatelessWidget {
  final AppThemeTokens tokens;
  const _ServerInfoRow({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Connecting to',
          style: TextStyle(fontSize: 11, color: tokens.textMuted),
        ),
        const SizedBox(height: 6),
        _Pill(label: '🎵  $_kMusicUrl', tokens: tokens),
        const SizedBox(height: 4),
        _Pill(label: '🤖  $_kShuffleUrl', tokens: tokens),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final AppThemeTokens tokens;
  const _Pill({required this.label, required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: tokens.bgElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tokens.outline.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: tokens.textMuted),
      ),
    );
  }
}

// =============================================================================
// Helper: check whether the user is already logged in
// Returns true if username + password are saved in Hive.
// =============================================================================
bool isLoggedIn() {
  final auth = HiveBoxes.auth;
  final username = auth.get(HiveBoxes.kUsername)?.toString() ?? '';
  final password = auth.get(HiveBoxes.kPassword)?.toString() ?? '';
  return username.isNotEmpty && password.isNotEmpty;
}
