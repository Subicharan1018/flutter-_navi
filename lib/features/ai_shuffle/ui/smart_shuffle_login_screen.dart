// =============================================================================
// SmartShuffleLoginScreen — shown when the shuffle server returns 401.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../providers/settings_provider.dart';
import '../data/repositories/shuffle_exception.dart';
import '../data/services/shuffle_api_service.dart';
import '../data/models/health_response.dart';

class SmartShuffleLoginScreen extends ConsumerStatefulWidget {
  final bool isDialog;

  const SmartShuffleLoginScreen({super.key, this.isDialog = false});

  @override
  ConsumerState<SmartShuffleLoginScreen> createState() =>
      _SmartShuffleLoginScreenState();
}

class _SmartShuffleLoginScreenState
    extends ConsumerState<SmartShuffleLoginScreen> {
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  bool _obscurePass = true;
  bool _isConnecting = false;
  String? _error;
  HealthResponse? _confirmedHealth;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _userCtrl = TextEditingController(text: settings.username);
    _passCtrl = TextEditingController(text: settings.password);
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _isConnecting = true;
      _error = null;
      _confirmedHealth = null;
    });

    try {
      final service = ShuffleApiService(
        username: _userCtrl.text.trim(),
        password: _passCtrl.text,
      );
      final health = await service.getHealth();

      // Persist the (possibly updated) credentials back to settings.
      await ref.read(settingsProvider.notifier).saveSettings(
            ref.read(settingsProvider).serverUrl,
            _userCtrl.text.trim(),
            _passCtrl.text,
          );

      if (!mounted) return;
      setState(() {
        _confirmedHealth = health;
        _isConnecting = false;
      });

      // Wait a beat, then pop.
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.of(context).pop(true);
    } on ShuffleAuthError catch (e) {
      setState(() {
        _error = e.message;
        _isConnecting = false;
      });
    } on ShuffleNetworkError catch (e) {
      setState(() {
        _error = e.message;
        _isConnecting = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isConnecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final body = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Icon & title ─────────────────────────────────────────────────
            Container(
              alignment: Alignment.center,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [cs.primary, cs.secondary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    color: Colors.white, size: 36),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Smart Shuffle',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Connect with your Navidrome credentials\nto enable AI-powered recommendations.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),

            // ── Success card ─────────────────────────────────────────────────
            if (_confirmedHealth != null) ...[
              _WeatherConfirmCard(health: _confirmedHealth!),
            ] else ...[
              // ── Credentials form ─────────────────────────────────────────
              TextField(
                controller: _userCtrl,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                  border: OutlineInputBorder(),
                ),
                autofillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passCtrl,
                obscureText: _obscurePass,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePass
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _connect(),
              ),

              // ── Error message ────────────────────────────────────────────
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded,
                          color: cs.onErrorContainer, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _isConnecting ? null : _connect,
                icon: _isConnecting
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: cs.onPrimary),
                      )
                    : const Icon(Icons.link_rounded),
                label: Text(_isConnecting ? 'Connecting…' : 'Connect'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],

            const SizedBox(height: 16),
            Text(
              'shuffle.subimusic.me',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );

    if (widget.isDialog) return body;
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: const CloseButton(),
        title: const Text('Connect Smart Shuffle'),
      ),
      body: body,
    );
  }
}

// ---------------------------------------------------------------------------
// Weather confirmation card shown after successful authentication.
// ---------------------------------------------------------------------------

class _WeatherConfirmCard extends StatelessWidget {
  final HealthResponse health;

  const _WeatherConfirmCard({required this.health});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final w = health.weather;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.check_circle_rounded, color: cs.primary, size: 40),
          const SizedBox(height: 12),
          Text(
            'Connected!',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.onPrimaryContainer,
            ),
          ),
          if (w != null) ...[
            const SizedBox(height: 8),
            Text(
              '${w.moodIcon}  ${w.temperatureC.toStringAsFixed(1)}°C · ${w.mood}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onPrimaryContainer,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
