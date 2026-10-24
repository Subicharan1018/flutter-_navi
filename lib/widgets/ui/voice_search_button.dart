import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../services/voice_input.dart';
import '../../utils/platform_utils.dart';
import '../art/navi_icons.dart';

/// Bumped by the remote's voice / search key; a field that opted in
/// (`listenForVoiceKey`) starts listening when it changes.
final ValueNotifier<int> voiceKeyPresses = ValueNotifier<int>(0);

/// A microphone for a text field: tap, speak, and the words land in
/// [controller] as they are recognised. Hidden where there is no speech
/// service to ask, and says so plainly when the device has none.
class VoiceSearchButton extends StatefulWidget {
  final TextEditingController controller;

  /// Called with the transcript as it grows (partial) and when final.
  final ValueChanged<String>? onChanged;

  /// Called once with the final transcript, as if the user pressed search.
  final ValueChanged<String>? onSubmitted;

  /// Start when the remote's voice key is pressed.
  final bool listenForVoiceKey;

  const VoiceSearchButton({
    super.key,
    required this.controller,
    this.onChanged,
    this.onSubmitted,
    this.listenForVoiceKey = false,
  });

  @override
  State<VoiceSearchButton> createState() => VoiceSearchButtonState();
}

class VoiceSearchButtonState extends State<VoiceSearchButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  bool _listening = false;
  int _seenKey = voiceKeyPresses.value;

  @override
  void initState() {
    super.initState();
    if (widget.listenForVoiceKey) voiceKeyPresses.addListener(_onVoiceKey);
  }

  @override
  void dispose() {
    voiceKeyPresses.removeListener(_onVoiceKey);
    if (_listening) VoiceInput.engine.stop();
    _pulse.dispose();
    super.dispose();
  }

  void _onVoiceKey() {
    if (voiceKeyPresses.value == _seenKey) return;
    _seenKey = voiceKeyPresses.value;
    start();
  }

  /// Starts (or, if already listening, stops) a dictation.
  Future<void> start() async {
    final engine = VoiceInput.engine;
    if (_listening) {
      await engine.stop();
      return;
    }
    HapticFeedback.selectionClick();
    var heard = '';
    setState(() => _listening = true);
    _pulse.repeat(reverse: true);
    final started = await engine.start(
      onText: (text, isFinal) {
        heard = text;
        if (!mounted) return;
        widget.controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        widget.onChanged?.call(text);
      },
      onDone: (failure) {
        if (!mounted) return;
        _pulse
          ..stop()
          ..value = 0;
        setState(() => _listening = false);
        if (failure != null) _explain(failure);
        if (failure == null && heard.trim().isNotEmpty) widget.onSubmitted?.call(heard.trim());
      },
    );
    if (!started && mounted) setState(() => _listening = false);
  }

  void _explain(VoiceFailure failure) {
    final tv = PlatformUtils.isTv;
    final message = switch (failure) {
      VoiceFailure.denied => 'Allow the microphone for NaviVibe to type by voice.',
      VoiceFailure.unavailable =>
        tv ? 'Voice typing isn’t available here. Use the on-screen keyboard.' : 'Voice typing isn’t available on this device.',
      VoiceFailure.error => 'Couldn’t hear that. Try again.',
    };
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    if (!VoiceInput.engine.supportedPlatform) return const SizedBox.shrink();
    final t = ThemeTokens.of(context);
    final size = PlatformUtils.isTv ? 56.0 : 44.0;
    return Semantics(
      button: true,
      label: _listening ? 'Stop voice typing' : 'Type by voice',
      child: CupertinoClickable(
        onTap: start,
        scaleFactor: 0.92,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (_, child) => Container(
                width: 34 + (_listening ? _pulse.value * 6 : 0),
                height: 34 + (_listening ? _pulse.value * 6 : 0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _listening ? t.accent : Colors.transparent,
                ),
                alignment: Alignment.center,
                child: child,
              ),
              child: NaviIcon(NaviGlyph.mic, size: 22, color: _listening ? t.onAccent : t.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}
