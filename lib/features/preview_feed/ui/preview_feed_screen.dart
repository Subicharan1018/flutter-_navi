import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion.dart';
import '../../../core/theme.dart';
import '../../../utils/platform_utils.dart';
import '../../../widgets/app_scaffold.dart' show navigateInApp;
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/cover_art.dart';
import '../../../widgets/ui/action_sheet.dart' show showToast;
import '../data/preview_models.dart';
import '../logic/preview_feed_providers.dart';
import 'art_tint.dart';
import 'feed_controls.dart';
import 'preview_feed_list.dart';

/// Opens Swipe to fetch: a full-screen pager on a phone or TV, a keyboard list inside the app on Windows.
void openPreviewFeed(BuildContext context) {
  if (PlatformUtils.isDesktop && !PlatformUtils.isTv) {
    navigateInApp(context, const PreviewFeedScreen(), title: 'Swipe to fetch');
    return;
  }
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => const PreviewFeedScreen(),
      transitionsBuilder: (context, a, _, child) {
        final curved = CurvedAnimation(
          parent: a,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        if (!context.motionFullNow) {
          return FadeTransition(opacity: curved, child: child);
        }
        return SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    ),
  );
}

/// Swipe to fetch: 30 s previews of songs that are not in the library. Swipe up for the next, heart to fetch. The main queue is
/// never touched: the feed has its own player, and the listener's music is paused for the visit and resumed after it.
class PreviewFeedScreen extends ConsumerStatefulWidget {
  const PreviewFeedScreen({super.key});

  @override
  ConsumerState<PreviewFeedScreen> createState() => _PreviewFeedScreenState();
}

