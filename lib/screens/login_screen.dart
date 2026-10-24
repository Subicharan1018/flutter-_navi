// =============================================================================
// Sign-in — first launch. Checks the server and credentials before saving
// them (encrypted Hive auth box), then replaces itself with the app.
// =============================================================================

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_exception.dart';
import '../core/constants.dart';
import '../core/hive_boxes.dart';
import '../core/theme.dart';
import '../providers/settings_provider.dart';
import '../services/subsonic_service.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/ui/grouped_list.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _server = TextEditingController(text: Constants.suggestedServerUrl);
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final c in [_server, _user, _pass]) {
      c.addListener(() => setState(() => _error = null));
    }
  }

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  bool get _ready => _server.text.trim().isNotEmpty && _user.text.trim().isNotEmpty && _pass.text.isNotEmpty;

  Future<void> _signIn() async {
    if (!_ready || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final server = _server.text.trim();
    final user = _user.text.trim();
    final pass = _pass.text;
    try {
      // Check before saving, so a typo doesn't land the person in an app
      // that fails everywhere.
      await SubsonicService(
        serverUrl: server,
        username: user,
        password: pass,
        cache: ref.read(playlistCacheServiceProvider),
      ).verifyCredentials();
      await ref.read(settingsProvider.notifier).saveSettings(server, user, pass);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, _, _) => const AppScaffold(),
          transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
          transitionDuration: Motion.slow,
        ),
      );
    } on AuthException {
      _fail('That username and password didn’t work. Check them and try again.');
    } on NetworkException {
      _fail('Can’t reach the server. Check the address and your connection.');
    } on TimeoutException {
      _fail('The server took too long to answer. Try again.');
    } catch (_) {
      _fail('The server didn’t respond like a Navidrome or Subsonic server. Check the address.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: t.bgBase,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: Space.huge),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: AutofillGroup(
                  child: Column(
                    children: [
                      // App mark: a squircle in the accent, like an iOS icon.
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: t.accent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(CupertinoIcons.waveform, size: 44, color: t.onAccent),
                      ),
                      const SizedBox(height: Space.xxl),
                      Text('Welcome to ${Constants.appName}', textAlign: TextAlign.center, style: t.title1),
                      const SizedBox(height: Space.sm),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.xxxl),
                        child: Text(
                          'Sign in with the username and password you were given.',
                          textAlign: TextAlign.center,
                          style: t.subheadline,
                        ),
                      ),
                      const SizedBox(height: Space.xxxl),
                      GroupedSection(
                        children: [
                          GroupedTextFieldRow(
                            title: 'Server',
                            controller: _server,
                            placeholder: 'https://',
                            keyboardType: TextInputType.url,
                          ),
                          GroupedTextFieldRow(title: 'Username', controller: _user, placeholder: 'Required'),
                          GroupedTextFieldRow(
                            title: 'Password',
                            controller: _pass,
                            placeholder: 'Required',
                            obscure: true,
                          ),
                        ],
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(Space.xxl, 0, Space.xxl, Space.lg),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(CupertinoIcons.exclamationmark_circle_fill, size: 16, color: t.danger),
                              const SizedBox(width: Space.sm),
                              Expanded(child: Text(_error!, style: t.footnote.copyWith(color: t.danger))),
                            ],
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                        child: CupertinoClickable(
                          onTap: _ready && !_busy ? _signIn : null,
                          scaleFactor: 0.97,
                          semanticLabel: 'Sign In',
                          child: AnimatedContainer(
                            duration: Motion.fast,
                            height: 52,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _ready ? t.accent : t.fill,
                              borderRadius: BorderRadius.circular(Radii.capsule),
                            ),
                            child: _busy
                                ? CupertinoActivityIndicator(color: t.onAccent)
                                : Text(
                                    'Sign In',
                                    style: t.headline.copyWith(color: _ready ? t.onAccent : t.textMuted),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: Space.xl),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.xxxl),
                        child: Text(
                          'Your password is stored encrypted on this device.',
                          textAlign: TextAlign.center,
                          style: t.footnote,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// True when a username and password are saved (the app opens straight in).
bool isLoggedIn() {
  final auth = HiveBoxes.auth;
  final username = auth.get(HiveBoxes.kUsername)?.toString() ?? '';
  final password = auth.get(HiveBoxes.kPassword)?.toString() ?? '';
  return username.isNotEmpty && password.isNotEmpty;
}
