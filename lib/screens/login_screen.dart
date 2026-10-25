// =============================================================================
// Sign-in — first launch. Checks the server and credentials before saving
// them (encrypted Hive auth box), then replaces itself with the app.
//
// Typing is the hard part on a TV remote, so this screen helps: it remembers
// the last server, offers the suggested one as a chip, takes paste and voice,
// moves Next / Done through the fields in order, and on a TV points at the
// phone remote keyboard. (The easy way on a TV is pairing; see TvPairScreen.)
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
import '../utils/platform_utils.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/art/navi_icons.dart';
import '../widgets/ui/grouped_list.dart';

/// Checks [server] / [user] / [pass] against the server, saves them, and
/// remembers the server for next time. Throws the app's own exceptions.
Future<void> verifyAndSaveCredentials(
  WidgetRef ref, {
  required String server,
  required String user,
  required String pass,
}) async {
  // Check before saving, so a typo doesn't land the person in an app
  // that fails everywhere.
  await SubsonicService(
    serverUrl: server,
    username: user,
    password: pass,
    cache: ref.read(playlistCacheServiceProvider),
  ).verifyCredentials();
  await ref.read(settingsProvider.notifier).saveSettings(server, user, pass);
  try {
    await HiveBoxes.prefs.put(HiveBoxes.kLastServerUrl, server);
  } catch (_) {} // remembering is a convenience; never fail a sign-in over it
}

/// What to tell the person for a failed [verifyAndSaveCredentials].
String signInErrorMessage(Object error) => switch (error) {
      AuthException() => 'That username and password didn’t work. Check them and try again.',
      NetworkException() => 'Can’t reach the server. Check the address and your connection.',
      TimeoutException() => 'The server took too long to answer. Try again.',
      _ => 'The server didn’t respond like a Navidrome or Subsonic server. Check the address.',
    };

/// Replaces the sign-in with the app.
void openApp(BuildContext context) {
  Navigator.of(context).pushReplacement(
    PageRouteBuilder(
      pageBuilder: (_, _, _) => const AppScaffold(),
      transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
      transitionDuration: Motion.slow,
    ),
  );
}

