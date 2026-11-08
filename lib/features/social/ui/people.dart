import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/app_scaffold.dart' show AppTab, selectAppTab;
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/desktop_dialogs.dart' show showPlatformSheet;
import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/ui/media.dart';
import '../data/social_models.dart';
import '../logic/jam_controller.dart';
import '../logic/people_providers.dart';
import '../logic/social_providers.dart';
import '../logic/social_rules.dart';
import 'jam/jam_room.dart' show JamChipButton;
import 'social_widgets.dart';

/// A small mark for how present someone is. The state is in the shape, not the
/// colour: a filled dot (listening now), a half dot (idle), a hollow ring
/// (offline), a dashed ring (not sharing).
class PresenceMark extends StatelessWidget {
  final PresenceState state;
  final double size;
  const PresenceMark(this.state, {super.key, this.size = 12});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Semantics(
      label: state.label,
      excludeSemantics: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: _PresencePainter(state, t.textPrimary, t.textMuted),
      ),
    );
  }
}

class _PresencePainter extends CustomPainter {
  final PresenceState state;
  final Color ink;
  final Color dim;
  const _PresencePainter(this.state, this.ink, this.dim);

  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final r = s.width / 2 - 1;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = state == PresenceState.offline || state == PresenceState.hidden ? dim : ink;
    switch (state) {
      case PresenceState.active:
        canvas.drawCircle(c, r + 0.5, Paint()..color = ink);
      case PresenceState.idle:
        canvas.drawCircle(c, r, stroke);
        canvas.drawArc(Rect.fromCircle(center: c, radius: r), 1.5708, 3.14159, true, Paint()..color = ink); // lower half
      case PresenceState.offline:
        canvas.drawCircle(c, r, stroke);
      case PresenceState.hidden:
        const dashes = 8;
        for (var i = 0; i < dashes; i++) {
          final a = i * 2 * 3.14159 / dashes;
          canvas.drawArc(Rect.fromCircle(center: c, radius: r), a, 2 * 3.14159 / dashes * 0.55, false, stroke);
        }
    }
  }

  @override
  bool shouldRepaint(_PresencePainter old) => old.state != state || old.ink != ink || old.dim != dim;
}

/// Joins an open room from People, then shows it.
Future<void> joinFromPeople(BuildContext context, WidgetRef ref, Person p) async {
  final code = p.room?.code;
  if (code == null || !canJoin(p)) return;
  final ok = await ref.read(jamControllerProvider.notifier).join(code);
  if (!context.mounted) return;
  if (ok) {
    selectAppTab(AppTab.jam);
  } else {
    showToast(context, ref.read(jamControllerProvider).notice ?? 'Couldn’t join that room.');
  }
}

/// Everyone on the server who turned social features on, listening now first.
/// Opening it keeps the list fresh; leaving it stops the faster refresh.
class PeopleSection extends ConsumerStatefulWidget {
  const PeopleSection({super.key});

  @override
  ConsumerState<PeopleSection> createState() => _PeopleSectionState();
}

class _PeopleSectionState extends ConsumerState<PeopleSection> {
  VoidCallback? _stop;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) _stop = ref.read(peopleProvider.notifier).watching();
    });
  }

  @override
  void dispose() {
    _stop?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(socialEnabledProvider)) return const SizedBox.shrink();
    final s = ref.watch(peopleProvider);
    final people = sortPeople(s.list?.people ?? const []);
    final listening = people.where((p) => p.isActive).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(title: listening == 0 ? 'People' : 'People · $listening listening'),
      if (s.list == null && !s.failed)
        const Padding(padding: EdgeInsets.all(Space.xl), child: Center(child: CupertinoActivityIndicator()))
      else if (s.list == null)
        SocialNote(
          glyph: NaviGlyph.group,
          title: 'Couldn’t load people',
          message: 'Check your connection to the server, then try again.',
          actionLabel: 'Try again',
          onAction: () => ref.read(peopleProvider.notifier).refresh(),
        )
      else if (people.isEmpty)
        const SocialNote(
          glyph: NaviGlyph.group,
          title: 'No one else is here yet',
          message: 'People who turn on social features on this server appear here.',
        )
      else
        for (final (i, p) in people.indexed) PersonRow(person: p, showSeparator: i < people.length - 1),
    ]);
  }
}

