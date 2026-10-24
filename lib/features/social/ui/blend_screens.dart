import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../providers/player_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../widgets/app_scaffold.dart' show navigateInApp;
import '../../../widgets/art/generated_cover.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/cover_art.dart';
import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/ui/large_title_page.dart';
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/states.dart';
import '../data/social_api.dart';
import '../data/social_models.dart';
import '../logic/social_providers.dart';
import 'social_widgets.dart';

String _msg(Object e) => e is SocialException ? e.message : 'Something went wrong. Try again.';

Widget _blendCover(Blend b, double size) => SizedBox(
      width: size,
      height: size,
      child: GeneratedCover(name: 'blend ${b.withUser}', songIds: [b.id], borderRadius: Radii.cover),
    );

// ── hub section ──────────────────────────────────────────────────────────────

class BlendSection extends ConsumerWidget {
  const BlendSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(socialEnabledProvider)) return const SizedBox.shrink();
    final t = ThemeTokens.of(context);
    final blends = ref.watch(blendListProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHeader(title: 'Blends'),
      blends.when(
        loading: () => const Padding(padding: EdgeInsets.all(Space.xl), child: Center(child: CupertinoActivityIndicator())),
        error: (_, _) => SocialNote(
          glyph: NaviGlyph.blend,
          title: 'Couldn’t load Blends',
          message: 'Check your connection to the server, then try again.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(blendListProvider),
        ),
        data: (items) => Column(children: [
          for (final b in items) _BlendRow(blend: b),
          if (items.isEmpty)
            const SocialFootnote('A Blend is a playlist of music you and a friend both like, refreshed every day. You both have to say yes.'),
          CollectionRow(
            title: 'Start a Blend',
            leading: SizedBox(width: 30, child: NaviIcon(NaviGlyph.blend, size: 24, color: t.accent)),
            showChevron: false,
            showSeparator: false,
            onTap: () => _invite(context, ref, items),
          ),
        ]),
      ),
    ]);
  }

  Future<void> _invite(BuildContext context, WidgetRef ref, List<Blend> existing) async {
    final who = await pickPerson(context, ref, title: 'Blend with…', skip: {for (final b in existing) b.withUser});
    if (who == null) return;
    try {
      await ref.read(socialApiProvider).blendInvite(who);
      ref.invalidate(blendListProvider);
      if (context.mounted) showToast(context, 'Invite sent to $who');
    } catch (e) {
      if (context.mounted) showToast(context, _msg(e));
    }
  }
}

class _BlendRow extends ConsumerWidget {
  final Blend blend;
  const _BlendRow({required this.blend});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final b = blend;
    if (b.pending && b.incoming) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.sm),
        child: Row(children: [
          _blendCover(b, 52),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Blend with ${b.withUser}', style: t.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('Wants to blend tastes', style: t.footnote),
            ]),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            minimumSize: const Size(44, 44),
            onPressed: () => _answer(context, ref, false),
            child: Text('Decline', style: t.body.copyWith(color: t.textSecondary)),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            minimumSize: const Size(44, 44),
            onPressed: () => _answer(context, ref, true),
            child: Text('Accept', style: t.headline.copyWith(color: t.accent)),
          ),
        ]),
      );
    }
    final subtitle = b.pending
        ? 'Waiting for ${b.withUser} to accept'
        : b.paused
            ? 'Paused'
            : (b.matchPct == null ? 'Tap to see your Blend' : '${b.matchPct}% match');
    return CollectionRow(
      title: 'You + ${b.withUser}',
      subtitle: subtitle,
      leading: _blendCover(b, 52),
      onTap: () => navigateInApp(context, BlendScreen(id: b.id)),
    );
  }

  Future<void> _answer(BuildContext context, WidgetRef ref, bool accept) async {
    try {
      await ref.read(socialApiProvider).blendRespond(blend.id, accept);
      ref.invalidate(blendListProvider);
    } catch (e) {
      if (context.mounted) showToast(context, _msg(e));
    }
  }
}

// ── detail ───────────────────────────────────────────────────────────────────

