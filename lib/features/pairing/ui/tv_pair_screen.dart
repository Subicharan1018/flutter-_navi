import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme.dart';
import '../../../screens/login_screen.dart';
import '../../../widgets/mascot/microduck.dart';
import '../../../widgets/mascot/microduck_pose.dart';
import '../../../providers/settings_provider.dart';
import '../pair_crypto.dart';
import '../pair_link.dart';
import '../pair_providers.dart';
import '../pair_relay.dart';
import '../tv_pairing.dart';

// =============================================================================
// TV sign-in: a big code and a QR. Open NaviVibe on a signed-in phone, go to
// Settings → Sign in another device, and type the code or scan the QR; the
// phone sends the login end-to-end encrypted and this screen signs in.
// "Type it instead" is the way to the ordinary form.
// =============================================================================

class TvPairScreen extends ConsumerStatefulWidget {
  /// Tests inject a relay and a quicker poll.
  final PairRelay? relay;
  final Duration pollEvery;
  const TvPairScreen({
    super.key,
    this.relay,
    this.pollEvery = const Duration(seconds: 2),
  });

  @override
  ConsumerState<TvPairScreen> createState() => _TvPairScreenState();
}

class _TvPairScreenState extends ConsumerState<TvPairScreen> {
  late final TvPairing _pairing = TvPairing(
    relay: widget.relay ?? ref.read(pairRelayProvider),
    pollEvery: widget.pollEvery,
    signIn: _signIn,
  );

  Future<void> _signIn(PairCredentials c) async {
    try {
      await verifyAndSaveCredentials(
        ref,
        server: c.serverUrl,
        user: c.username,
        pass: c.password,
      );
    } catch (e) {
      throw Exception(signInErrorMessage(e));
    }
  }

  @override
  void initState() {
    super.initState();
    _pairing.addListener(_changed);
    _pairing.start();
  }

  void _changed() {
    if (_pairing.value is TvPairDone && mounted) openApp(context);
  }

  @override
  void dispose() {
    _pairing.removeListener(_changed);
    _pairing.dispose();
    super.dispose();
  }

  void _typeInstead() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const LoginScreen()));

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Scaffold(
      backgroundColor: t.bgBase,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xxxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: FocusTraversalGroup(
                child: ValueListenableBuilder<TvPairState>(
                  valueListenable: _pairing,
                  builder: (context, state, _) => switch (state) {
                    TvPairStarting() => const _Centered(
                      child: CircularProgressIndicator(),
                    ),
                    TvPairWaiting() => _Waiting(
                      state: state,
                      onTypeInstead: _typeInstead,
                    ),
                    TvPairSigningIn(:final username) => _Centered(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: Space.xl),
                          Text('Signing in as $username…', style: t.title2),
                        ],
                      ),
                    ),
                    TvPairDone() => const SizedBox.shrink(),
                    TvPairFailed(:final message) => _Failed(
                      message: message,
                      onRetry: _pairing.start,
                      onTypeInstead: _typeInstead,
                    ),
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  final Widget child;
  const _Centered({required this.child});

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 360, child: Center(child: child));
}

class _Waiting extends ConsumerWidget {
  final TvPairWaiting state;
  final VoidCallback onTypeInstead;
  const _Waiting({required this.state, required this.onTypeInstead});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final duck = ref.watch(
      settingsProvider.select((s) => (s.microduckEnabled, s.microduckSkin)),
    );
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (duck.$1)
                Microduck(
                  pose: resolveMicroduckPose(
                    playing: false,
                    now: DateTime.now(),
                    reducedMotion: reduced,
                  ),
                  size: 96,
                  skin: duck.$2,
                ),
              const SizedBox(height: Space.lg),
              Text('Sign in from your phone', style: t.largeTitle),
              const SizedBox(height: Space.xl),
              const _Step(1, 'Open NaviVibe on a phone that’s signed in.'),
              const _Step(2, 'Go to Settings, then Sign in another device.'),
              const _Step(3, 'Scan the QR code, or type the code.'),
              const SizedBox(height: Space.xxl),
              CupertinoClickableButton(
                label: 'Type it instead',
                autofocus: true,
                onTap: onTypeInstead,
              ),
            ],
          ),
        ),
        const SizedBox(width: Space.xxxl),
        Expanded(
          flex: 5,
          child: Semantics(
            label: 'Sign-in code ${state.code.split('').join(' ')}',
            child: Column(
              children: [
                Text(
                  PairLink.display(state.code),
                  maxLines: 1,
                  style: t.largeTitle.copyWith(
                    fontSize: 64,
                    letterSpacing: 6,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: Space.xl),
                // A QR needs dark modules on a light quiet zone to scan.
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(Space.md),
                  child: QrImageView(
                    data: state.link.uri,
                    size: 216,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      color: Colors.black,
                      eyeShape: QrEyeShape.square,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      color: Colors.black,
                      dataModuleShape: QrDataModuleShape.square,
                    ),
                  ),
                ),
                const SizedBox(height: Space.lg),
                Text(
                  'Security check ${state.fingerprint}. A typed code shows this on your phone too.',
                  textAlign: TextAlign.center,
                  style: t.footnote,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String text;
  const _Step(this.n, this.text);

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Text('$n', style: t.title2.copyWith(color: t.accent)),
          ),
          Expanded(
            child: Text(
              text,
              style: t.title3.copyWith(fontWeight: FontWeight.w400),
            ),
          ),
        ],
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onTypeInstead;
  const _Failed({
    required this.message,
    required this.onRetry,
    required this.onTypeInstead,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Couldn’t sign in', style: t.largeTitle),
        const SizedBox(height: Space.md),
        Text(
          message,
          style: t.title3.copyWith(
            fontWeight: FontWeight.w400,
            color: t.textSecondary,
          ),
        ),
        const SizedBox(height: Space.xxl),
        Row(
          children: [
            CupertinoClickableButton(
              label: 'Try again',
              autofocus: true,
              onTap: onRetry,
            ),
            const SizedBox(width: Space.lg),
            CupertinoClickableButton(
              label: 'Type it instead',
              onTap: onTypeInstead,
              quiet: true,
            ),
          ],
        ),
      ],
    );
  }
}

/// A big capsule button for the 10-foot screen (focus ring comes from CupertinoClickable).
class CupertinoClickableButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool autofocus;
  final bool quiet;
  const CupertinoClickableButton({
    super.key,
    required this.label,
    required this.onTap,
    this.autofocus = false,
    this.quiet = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return CupertinoClickable(
      onTap: onTap,
      autofocus: autofocus,
      semanticLabel: label,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: Space.xxl),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: quiet ? t.fill : t.accent,
          borderRadius: BorderRadius.circular(Radii.capsule),
        ),
        child: Text(
          label,
          style: t.headline.copyWith(color: quiet ? t.textPrimary : t.onAccent),
        ),
      ),
    );
  }
}
