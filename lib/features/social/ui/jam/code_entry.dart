import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../../core/motion.dart';
import '../../../../core/theme.dart';

/// Letters a Jam code is made of (the server leaves out 0 O 1 I).
const String jamCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const int jamCodeLength = 6;

/// Cleans typed or pasted text into the characters a code can hold.
String cleanJamCode(String raw) {
  final up = raw.toUpperCase();
  final out = StringBuffer();
  for (final ch in up.split('')) {
    if (jamCodeAlphabet.contains(ch)) out.write(ch);
  }
  final s = out.toString();
  return s.length > jamCodeLength ? s.substring(0, jamCodeLength) : s;
}

/// Six seats for a code. Each letter drops into its seat as it is typed; the
/// last one calls [onComplete]. A real text field sits under the seats so the
/// keyboard, paste and autofill all work.
class JamCodeEntry extends StatefulWidget {
  final ValueChanged<String> onComplete;
  final bool enabled;
  const JamCodeEntry({super.key, required this.onComplete, this.enabled = true});

  @override
  State<JamCodeEntry> createState() => JamCodeEntryState();
}

class JamCodeEntryState extends State<JamCodeEntry> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String _code = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
  }

  void _changed() {
    final clean = cleanJamCode(_controller.text);
    if (clean != _controller.text) {
      _controller.value = TextEditingValue(text: clean, selection: TextSelection.collapsed(offset: clean.length));
      return;
    }
    if (clean == _code) return;
    setState(() => _code = clean);
    if (clean.length == jamCodeLength) {
      HapticFeedback.selectionClick();
      _focus.unfocus();
      widget.onComplete(clean);
    }
  }

  /// Lets the screen clear the seats after a wrong code.
  void clear() {
    _controller.clear();
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final motion = context.motionFull;
    return Semantics(
      textField: true,
      label: 'Jam code, $jamCodeLength characters',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _focus.requestFocus(),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < jamCodeLength; i++) ...[
                if (i > 0) const SizedBox(width: Space.sm),
                _Seat(
                  char: i < _code.length ? _code[i] : null,
                  active: i == _code.length && _focus.hasFocus,
                  motion: motion,
                  tokens: t,
                ),
              ],
            ]),
            // The real field: invisible, full size, receives the keyboard.
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                child: CupertinoTextField(
                  controller: _controller,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.characters,
                  keyboardType: TextInputType.visiblePassword,
                  inputFormatters: [LengthLimitingTextInputFormatter(24)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Seat extends StatelessWidget {
  final String? char;
  final bool active;
  final bool motion;
  final AppThemeTokens tokens;
  const _Seat({required this.char, required this.active, required this.motion, required this.tokens});

  @override
  Widget build(BuildContext context) {
    final filled = char != null;
    return AnimatedContainer(
      duration: motion ? Motion.fast : Duration.zero,
      curve: Motion.ease,
      width: 44,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? tokens.textPrimary : tokens.fill,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(
          color: active ? tokens.textPrimary : tokens.outline,
          width: active ? 1.5 : 0.5,
        ),
      ),
      child: AnimatedScale(
        scale: filled ? 1 : 0.4,
        duration: motion ? Motion.standard : Duration.zero,
        curve: Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: filled ? 1 : 0,
          duration: motion ? Motion.fast : Duration.zero,
          child: Text(char ?? '', style: tokens.title2.copyWith(color: tokens.bgBase)),
        ),
      ),
    );
  }
}