String? _lastServer() {
  try {
    final v = HiveBoxes.prefs.get(HiveBoxes.kLastServerUrl)?.toString() ?? '';
    return v.isEmpty ? null : v;
  } catch (_) {
    return null; // prefs not open (tests)
  }
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _server = TextEditingController(text: _lastServer() ?? Constants.suggestedServerUrl);
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _serverNode = FocusNode(debugLabel: 'login-server');
  final _userNode = FocusNode(debugLabel: 'login-user');
  final _passNode = FocusNode(debugLabel: 'login-password');
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
    for (final c in [_server, _user, _pass]) {
      c.dispose();
    }
    for (final n in [_serverNode, _userNode, _passNode]) {
      n.dispose();
    }
    super.dispose();
  }

  bool get _ready => _server.text.trim().isNotEmpty && _user.text.trim().isNotEmpty && _pass.text.isNotEmpty;

  /// Start where there is something left to type.
  bool get _serverFilled => _server.text.trim().isNotEmpty;

  Future<void> _signIn() async {
    if (!_ready || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await verifyAndSaveCredentials(
        ref,
        server: _server.text.trim(),
        user: _user.text.trim(),
        pass: _pass.text,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      openApp(context);
    } catch (e) {
      _fail(signInErrorMessage(e));
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

  Future<void> _pasteServer() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    _server.text = text;
    _userNode.requestFocus();
  }

  Widget _brand(AppThemeTokens t, {required bool compact}) {
    final mark = Container(
      width: compact ? 64 : 84,
      height: compact ? 64 : 84,
      decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(compact ? 15 : 20)),
      child: NaviIcon(NaviGlyph.aiShuffle, size: compact ? 34 : 44, color: t.onAccent),
    );
    final cross = compact ? CrossAxisAlignment.start : CrossAxisAlignment.center;
    final align = compact ? TextAlign.start : TextAlign.center;
    return Column(
      crossAxisAlignment: cross,
      mainAxisSize: MainAxisSize.min,
      children: [
        // App mark: a squircle in the accent, like an iOS icon.
        mark,
        SizedBox(height: compact ? Space.lg : Space.xxl),
        Text('Welcome to ${Constants.appName}', textAlign: align, style: t.title1),
        const SizedBox(height: Space.sm),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : Space.xxxl),
          child: Text(
            'Sign in with the username and password you were given.',
            textAlign: align,
            style: t.subheadline,
          ),
        ),
        if (compact && PlatformUtils.isTv) ...[
          const SizedBox(height: Space.lg),
          Text(
            'Typing is easier from your phone: open the Google TV app, tap Remote, then the keyboard icon. '
            'Or go back and pair with your phone instead.',
            style: t.footnote,
          ),
        ],
      ],
    );
  }

  Widget _form(AppThemeTokens t, {required bool compact}) {
    final suggested = Constants.suggestedServerUrl;
    return AutofillGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GroupedSection(
            children: [
              FocusTraversalOrder(
                order: const NumericFocusOrder(1),
                child: GroupedTextFieldRow(
                  title: 'Server',
                  controller: _server,
                  focusNode: _serverNode,
                  placeholder: 'https://',
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  autofocus: !_serverFilled,
                  voice: true,
                  onSubmitted: (_) => _userNode.requestFocus(),
                ),
              ),
              FocusTraversalOrder(
                order: const NumericFocusOrder(3),
                child: GroupedTextFieldRow(
                  title: 'Username',
                  controller: _user,
                  focusNode: _userNode,
                  placeholder: 'Required',
                  textInputAction: TextInputAction.next,
                  autofocus: _serverFilled,
                  autofillHints: const [AutofillHints.username],
                  voice: true,
                  onSubmitted: (_) => _passNode.requestFocus(),
                ),
              ),
              // No microphone on the password: it would be said aloud.
              FocusTraversalOrder(
                order: const NumericFocusOrder(4),
                child: GroupedTextFieldRow(
                  title: 'Password',
                  controller: _pass,
                  focusNode: _passNode,
                  placeholder: 'Required',
                  obscure: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _signIn(),
                ),
              ),
            ],
          ),
          FocusTraversalOrder(
            order: const NumericFocusOrder(2),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
              child: Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  if (suggested.isNotEmpty && _server.text.trim() != suggested)
                    _Chip(
                      label: 'Use $suggested',
                      onTap: () {
                        _server.text = suggested;
                        _userNode.requestFocus();
                      },
                    ),
                  _Chip(label: 'Paste server', onTap: _pasteServer),
                ],
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xxl, 0, Space.xxl, Space.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NaviIcon(NaviGlyph.alert, size: 16, color: t.danger, filled: true),
                  const SizedBox(width: Space.sm),
                  Expanded(child: Text(_error!, style: t.footnote.copyWith(color: t.danger))),
                ],
              ),
            ),
          FocusTraversalOrder(
            order: const NumericFocusOrder(5),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: CupertinoClickable(
                onTap: _ready && !_busy ? _signIn : null,
                focusRadius: Radii.capsule,
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
                      : Text('Sign In', style: t.headline.copyWith(color: _ready ? t.onAccent : t.textMuted)),
                ),
              ),
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: Space.xl),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.xxxl),
              child: Text(
                PlatformUtils.isTv
                    ? 'Typing is easier from your phone: open the Google TV app, tap Remote, '
                        'then the keyboard icon. Or go back and pair with your phone instead.'
                    : 'Your password is stored encrypted on this device.',
                textAlign: TextAlign.center,
                style: t.footnote,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: t.bgBase,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) {
              // A short, wide screen (a TV, a phone on its side) puts the brand
              // beside the form so Sign In is never below the fold.
              final compact = c.maxHeight < 620 && c.maxWidth > c.maxHeight;
              return FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(vertical: compact ? Space.lg : Space.huge, horizontal: Space.lg),
                    child: compact
                        ? ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 900),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(flex: 5, child: _brand(t, compact: true)),
                                const SizedBox(width: Space.xxxl),
                                Expanded(flex: 6, child: _form(t, compact: true)),
                              ],
                            ),
                          )
                        : ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _brand(t, compact: false),
                                const SizedBox(height: Space.xxxl),
                                _form(t, compact: false),
                              ],
                            ),
                          ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return CupertinoClickable(
      onTap: onTap,
      focusRadius: Radii.capsule,
      semanticLabel: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
        decoration: BoxDecoration(color: t.fill, borderRadius: BorderRadius.circular(Radii.capsule)),
        child: Text(label, style: t.footnote.copyWith(color: t.textPrimary)),
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
