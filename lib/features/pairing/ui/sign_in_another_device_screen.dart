import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme.dart';
import '../../../providers/settings_provider.dart';
import '../../../utils/platform_utils.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/grouped_list.dart';
import '../../../widgets/ui/large_title_page.dart';
import '../pair_crypto.dart';
import '../pair_link.dart';
import '../pair_providers.dart';
import '../pair_relay.dart';
import '../phone_pairing.dart';

// =============================================================================
// Settings → Sign in another device. The TV shows a code and a QR; scan the QR
// or type the code here, check the numbers match, and this device sends its
// login to the TV end-to-end encrypted (the server only relays ciphertext).
// =============================================================================

enum _Step { enter, confirm, sending, sent }

class SignInAnotherDeviceScreen extends ConsumerStatefulWidget {
  /// Tests inject a relay.
  final PairRelay? relay;
  const SignInAnotherDeviceScreen({super.key, this.relay});

  @override
  ConsumerState<SignInAnotherDeviceScreen> createState() => _SignInAnotherDeviceScreenState();
}

class _SignInAnotherDeviceScreenState extends ConsumerState<SignInAnotherDeviceScreen> {
  final _code = TextEditingController();
  _Step _step = _Step.enter;
  PairTarget? _target;
  String? _error;
  bool _busy = false;

  late final PhonePairing _pairing = PhonePairing(widget.relay ?? ref.read(pairRelayProvider));

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _fail(Object e) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = e is FormatException
          ? e.message
          : e is PairRelayException
              ? e.message
              : 'Something went wrong. Try again.';
    });
  }

  Future<void> _lookup() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final target = await _pairing.fromTypedCode(_code.text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _target = target;
        _step = _Step.confirm;
      });
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _scan() async {
    final text = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _ScanScreen(), fullscreenDialog: true),
    );
    if (text == null || !mounted) return;
    final link = PairLink.parse(text);
    if (link == null) {
      setState(() => _error = 'That isn’t a NaviVibe sign-in code. Scan the one on your TV.');
      return;
    }
    final target = await _pairing.fromLink(link);
    if (!mounted) return;
    setState(() {
      _error = null;
      _target = target;
      _step = _Step.confirm;
    });
  }

  Future<void> _send() async {
    final target = _target;
    if (target == null || _busy) return;
    final s = ref.read(settingsProvider);
    setState(() {
      _busy = true;
      _step = _Step.sending;
      _error = null;
    });
    try {
      await _pairing.send(
        target,
        PairCredentials(serverUrl: s.serverUrl, username: s.username, password: s.password),
      );
      HapticFeedback.mediumImpact();
      if (mounted) {
        setState(() {
          _busy = false;
          _step = _Step.sent;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _step = _Step.confirm);
      _fail(e);
    }
  }

  void _again() => setState(() {
        _step = _Step.enter;
        _target = null;
        _error = null;
        _code.clear();
      });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final s = ref.watch(settingsProvider);
    final host = Uri.tryParse(s.serverUrl)?.host ?? s.serverUrl;
    final canScan = PlatformUtils.isAndroid || PlatformUtils.isIOS;
    return LargeTitlePage(
      title: 'Sign in another device',
      clearPlayer: false,
      slivers: [
        SliverList.list(children: [
          const SizedBox(height: Space.sm),
          if (_step == _Step.enter) ...[
            GroupedSection(
              header: 'On your TV',
              footer: 'Open NaviVibe on the TV. It shows a code and a QR. Your login is encrypted '
                  'on this device and can only be opened by that TV.',
              children: [
                GroupedTextFieldRow(
                  title: 'Code',
                  icon: NaviGlyph.link,
                  controller: _code,
                  placeholder: 'ABC 123',
                  autofocus: true,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _lookup(),
                ),
                if (canScan) GroupedRow(title: 'Scan the QR code', icon: NaviGlyph.camera, onTap: _scan),
              ],
            ),
            _Action(label: 'Continue', busy: _busy, onTap: _lookup),
          ],
          if (_step == _Step.confirm || _step == _Step.sending) ...[
            GroupedSection(
              header: 'Sign in this TV',
              footer: _target!.keyFromQr
                  ? 'The TV’s QR code matched.'
                  : 'Check that the TV shows the same security numbers. If it doesn’t, cancel.',
              children: [
                GroupedRow(title: 'Account', icon: NaviGlyph.person, value: s.username, showChevron: false),
                GroupedRow(title: 'Server', icon: NaviGlyph.cloud, value: host, showChevron: false),
                GroupedRow(title: 'Security', icon: NaviGlyph.lock, value: _target!.fingerprint, showChevron: false),
              ],
            ),
            _Action(label: 'Sign in the TV', busy: _step == _Step.sending, onTap: _send),
            _Action(label: 'Cancel', quiet: true, onTap: _again),
          ],
          if (_step == _Step.sent) ...[
            GroupedSection(
              header: 'Sent',
              footer: 'The TV is signing in as ${s.username}. This can take a few seconds.',
              children: [GroupedRow(title: 'Sign in another TV', icon: NaviGlyph.plus, onTap: _again)],
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xxl, Space.sm, Space.xxl, Space.lg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NaviIcon(NaviGlyph.alert, size: 16, color: t.danger, filled: true),
                  const SizedBox(width: Space.sm),
                  Expanded(child: Text(_error!, style: t.footnote.copyWith(color: t.danger))),
                ],
              ),
            ),
        ]),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool busy;
  final bool quiet;
  const _Action({required this.label, required this.onTap, this.busy = false, this.quiet = false});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.sm),
      child: CupertinoClickable(
        onTap: busy ? null : onTap,
        focusRadius: Radii.capsule,
        scaleFactor: 0.97,
        semanticLabel: label,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: quiet ? t.fill : t.accent,
            borderRadius: BorderRadius.circular(Radii.capsule),
          ),
          child: busy
              ? CupertinoActivityIndicator(color: t.onAccent)
              : Text(label, style: t.headline.copyWith(color: quiet ? t.textPrimary : t.onAccent)),
        ),
      ),
    );
  }
}

/// Full-screen camera that returns the first QR code it reads.
class _ScanScreen extends StatefulWidget {
  const _ScanScreen();

  @override
  State<_ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<_ScanScreen> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            onDetect: (capture) {
              final text = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
              if (text == null || _done) return;
              _done = true;
              Navigator.of(context).pop(text);
            },
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(Space.xxl),
                child: Text(
                  'NaviVibe can’t use the camera. Allow it in Settings, or type the code instead.',
                  textAlign: TextAlign.center,
                  style: t.body.copyWith(color: Colors.white),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(Space.md),
                child: CupertinoClickable(
                  onTap: () => Navigator.of(context).pop(),
                  semanticLabel: 'Close',
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(child: NaviIcon(NaviGlyph.close, size: 24, color: Colors.white)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
