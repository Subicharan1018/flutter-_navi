import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/cover_art.dart';
import '../logic/preview_feed_providers.dart';
import 'feed_controls.dart';

/// Windows: the same feed as a keyboard list. Up/Down (or J/K) move through the songs and play each one's 30 s preview,
/// Space pauses, H or Enter hearts it. Moving past a song without hearting it is a "no", exactly like a swipe on the phone.
class PreviewFeedList extends ConsumerStatefulWidget {
  const PreviewFeedList({super.key});

  @override
  ConsumerState<PreviewFeedList> createState() => _PreviewFeedListState();
}

class _PreviewFeedListState extends ConsumerState<PreviewFeedList> {
  static const double _row = 72;
  final _scroll = ScrollController();
  final _focus = FocusNode(debugLabel: 'preview-feed-list');

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _move(int delta) async {
    final s = ref.read(previewFeedProvider);
    final to = (s.index + delta).clamp(0, s.items.length - 1);
    if (to == s.index) return;
    await ref.read(previewFeedProvider.notifier).onPage(to);
    if (!_scroll.hasClients) return;
    final top = to * _row;
    final view = _scroll.position.viewportDimension;
    if (top < _scroll.offset) {
      _scroll.animateTo(
        top,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    } else if (top + _row > _scroll.offset + view) {
      _scroll.animateTo(
        top + _row - view,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final count = ref.watch(previewFeedProvider.select((s) => s.items.length));
    final left = ref.watch(previewFeedProvider.select((s) => s.remaining));
    final ctl = ref.read(previewFeedProvider.notifier);
    return Scaffold(
      backgroundColor: t.bgBase,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                  _move(1),
              const SingleActivator(LogicalKeyboardKey.keyJ): () => _move(1),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                  _move(-1),
              const SingleActivator(LogicalKeyboardKey.keyK): () => _move(-1),
              const SingleActivator(LogicalKeyboardKey.space): ctl.togglePause,
              const SingleActivator(LogicalKeyboardKey.keyH): ctl.heart,
              const SingleActivator(LogicalKeyboardKey.enter): ctl.heart,
            },
            child: Focus(
              focusNode: _focus,
              autofocus: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                    child: Text('Swipe to fetch', style: t.title1),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      '30-second previews of songs you don’t own. ↑ ↓ to move, Space to pause, H to heart and fetch.'
                      '${left == null ? '' : '  ·  $left ${left == 1 ? 'heart' : 'hearts'} left today'}',
                      style: t.footnote,
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: _scroll,
                      itemExtent: _row,
                      itemCount: count,
                      itemBuilder: (context, i) => _FeedRow(index: i),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedRow extends ConsumerWidget {
  final int index;
  const _FeedRow({required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(previewFeedProvider.select((s) => s.items[index]));
    final selected = ref.watch(
      previewFeedProvider.select((s) => s.index == index),
    );
    final playing = ref.watch(
      previewFeedProvider.select((s) => s.index == index && s.playing),
    );
    final hearted = ref.watch(
      previewFeedProvider.select((s) => s.isHearted(item.key)),
    );
    final t = ThemeTokens.of(context);
    final ctl = ref.read(previewFeedProvider.notifier);
    return InkWell(
      onTap: () => selected
          ? unawaited(ctl.togglePause())
          : unawaited(ctl.onPage(index)),
      child: Container(
        color: selected ? t.textPrimary.withValues(alpha: 0.07) : null,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                CoverArt(url: item.artUrl, size: 52, radius: 6),
                if (selected)
                  NaviIcon(
                    playing ? NaviGlyph.pause : NaviGlyph.play,
                    size: 22,
                    color: Colors.white,
                    filled: true,
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.headline,
                  ),
                  Text(
                    '${item.artist}  ·  ${item.reason.isEmpty ? item.source.label : item.reason}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.subheadline,
                  ),
                  if (selected)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Consumer(
                        builder: (context, ref, _) {
                          final p = ref.watch(previewFeedProgressProvider);
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: p,
                              minHeight: 2,
                              color: t.textPrimary,
                              backgroundColor: t.textPrimary.withValues(
                                alpha: 0.15,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            FeedHeartButton(
              hearted: hearted,
              active: false,
              size: 44,
              color: t.textPrimary,
              onTap: () async {
                if (!selected) await ctl.onPage(index);
                await ctl.heart();
              },
            ),
          ],
        ),
      ),
    );
  }
}