class BlendScreen extends ConsumerWidget {
  final String id;
  const BlendScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(blendDetailProvider(id));
    return async.when(
      loading: () => const LargeTitlePage(title: 'Blend', slivers: [SliverToBoxAdapter(child: LoadingState())]),
      error: (e, _) => LargeTitlePage(title: 'Blend', slivers: [
        SliverToBoxAdapter(
          child: SocialNote(
            glyph: NaviGlyph.blend,
            title: 'Couldn’t open this Blend',
            message: 'Check your connection to the server, then try again.',
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(blendDetailProvider(id)),
          ),
        ),
      ]),
      data: (b) => _BlendBody(blend: b),
    );
  }
}

class _BlendBody extends ConsumerWidget {
  final Blend blend;
  const _BlendBody({required this.blend});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final b = blend;
    final svc = ref.read(subsonicServiceProvider);
    final me = ref.read(settingsProvider).username.toLowerCase();
    final byId = ref.watch(socialSongsProvider(b.songs.map((s) => s.songId).join(','))).asData?.value ?? const {};
    final playable = [for (final s in b.songs) if (byId[s.songId] != null) byId[s.songId]!];

    String from(BlendSong s) {
      if (s.from == 'both') return 'You both';
      return s.from.toLowerCase() == me ? 'From you' : 'From ${s.from}';
    }

    Widget note(NaviGlyph g, String title, String message) =>
        SliverToBoxAdapter(child: SocialNote(glyph: g, title: title, message: message));

    return LargeTitlePage(
      title: 'You + ${b.withUser}',
      onRefresh: () async => ref.invalidate(blendDetailProvider(b.id)),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: () async {
          final sure = await confirmDestructive(
            context,
            title: 'Leave this Blend?',
            message: 'It is removed for you and ${b.withUser}.',
            confirmLabel: 'Leave',
          );
          if (!sure) return;
          try {
            await ref.read(socialApiProvider).blendLeave(b.id);
            ref.invalidate(blendListProvider);
            if (context.mounted) Navigator.of(context).pop();
          } catch (e) {
            if (context.mounted) showToast(context, _msg(e));
          }
        },
        child: Text('Leave', style: t.body.copyWith(color: t.danger)),
      ),
      slivers: [
        if (b.pending)
          note(NaviGlyph.blend, b.incoming ? 'Accept to start' : 'Waiting for ${b.withUser}',
              b.incoming ? 'Accept the invite on the Social page.' : 'Your Blend starts once they accept.')
        else if (b.paused)
          note(NaviGlyph.blend, 'Blend paused',
              'One of you turned social features off. Turn them back on in Settings to see it again.')
        else if (b.notEnoughListening)
          note(NaviGlyph.blend, 'Not enough listening yet',
              'A Blend needs a little more listening from both of you. Check back in a few days.')
        else ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.md),
              child: Row(children: [
                _blendCover(b, 96),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(b.matchPct == null ? 'Blend' : '${b.matchPct}% match', style: t.title2),
                    Text('${b.songs.length} songs · refreshed ${b.refreshedOn ?? 'today'}', style: t.footnote),
                    const SizedBox(height: Space.sm),
                    SocialButton(
                      label: 'Play',
                      onPressed: playable.isEmpty
                          ? null
                          : () => ref.read(playerProvider.notifier).setQueue(playable, 0, playlistName: 'You + ${b.withUser}'),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
          SliverList.builder(
            itemCount: b.songs.length,
            itemBuilder: (context, i) {
              final s = b.songs[i];
              final song = byId[s.songId];
              return CupertinoClickable(
                onTap: song == null
                    ? null
                    : () => ref.read(playerProvider.notifier).setQueue(playable, playable.indexOf(song), playlistName: 'You + ${b.withUser}'),
                scaleFactor: 0.99,
                semanticLabel: '${song?.title ?? s.title}, ${from(s)}',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.xs + 2),
                  child: Row(children: [
                    CoverArt(url: song == null ? null : svc.getCoverArtUrl(song.coverArt), size: 46, radius: Radii.thumb),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(song?.title ?? s.title, style: t.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(song == null ? from(s) : '${song.artist} · ${from(s)}',
                            style: t.footnote, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                  ]),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}
