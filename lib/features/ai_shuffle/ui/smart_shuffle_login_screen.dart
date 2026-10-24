// =============================================================================
// Smart Shuffle sign-in — shown when the shuffle server rejects the saved
// credentials. Checks an authenticated endpoint (/health is public and would
// accept anything), then saves and closes.
// =============================================================================

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../providers/settings_provider.dart';
import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/ui/grouped_list.dart';
import '../data/repositories/shuffle_exception.dart';
import '../data/services/shuffle_api_service.dart';
import '../logic/shuffle_providers.dart';

class SmartShuffleLoginScreen extends ConsumerStatefulWidget {
  const SmartShuffleLoginScreen({super.key});

  @override
  ConsumerState<SmartShuffleLoginScreen> createState() => _SmartShuffleLoginScreenState();
}

class _SmartShuffleLoginScreenState extends ConsumerState<SmartShuffleLoginScreen> {
  late final _user = TextEditingController(text: ref.read(settingsProvider).username);
  late final _pass = TextEditingController(text: ref.read(settingsProvider).password);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ShuffleApiService(username: _user.text.trim(), password: _pass.text).getModelStatus();
      await ref
          .read(settingsProvider.notifier)
          .saveSettings(ref.read(settingsProvider).serverUrl, _user.text.trim(), _pass.text);
      ref.invalidate(serverHealthProvider);
      ref.invalidate(modelStatusProvider);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final page = Navigator.of(context).context;
      Navigator.of(context).pop(true);
      if (page.mounted) showToast(page, 'Smart Shuffle connected');
    } on ShuffleAuthError {
      _fail('That username and password didn’t work for Smart Shuffle.');
    } on ShuffleNetworkError {
      _fail('Can’t reach the Smart Shuffle server. Check your connection.');
    } on ShuffleServerError {
      _fail('Smart Shuffle answered with an error. It may still be building your model; try again shortly.');
    } catch (_) {
      _fail('Couldn’t connect. Try again.');
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
    return Scaffold(
      backgroundColor: t.bgBase,
      appBar: AppBar(title: Text('Smart Shuffle', style: t.headline)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Space.xxl),
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(18)),
              child: Icon(CupertinoIcons.sparkles, size: 36, color: t.onAccent),
            ),
          ),
          const SizedBox(height: Space.xl),
          Text('Reconnect Smart Shuffle', textAlign: TextAlign.center, style: t.title2),
          const SizedBox(height: Space.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xxxl),
            child: Text(
              'Smart Shuffle uses your music account. Sign in again to get personal mixes, Stats and Replay.',
              textAlign: TextAlign.center,
              style: t.subheadline,
            ),
          ),
          const SizedBox(height: Space.xxl),
          GroupedSection(
            children: [
              GroupedTextFieldRow(title: 'Username', controller: _user, placeholder: 'Required'),
              GroupedTextFieldRow(title: 'Password', controller: _pass, placeholder: 'Required', obscure: true),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xxl, 0, Space.xxl, Space.lg),
              child: Text(_error!, style: t.footnote.copyWith(color: t.danger)),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: CupertinoClickable(
              onTap: _busy ? null : _connect,
              scaleFactor: 0.97,
              semanticLabel: 'Connect',
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(Radii.capsule)),
                child: _busy
                    ? CupertinoActivityIndicator(color: t.onAccent)
                    : Text('Connect', style: t.headline.copyWith(color: t.onAccent)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
