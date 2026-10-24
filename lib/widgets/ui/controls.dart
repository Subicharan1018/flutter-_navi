import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import 'voice_search_button.dart';

/// iOS search field: grey rounded fill, magnifier, clear button.
class NaviSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;

  /// A microphone beside the field for voice typing (hidden where the device
  /// has no speech service).
  final bool voice;

  /// The remote's voice key starts dictation into this field.
  final bool listenForVoiceKey;

  const NaviSearchField({
    super.key,
    required this.controller,
    this.placeholder = 'Search',
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
    this.voice = true,
    this.listenForVoiceKey = false,
  });

  @override
  Widget build(BuildContext context) {
    final field = _field(context);
    if (!voice) return field;
    return Row(
      children: [
        Expanded(child: field),
        VoiceSearchButton(
          controller: controller,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          listenForVoiceKey: listenForVoiceKey,
        ),
      ],
    );
  }

  Widget _field(BuildContext context) {
    final t = ThemeTokens.of(context);
    return CupertinoSearchTextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      placeholder: placeholder,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: t.body,
      placeholderStyle: t.body.copyWith(color: t.textSecondary),
      backgroundColor: t.fill,
      itemColor: t.textSecondary,
      borderRadius: BorderRadius.circular(Radii.control),
      padding: const EdgeInsets.symmetric(horizontal: Space.xs + 2, vertical: Space.sm + 1),
    );
  }
}

/// iOS segmented control for a small set of mutually exclusive views
/// (Albums / Songs, 7 days / 30 days / All time).
class NaviSegmented<T extends Object> extends StatelessWidget {
  final Map<T, String> segments;
  final T value;
  final ValueChanged<T> onChanged;

  const NaviSegmented({super.key, required this.segments, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return SizedBox(
      width: double.infinity,
      child: CupertinoSlidingSegmentedControl<T>(
        groupValue: value,
        backgroundColor: t.fill,
        thumbColor: t.bgOverlay,
        padding: const EdgeInsets.all(2),
        onValueChanged: (v) {
          if (v == null) return;
          HapticFeedback.selectionClick();
          onChanged(v);
        },
        children: {
          for (final e in segments.entries)
            e.key: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs + 2),
              child: Text(
                e.value,
                style: t.footnote.copyWith(
                  color: t.textPrimary,
                  fontWeight: e.key == value ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
        },
      ),
    );
  }
}

/// A row of filter pills that scrolls horizontally (Library filters).
class FilterPills<T> extends StatelessWidget {
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  const FilterPills({super.key, required this.options, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    // 34pt pills inside a 44pt row, so each one is a full-size target.
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        children: [
          for (final e in options.entries)
            Padding(
              padding: const EdgeInsets.only(right: Space.sm, top: 5, bottom: 5),
              child: CupertinoClickable(
                semanticLabel: e.value,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(e.key);
                },
                child: AnimatedContainer(
                  duration: Motion.fast,
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: e.key == value ? t.accent : t.fill,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Text(
                    e.value,
                    style: t.subheadline.copyWith(
                      color: e.key == value ? t.onAccent : t.textPrimary,
                      fontWeight: FontWeight.w600,
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
