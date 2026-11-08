import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/app_scaffold.dart' show navigateInApp;
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/large_title_page.dart';
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/states.dart';
import '../data/social_models.dart';
import '../logic/reaction_rules.dart';
import '../logic/recap_providers.dart';
import '../logic/social_providers.dart';
import 'blend_screens.dart' show BlendScreen;
import 'social_widgets.dart';

/// "3 h 12 min listened · 54 plays": the big number of the week.
class _Headline extends StatelessWidget {
  final WeeklyRecap recap;
  const _Headline(this.recap);

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(recapDuration(recap.minutes), style: t.largeTitle),
      Text('listened · ${recap.plays} ${recap.plays == 1 ? 'play' : 'plays'}', style: t.subheadline),
    ]);
  }
}

/// Social hub: one line per Blend friend for the past week, opening the full
/// recap. Absent when social is off, the server has no recap, or there is
/// nothing to say.
class RecapSection extends ConsumerWidget {
  const RecapSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recap = ref.watch(recapProvider).asData?.value;
    if (recap == null || !recap.hasContent) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(title: 'Your week', onTap: () => navigateInApp(context, const RecapScreen())),
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.sm),
        child: _Headline(recap),
      ),
      for (final (i, f) in recap.friends.indexed) _RecapFriendRow(friend: f, showSeparator: i < recap.friends.length - 1),
    ]);
  }
}

class _RecapFriendRow extends StatelessWidget {
  final RecapFriend friend;
  final bool showSeparator;
  const _RecapFriendRow({required this.friend, required this.showSeparator});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final line = recapFriendLine(friend);
    return CupertinoClickable(
      onTap: () => navigateInApp(context, const RecapScreen()),
      scaleFactor: 0.99,
      semanticLabel: 'You and ${friend.username}, $line',
      child: Container(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.sm),
        decoration: showSeparator ? BoxDecoration(border: Border(bottom: BorderSide(color: t.outline, width: 0.5))) : null,
        child: Row(children: [
          PersonAvatar(friend.username, size: 40),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('You + ${friend.username}', style: t.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(line, style: t.subheadline, maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Home: the weekly recap as a plain section (no card), once a week. "Not now"
/// hides it until next week; the same recap stays in Social.
class HomeRecapSection extends ConsumerWidget {
  const HomeRecapSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recap = ref.watch(homeRecapProvider);
    if (recap == null) return const SizedBox.shrink();
    final t = ThemeTokens.of(context);
    final best = closestFriend(recap);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(title: 'Your week', onTap: () => navigateInApp(context, const RecapScreen())),
      CupertinoClickable(
        onTap: () => navigateInApp(context, const RecapScreen()),
        scaleFactor: 0.99,
        semanticLabel: 'Your week, ${recapDuration(recap.minutes)} listened',
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.sm),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _Headline(recap),
                if (best != null) ...[
                  const SizedBox(height: Space.sm),
                  Text('Closest to ${best.username}: ${recapFriendLine(best)}', style: t.footnote, maxLines: 2),
                ],
              ]),
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              minimumSize: const Size(44, 44),
              onPressed: () => ref.read(recapDismissedProvider.notifier).dismissThisWeek(),
              child: Text('Not now', style: t.subheadline.copyWith(color: t.textSecondary)),
            ),
          ]),
        ),
      ),
    ]);
  }
}

// ── full screen ──────────────────────────────────────────────────────────────

class RecapScreen extends ConsumerWidget {
  const RecapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recapProvider);
    final recap = async.asData?.value;
    return LargeTitlePage(
      title: 'Weekly recap',
      onRefresh: () async => ref.invalidate(recapProvider),
      slivers: [
        if (async.isLoading && recap == null)
          const SliverToBoxAdapter(child: LoadingState())
        else if (async.hasError && recap == null)
          SliverToBoxAdapter(
            child: SocialNote(
              glyph: NaviGlyph.blend,
              title: 'Couldn’t load your week',
              message: 'Check your connection to the server, then try again.',
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(recapProvider),
            ),
          )
        else if (recap == null || !recap.hasContent)
          const SliverToBoxAdapter(
            child: SocialNote(
              glyph: NaviGlyph.blend,
              title: 'Nothing to recap yet',
              message: 'Start a Blend with a friend and listen through the week. Your recap appears here.',
            ),
          )
        else
          SliverToBoxAdapter(child: RecapBody(recap: recap)),
      ],
    );
  }
}

class RecapBody extends StatelessWidget {
  final WeeklyRecap recap;
  const RecapBody({super.key, required this.recap});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.md),
        child: _Headline(recap),
      ),
      if (recap.topArtists.isNotEmpty) ...[
        const SectionHeader(title: 'Your top artists'),
        for (final (i, a) in recap.topArtists.indexed) _Line(rank: i + 1, title: a.name, trailing: '${a.you} plays'),
      ],
      if (recap.topSongs.isNotEmpty) ...[
        const SectionHeader(title: 'Your top songs'),
        for (final (i, s) in recap.topSongs.indexed) _Line(rank: i + 1, title: s.name, trailing: '${s.you} plays'),
      ],
      for (final f in recap.friends) ...[
        SectionHeader(title: 'You + ${f.username}'),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.sm),
          child: Row(children: [
            Expanded(child: Text(recapFriendLine(f), style: t.subheadline)),
            if (f.blendId.isNotEmpty)
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                onPressed: () => navigateInApp(context, BlendScreen(id: f.blendId)),
                child: Text('Open Blend', style: t.subheadline.copyWith(color: t.accent, fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
        if (f.theirMinutes != null)
          _Line(
            title: 'Listening time',
            trailing: 'You ${recapDuration(recap.minutes)} · ${f.username} ${recapDuration(f.theirMinutes!)}',
          ),
        for (final a in f.sharedArtists) _Line(title: a.name, subtitle: 'Shared artist', trailing: '${a.you} · ${a.them}'),
        for (final s in f.sharedSongs) _Line(title: s.name, subtitle: 'Shared song', trailing: '${s.you} · ${s.them}'),
        if (f.hidden) const SocialFootnote('They hide what they listen to, so only the match is shown.'),
      ],
      const SocialFootnote('Counts are plays this week. Shared items show your plays, then theirs.'),
      const SizedBox(height: Space.xxl),
    ]);
  }
}

class _Line extends StatelessWidget {
  final int? rank;
  final String title;
  final String? subtitle;
  final String trailing;
  const _Line({this.rank, required this.title, this.subtitle, required this.trailing});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.sm),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.outline, width: 0.5))),
      child: Row(children: [
        if (rank != null) SizedBox(width: 28, child: Text('$rank', style: t.subheadline)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.body, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (subtitle != null) Text(subtitle!, style: t.footnote),
          ]),
        ),
        const SizedBox(width: Space.md),
        Flexible(child: Text(trailing, style: t.subheadline, maxLines: 2, textAlign: TextAlign.end)),
      ]),
    );
  }
}