class _PreviewFeedScreenState extends ConsumerState<PreviewFeedScreen> {
  late final PreviewFeedController _ctl = ref.read(
    previewFeedProvider.notifier,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_ctl.open()));
  }

  @override
  void dispose() {
    unawaited(_ctl.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(previewFeedProvider.select((s) => s.note), (_, note) {
      if (note == null) return;
      showToast(context, note);
      _ctl.ackNote();
    });
    final load = ref.watch(previewFeedProvider.select((s) => s.load));
    final desktop = PlatformUtils.isDesktop && !PlatformUtils.isTv;
    final Widget body = switch (load) {
      FeedLoad.loading => const _Centered(child: _Loading()),
      FeedLoad.error => _Centered(
        child: _Message(
          title: 'The feed didn’t load',
          message:
              ref.watch(previewFeedProvider.select((s) => s.error)) ??
              'Check your connection and try again.',
          action: 'Try again',
          onAction: _ctl.load,
        ),
      ),
      FeedLoad.ready => desktop ? const PreviewFeedList() : const _Pager(),
    };
    if (desktop) return body;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: body),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: _TopBar(onClose: () => Navigator.of(context).maybePop()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends ConsumerWidget {
  final VoidCallback onClose;
  const _TopBar({required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final left = ref.watch(previewFeedProvider.select((s) => s.remaining));
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 20, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: const NaviIcon(
              NaviGlyph.close,
              size: 22,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          if (left != null)
            Text(
              left == 0
                  ? 'No hearts left today'
                  : (left == 1
                        ? '1 heart left today'
                        : '$left hearts left today'),
              style: t.textStyle(
                13,
                FontWeight.w500,
                Colors.white.withValues(alpha: 0.72),
              ),
            ),
        ],
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  final Widget child;
  const _Centered({required this.child});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: Center(child: child),
  );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
        const SizedBox(height: 18),
        Text(
          'Finding songs you don’t own',
          style: t.textStyle(
            15,
            FontWeight.w500,
            Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  final String title;
  final String message;
  final String action;
  final VoidCallback onAction;
  const _Message({
    required this.title,
    required this.message,
    required this.action,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: t.textStyle(22, FontWeight.w700, Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: t.textStyle(
              15,
              FontWeight.w400,
              Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 22),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: Colors.black,
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
              shape: const StadiumBorder(),
            ),
            child: Text(
              action,
              style: t.textStyle(15, FontWeight.w600, Colors.black),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Pager extends ConsumerStatefulWidget {
  const _Pager();

  @override
  ConsumerState<_Pager> createState() => _PagerState();
}

class _PagerState extends ConsumerState<_Pager> {
  final _page = PageController();
  bool _swiped = false;
  Timer? _auto;

  @override
  void dispose() {
    _auto?.cancel();
    _page.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final n = ref.read(previewFeedProvider).items.length + 1;
    final to = ((_page.page ?? 0).round() + delta).clamp(0, n - 1);
    final dur = context.motionFullNow
        ? const Duration(milliseconds: 360)
        : Duration.zero;
    _page.animateToPage(to, duration: dur, curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final ctl = ref.read(previewFeedProvider.notifier);
    final count = ref.watch(previewFeedProvider.select((s) => s.items.length));
    final exhausted = ref.watch(previewFeedProvider.select((s) => s.exhausted));
    final moreComing = ref.watch(
      previewFeedProvider.select((s) => s.loadingMore),
    );
    final tv = PlatformUtils.isTv;
    if (tv) {
      // Lean-back: when a clip ends the next one starts by itself.
      ref.listen(previewFeedProgressProvider, (prev, p) {
        if (p >= 1 && (prev ?? 0) < 1) {
          _auto?.cancel();
          _auto = Timer(const Duration(milliseconds: 900), () {
            if (mounted) _go(1);
          });
        }
      });
    }
    final pager = PageView.builder(
      scrollDirection: Axis.vertical,
      controller: _page,
      itemCount: count + (exhausted || moreComing ? 1 : 0),
      onPageChanged: (i) {
        if (!_swiped) setState(() => _swiped = true);
        unawaited(ctl.onPage(i));
      },
      itemBuilder: (context, i) => i >= count
          ? _Centered(
              child: moreComing && !exhausted
                  ? const _Loading()
                  : _Message(
                      title: 'You’ve heard what’s new',
                      message:
                          'Check back later: more songs turn up as the charts and new releases move.',
                      action: 'Look again',
                      onAction: ctl.load,
                    ),
            )
          : _FeedPage(
              index: i,
              showHint: !_swiped && i == 0,
              onNext: tv ? () => _go(1) : null,
            ),
    );
    if (!tv) return pager;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _go(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _go(-1),
        const SingleActivator(LogicalKeyboardKey.mediaTrackNext): () => _go(1),
      },
      child: Focus(autofocus: true, child: pager),
    );
  }
}

class _FeedPage extends ConsumerWidget {
  final int index;
  final bool showHint;
  final VoidCallback? onNext;
  const _FeedPage({required this.index, required this.showHint, this.onNext});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(
      previewFeedProvider.select(
        (s) => index < s.items.length ? s.items[index] : null,
      ),
    );
    if (item == null) return const SizedBox.shrink();
    final active = ref.watch(
      previewFeedProvider.select((s) => s.index == index),
    );
    final playing = ref.watch(
      previewFeedProvider.select((s) => s.index == index && s.playing),
    );
    final hearted = ref.watch(
      previewFeedProvider.select((s) => s.isHearted(item.key)),
    );
    final ctl = ref.read(previewFeedProvider.notifier);
    final t = ThemeTokens.of(context);

    return TintedBackdrop(
      keyName: item.key,
      artUrl: item.artUrl,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: active ? ctl.togglePause : null,
        onDoubleTap: active ? ctl.heart : null,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 56, 28, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(flex: 2),
                Flexible(
                  flex: 12,
                  child: Center(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final side = c.biggest.shortestSide.clamp(120.0, 380.0);
                        return _Art(
                          item: item,
                          side: side,
                          paused: active && !playing,
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                FeedWaveform(seed: item.key, playing: playing),
                const SizedBox(height: 18),
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.textStyle(24, FontWeight.w700, Colors.white),
                ),
                const SizedBox(height: 3),
                Text(
                  item.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.textStyle(
                    17,
                    FontWeight.w400,
                    Colors.white.withValues(alpha: 0.78),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.reason.isEmpty ? item.source.label : item.reason,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.textStyle(
                    13,
                    FontWeight.w500,
                    Colors.white.withValues(alpha: 0.5),
                  ),
                ),
                const Spacer(flex: 1),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (onNext != null) ...[
                      IconButton(
                        tooltip: 'Next song',
                        iconSize: 30,
                        onPressed: onNext,
                        icon: const RotatedBox(
                          quarterTurns: 1,
                          child: NaviIcon(
                            NaviGlyph.chevron,
                            size: 28,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 24),
                    ],
                    FeedHeartButton(
                      hearted: hearted,
                      active: active,
                      onTap: ctl.heart,
                      autofocus: onNext != null && active,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 20,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: showHint
                          ? Text(
                              'Swipe up for the next song',
                              key: const ValueKey('hint'),
                              style: t.textStyle(
                                13,
                                FontWeight.w500,
                                Colors.white.withValues(alpha: 0.5),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Art extends StatelessWidget {
  final PreviewItem item;
  final double side;
  final bool paused;
  const _Art({required this.item, required this.side, required this.paused});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: side,
      height: side,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: CoverArt(url: item.artUrl, size: side, radius: 18),
          ),
          // Paused: the cover dims a little and a pause mark rests on it (a tap resumes).
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: paused ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: Colors.black.withValues(alpha: 0.38),
                ),
                child: const Center(
                  child: NaviIcon(
                    NaviGlyph.play,
                    size: 54,
                    color: Colors.white,
                    filled: true,
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
