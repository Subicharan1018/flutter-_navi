import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import '../../../core/theme.dart';
import '../../../models/song.dart';
import '../../../providers/player_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../screens/song_picker_screen.dart';
import '../../../widgets/app_scaffold.dart' show navigateInApp;
import '../../../widgets/art/generated_cover.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/cover_art.dart';
import '../../../widgets/desktop_dialogs.dart' show showPlatformSheet;
import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/ui/large_title_page.dart';
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/states.dart';
import '../data/social_api.dart';
import '../data/social_models.dart';
import '../logic/social_providers.dart';
import 'social_widgets.dart';

String _msg(Object e) => e is SocialException ? e.message : 'Something went wrong. Try again.';

/// `WidgetRef` and `ProviderContainer` both fit; the sheet entry points hold a
/// container because the menu that opened them is gone by the time they run.
typedef _Invalidate = void Function(ProviderOrFamily provider, {bool asReload});

void _refresh(_Invalidate invalidate, [String? id]) {
  invalidate(collabListProvider);
  if (id != null) invalidate(collabDetailProvider(id));
}

Widget _cover(CollabPlaylist p, double size) => SizedBox(
      width: size,
      height: size,
      child: GeneratedCover(name: p.name, songIds: [p.id], borderRadius: Radii.cover),
    );

// ── hub section ──────────────────────────────────────────────────────────────

class CollabSection extends ConsumerWidget {
  const CollabSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(collabListProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHeader(title: 'Shared playlists'),
      lists.when(
        loading: () => const Padding(padding: EdgeInsets.all(Space.xl), child: Center(child: CupertinoActivityIndicator())),
        error: (_, _) => SocialNote(
          glyph: NaviGlyph.addToPlaylist,
          title: 'Couldn’t load shared playlists',
          message: 'Check your connection to the server, then try again.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(collabListProvider),
        ),
        data: (items) => Column(children: [
          for (final p in items.where((p) => !p.invited)) CollabRow(playlist: p),
          if (items.isEmpty)
            const SocialFootnote('Make a playlist with friends. Everyone you invite can add songs, and you see who added what.'),
          CollectionRow(
            title: 'New shared playlist',
            leading: SizedBox(width: 30, child: NaviIcon(NaviGlyph.addToPlaylist, size: 24, color: ThemeTokens.of(context).accent)),
            showChevron: false,
            showSeparator: false,
            onTap: () => createCollab(context, ProviderScope.containerOf(context)),
          ),
        ]),
      ),
    ]);
  }
}

class CollabRow extends ConsumerWidget {
  final CollabPlaylist playlist;
  const CollabRow({super.key, required this.playlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = playlist;
    final t = ThemeTokens.of(context);
    if (p.invited) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.sm),
        child: Row(children: [
          _cover(p, 52),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: t.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${p.invitedBy ?? p.owner} invited you', style: t.footnote),
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
            child: Text('Join', style: t.headline.copyWith(color: t.accent)),
          ),
        ]),
      );
    }
    final others = p.members.where((m) => m.active).length;
    return CollectionRow(
      title: p.name,
      subtitle: '${p.songCount} ${p.songCount == 1 ? 'song' : 'songs'} · $others ${others == 1 ? 'person' : 'people'}',
      leading: _cover(p, 52),
      onTap: () => navigateInApp(context, CollabScreen(id: p.id)),
    );
  }

  Future<void> _answer(BuildContext context, WidgetRef ref, bool accept) async {
    try {
      await ref.read(socialApiProvider).collabRespond(playlist.id, accept);
      _refresh(ref.invalidate, playlist.id);
    } catch (e) {
      if (context.mounted) showToast(context, _msg(e));
    }
  }
}

/// Asks for a name and makes a shared playlist (seeded with [songIds]);
/// opens it.
Future<void> createCollab(BuildContext context, ProviderContainer c, {List<String> songIds = const []}) async {
  final name = await askForText(context, title: 'New shared playlist', placeholder: 'Name', action: 'Create');
  if (name == null) return;
  try {
    final p = await c.read(socialApiProvider).collabCreate(name, songIds: songIds);
    _refresh(c.invalidate);
    if (context.mounted) navigateInApp(context, CollabScreen(id: p.id));
  } catch (e) {
    if (context.mounted) showToast(context, _msg(e));
  }
}