class PersonRow extends ConsumerWidget {
  final Person person;
  final bool showSeparator;
  const PersonRow({super.key, required this.person, this.showSeparator = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final p = person;
    final muted = ref.watch(friendAlertSettingsProvider.select((s) => s.isMuted(p.username)));
    final line = presenceLine(p);
    return CupertinoClickable(
      onTap: p.state == PresenceState.hidden ? null : () => _menu(context, ref),
      onLongPress: () => _menu(context, ref),
      scaleFactor: 0.99,
      semanticLabel: '${p.username}, ${p.state.label}. $line${muted ? '. Alerts muted' : ''}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.sm),
        decoration: showSeparator ? BoxDecoration(border: Border(bottom: BorderSide(color: t.outline, width: 0.5))) : null,
        child: Row(children: [
          PersonAvatar(p.username),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(p.username, style: t.headline, maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: Space.sm),
                PresenceMark(p.state),
                if (muted) ...[
                  const SizedBox(width: Space.sm),
                  Text('Muted', style: t.caption1.copyWith(color: t.textMuted)),
                ],
              ]),
              Text(line, style: t.subheadline, maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
          if (canJoin(p)) ...[
            const SizedBox(width: Space.sm),
            JamChipButton(label: 'Join', onTap: () => joinFromPeople(context, ref, p)),
          ],
        ]),
      ),
    );
  }

  void _menu(BuildContext context, WidgetRef ref) {
    final p = person;
    final alerts = ref.read(friendAlertSettingsProvider.notifier);
    final muted = ref.read(friendAlertSettingsProvider).isMuted(p.username);
    showPlatformSheet(
      context: context,
      title: p.username,
      builder: (_) => Padding(
        padding: const EdgeInsets.only(bottom: Space.md),
        child: SheetGroup(children: [
          if (canJoin(p)) SheetAction(label: 'Join ${p.room!.mode.label} room', onTap: () => joinFromPeople(context, ref, p)),
          SheetAction(
            label: muted ? 'Unmute alerts' : 'Mute alerts',
            detail: muted ? null : 'No notification when ${p.username} starts listening',
            onTap: () => alerts.setMuted(p.username, !muted),
          ),
        ]),
      ),
    );
  }
}

/// Windows Home: who is listening now, as a row of people. Nothing while no
/// one is, and nothing until social features are on.
class ListeningNowStrip extends ConsumerStatefulWidget {
  const ListeningNowStrip({super.key});

  @override
  ConsumerState<ListeningNowStrip> createState() => _ListeningNowStripState();
}

class _ListeningNowStripState extends ConsumerState<ListeningNowStrip> {
  VoidCallback? _stop;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) _stop = ref.read(peopleProvider.notifier).watching();
    });
  }

  @override
  void dispose() {
    _stop?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(socialEnabledProvider)) return const SizedBox.shrink();
    final now = ref.watch(peopleProvider.select((s) => s.list?.listeningNow ?? const <Person>[]));
    if (now.isEmpty) return const SizedBox.shrink();
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Listening now', style: t.title3),
        const SizedBox(height: Space.sm),
        SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: now.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.xl),
            itemBuilder: (context, i) {
              final p = now[i];
              return CupertinoClickable(
                onTap: () => selectAppTab(AppTab.jam),
                semanticLabel: '${p.username}, ${presenceLine(p)}',
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  PersonAvatar(p.username, size: 40),
                  const SizedBox(width: Space.sm),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.username, style: t.subheadline.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(presenceLine(p), style: t.footnote, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                  if (canJoin(p)) ...[
                    const SizedBox(width: Space.sm),
                    JamChipButton(label: 'Join', onTap: () => joinFromPeople(context, ref, p)),
                  ],
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }
}