/// Sheet to add [songs] to one of your shared playlists (or start one).
Future<void> showAddToCollab(BuildContext page, ProviderContainer c, List<Song> songs) async {
  List<CollabPlaylist> mine;
  try {
    mine = [for (final p in await c.read(socialApiProvider).collabList()) if (!p.invited) p];
  } catch (e) {
    if (page.mounted) showToast(page, _msg(e));
    return;
  }
  if (!page.mounted) return;
  final choice = await showPlatformSheet<Object>(
    context: page,
    title: 'Add to a shared playlist',
    builder: (ctx) {
      final t = ThemeTokens.of(ctx);
      return Padding(
        padding: const EdgeInsets.only(bottom: Space.md),
        child: SheetGroup(children: [
          for (final p in mine)
            SheetAction(
              label: p.name,
              detail: '${p.songCount} songs',
              onTap: () => Navigator.of(ctx).pop(p),
              keepOpen: true,
            ),
          SheetAction(
            label: 'New shared playlist…',
            trailing: NaviIcon(NaviGlyph.addToPlaylist, size: 21, color: t.textPrimary),
            keepOpen: true,
            onTap: () => Navigator.of(ctx).pop('new'),
          ),
        ]),
      );
    },
  );
  if (choice == null || !page.mounted) return;
  final ids = [for (final s in songs) s.id];
  if (choice == 'new') {
    await createCollab(page, c, songIds: ids);
    return;
  }
  try {
    final target = choice as CollabPlaylist;
    await c.read(socialApiProvider).collabAddSongs(target.id, ids);
    _refresh(c.invalidate, target.id);
    if (page.mounted) showToast(page, 'Added to ${target.name}');
  } catch (e) {
    if (page.mounted) showToast(page, _msg(e));
  }
}

// ── detail ───────────────────────────────────────────────────────────────────

class CollabScreen extends ConsumerWidget {
  final String id;
  const CollabScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(collabDetailProvider(id));
    return async.when(
      loading: () => const LargeTitlePage(title: 'Shared playlist', slivers: [SliverToBoxAdapter(child: LoadingState())]),
      error: (e, _) => LargeTitlePage(
        title: 'Shared playlist',
        slivers: [
          SliverToBoxAdapter(
            child: SocialNote(
              glyph: NaviGlyph.addToPlaylist,
              title: 'Couldn’t open this playlist',
              message: e is SocialException && e.status == 403
                  ? 'It isn’t shared with you any more.'
                  : 'Check your connection to the server, then try again.',
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(collabDetailProvider(id)),
            ),
          ),
        ],
      ),
      data: (p) => _CollabBody(playlist: p),
    );
  }
}

class _CollabBody extends ConsumerWidget {
  final CollabPlaylist playlist;
  const _CollabBody({required this.playlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = playlist;
    final t = ThemeTokens.of(context);
    final me = ref.read(settingsProvider).username.toLowerCase();
    final songs = ref.watch(socialSongsProvider(p.songs.map((e) => e.songId).join(','))).asData?.value ?? const {};
    final playable = [for (final e in p.songs) if (songs[e.songId] != null) songs[e.songId]!];
    final svc = ref.read(subsonicServiceProvider);

    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
        _refresh(ref.invalidate, p.id);
      } catch (e) {
        if (context.mounted) showToast(context, _msg(e));
      }
    }

    return LargeTitlePage(
      title: p.name,
      onRefresh: () async => _refresh(ref.invalidate, p.id),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: () => _menu(context, ref, p, run),
        child: NaviIcon(NaviGlyph.more, size: 24, color: t.accent),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.md),
            child: Row(children: [
              _cover(p, 96),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${p.songs.length} ${p.songs.length == 1 ? 'song' : 'songs'}', style: t.headline),
                  Text('Made by ${p.owner}', style: t.subheadline),
                  const SizedBox(height: Space.sm),
                  Row(children: [
                    SocialButton(
                      label: 'Play',
                      onPressed: playable.isEmpty
                          ? null
                          : () => ref.read(playerProvider.notifier).setQueue(playable, 0, playlistName: p.name),
                    ),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
        SliverToBoxAdapter(child: _MemberStrip(playlist: p, onRemove: (u) => run(() => ref.read(socialApiProvider).collabRemoveMember(p.id, u)))),
        if (p.songs.isEmpty)
          const SliverToBoxAdapter(
            child: SocialNote(
              glyph: NaviGlyph.queue,
              art: EmptyArtKind.record,
              title: 'No songs yet',
              message: 'Add the first song. Everyone in this playlist can add more.',
            ),
          )
        else
          SliverList.builder(
            itemCount: p.songs.length,
            itemBuilder: (context, i) {
              final e = p.songs[i];
              final s = songs[e.songId];
              final canRemove = p.isOwner || e.addedBy.toLowerCase() == me;
              return CupertinoClickable(
                onTap: s == null ? null : () => ref.read(playerProvider.notifier).setQueue(playable, playable.indexOf(s), playlistName: p.name),
                onLongPress: canRemove
                    ? () => showPlatformSheet(
                          context: context,
                          title: s?.title ?? 'Song',
                          builder: (_) => Padding(
                            padding: const EdgeInsets.only(bottom: Space.md),
                            child: SheetGroup(children: [
                              SheetAction(
                                label: 'Remove from playlist',
                                destructive: true,
                                onTap: () => run(() => ref.read(socialApiProvider).collabRemoveSong(p.id, e.entryId)),
                              ),
                            ]),
                          ),
                        )
                    : null,
                scaleFactor: 0.99,
                semanticLabel: '${s?.title ?? 'Song not in library'}, added by ${e.addedBy}',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.xs + 2),
                  child: Row(children: [
                    CoverArt(url: s == null ? null : svc.getCoverArtUrl(s.coverArt), size: 46, radius: Radii.thumb),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s?.title ?? 'Not in the library', style: t.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          s == null ? 'Added by ${e.addedBy}' : '${s.artist} · added by ${e.addedBy}',
                          style: t.footnote,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ]),
                    ),
                  ]),
                ),
              );
            },
          ),
        SliverToBoxAdapter(
          child: Center(
            child: SocialButton(
              label: 'Add songs',
              quiet: true,
              onPressed: () => Navigator.of(context, rootNavigator: true).push<bool>(
                CupertinoPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => SongPickerScreen.custom(
                    destination: p.name,
                    onPicked: (picked) async {
                      try {
                        await ref.read(socialApiProvider).collabAddSongs(p.id, [for (final s in picked) s.id]);
                        _refresh(ref.invalidate, p.id);
                        return true;
                      } catch (e) {
                        if (context.mounted) showToast(context, _msg(e));
                        return false;
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, CollabPlaylist p, Future<void> Function(Future<void> Function()) run) {
    final api = ref.read(socialApiProvider);
    return showPlatformSheet(
      context: context,
      title: p.name,
      builder: (_) => Padding(
        padding: const EdgeInsets.only(bottom: Space.md),
        child: SheetGroup(children: [
          if (p.isOwner)
            SheetAction(
              label: 'Invite someone',
              onTap: () async {
                final who = await pickPerson(context, ref,
                    title: 'Invite to ${p.name}', skip: {for (final m in p.members) m.username});
                if (who == null) return;
                await run(() async {
                  await api.collabInvite(p.id, who);
                  if (context.mounted) showToast(context, 'Invited $who');
                });
              },
            ),
          if (p.isOwner)
            SheetAction(
              label: 'Rename',
              onTap: () async {
                final name = await askForText(context, title: 'Rename', placeholder: 'Name', action: 'Save', initial: p.name);
                if (name != null) await run(() => api.collabRename(p.id, name));
              },
            ),
          if (p.isOwner)
            SheetAction(
              label: 'Delete playlist',
              destructive: true,
              onTap: () async {
                final sure = await confirmDestructive(
                  context,
                  title: 'Delete this playlist?',
                  message: 'It is removed for everyone who shares it.',
                  confirmLabel: 'Delete',
                );
                if (!sure) return;
                await api.collabDelete(p.id);
                _refresh(ref.invalidate);
                if (context.mounted) Navigator.of(context).pop();
              },
            )
          else
            SheetAction(
              label: 'Leave playlist',
              destructive: true,
              onTap: () async {
                final me = ref.read(settingsProvider).username;
                await api.collabRemoveMember(p.id, me);
                _refresh(ref.invalidate);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
        ]),
      ),
    );
  }
}

class _MemberStrip extends ConsumerWidget {
  final CollabPlaylist playlist;
  final void Function(String username) onRemove;
  const _MemberStrip({required this.playlist, required this.onRemove});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.md),
      child: Wrap(spacing: Space.md, runSpacing: Space.sm, children: [
        for (final m in playlist.members)
          CupertinoClickable(
            onTap: playlist.isOwner && m.username.toLowerCase() != playlist.owner.toLowerCase()
                ? () => showPlatformSheet(
                      context: context,
                      title: m.username,
                      builder: (_) => Padding(
                        padding: const EdgeInsets.only(bottom: Space.md),
                        child: SheetGroup(children: [
                          SheetAction(label: m.active ? 'Remove from playlist' : 'Cancel invite', destructive: true, onTap: () => onRemove(m.username)),
                        ]),
                      ),
                    )
                : null,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              PersonAvatar(m.username, size: 28),
              const SizedBox(width: Space.xs + 2),
              Text(m.active ? m.username : '${m.username} (invited)', style: t.footnote),
            ]),
          ),
      ]),
    );
  }
}
