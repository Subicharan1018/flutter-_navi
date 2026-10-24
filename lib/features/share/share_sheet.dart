import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../models/album.dart';
import '../../models/playlist.dart';
import '../../models/song.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/art/navi_icons.dart';
import '../../widgets/desktop_dialogs.dart';
import '../../widgets/ui/action_sheet.dart';
import 'share_api.dart';
import 'share_card.dart';

/// What is being shared: a song, album or playlist.
class ShareTarget {
  final ShareKind kind;
  final String id;
  final String title;
  final String subtitle;
  final String? coverArt;

  const ShareTarget({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    this.coverArt,
  });

  factory ShareTarget.song(Song s) => ShareTarget(
    kind: ShareKind.song,
    id: s.id,
    title: s.title,
    subtitle: s.artist,
    coverArt: s.coverArt,
  );

  factory ShareTarget.album(Album a) => ShareTarget(
    kind: ShareKind.album,
    id: a.id,
    title: a.name,
    subtitle: a.artist,
    coverArt: a.coverArt,
  );

  factory ShareTarget.playlist(Playlist p) => ShareTarget(
    kind: ShareKind.playlist,
    id: p.id,
    title: p.name,
    subtitle: p.owner == null || p.owner!.isEmpty ? 'Playlist' : 'Playlist by ${p.owner}',
    coverArt: p.coverArt,
  );

  /// "Title — Artist" line that goes in front of the link.
  String get caption => subtitle.isEmpty ? title : '$title — $subtitle';
}

Future<void> showShareSheet(BuildContext context, ShareTarget target) => showPlatformSheet(
  context: context,
  title: 'Share',
  builder: (_) => _ShareSheet(target: target),
);

class _ShareSheet extends ConsumerStatefulWidget {
  final ShareTarget target;
  const _ShareSheet({required this.target});

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  final _cardKey = GlobalKey();
  ShareExpiry _expiry = ShareExpiry.defaultChoice;
  ImageProvider? _cover;
  bool _coverDone = false;
  bool _busy = false;
  String? _error;

  /// One link per expiry choice, so tapping Copy then Share doesn't mint two.
  final Map<ShareExpiry, String> _links = {};

  @override
  void initState() {
    super.initState();
    _loadCover();
  }

  Future<void> _loadCover() async {
    final art = widget.target.coverArt;
    if (art == null || art.isEmpty) {
      if (mounted) setState(() => _coverDone = true);
      return;
    }
    try {
      final url = ref.read(subsonicServiceProvider).getCoverArtUrl(art, size: 900);
      final file = await DefaultCacheManager().getSingleFile(url);
      final provider = MemoryImage(await file.readAsBytes());
      if (!mounted) return;
      await precacheImage(provider, context);
      if (mounted) setState(() => _cover = provider);
    } catch (_) {
      // Card falls back to its glyph; sharing still works.
    }
    if (mounted) setState(() => _coverDone = true);
  }

  Future<String?> _link() async {
    final cached = _links[_expiry];
    if (cached != null) return cached;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final url = await ref.read(subsonicServiceProvider).createShare(
        widget.target.id,
        description: widget.target.caption,
        expiry: _expiry,
      );
      _links[_expiry] = url;
      return url;
    } on ShareException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn’t make a share link. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return null;
  }

  Future<void> _copy() async {
    final url = await _link();
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    showToast(context, 'Link copied');
  }

  Future<void> _shareLink() async {
    final url = await _link();
    if (url == null) return;
    await SharePlus.instance.share(ShareParams(text: '${widget.target.caption}\n$url', subject: widget.target.title));
  }

  Future<void> _shareCard() async {
    final url = await _link();
    if (url == null) return;
    setState(() => _busy = true);
    try {
      final file = await _renderCard();
      await SharePlus.instance.share(
        ShareParams(
          text: '${widget.target.caption}\n$url',
          subject: widget.target.title,
          files: file == null ? null : [XFile(file.path, mimeType: 'image/png')],
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<File?> _renderCard() async {
    try {
      final boundary = _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 1080 / ShareCard.width);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}navivibe_share_${widget.target.id}.png');
      return await file.writeAsBytes(Uint8List.view(data.buffer));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final target = widget.target;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: FittedBox(
                child: RepaintBoundary(
                  key: _cardKey,
                  child: ShareCard(
                    kind: target.kind,
                    title: target.title,
                    subtitle: target.subtitle,
                    cover: _cover,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Row(
              children: [
                Text('Link expires', style: t.subheadline),
                const SizedBox(width: Space.md),
                Expanded(
                  child: CupertinoSlidingSegmentedControl<ShareExpiry>(
                    groupValue: _expiry,
                    backgroundColor: t.fill,
                    thumbColor: t.bgOverlay,
                    onValueChanged: (v) {
                      if (v != null && !_busy) setState(() => _expiry = v);
                    },
                    children: {
                      for (final e in ShareExpiry.values)
                        e: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                          child: Text(e.label, style: t.footnote.copyWith(color: t.textPrimary)),
                        ),
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, 0),
              child: Text(_error!, textAlign: TextAlign.center, style: t.footnote.copyWith(color: t.danger)),
            ),
          const SizedBox(height: Space.lg),
          SheetGroup(
            children: [
              SheetAction(
                label: 'Share Link',
                icon: NaviGlyph.share,
                keepOpen: true,
                onTap: _busy ? null : _shareLink,
              ),
              SheetAction(
                label: 'Send as Card',
                icon: NaviGlyph.photo,
                keepOpen: true,
                onTap: _busy || !_coverDone ? null : _shareCard,
              ),
              SheetAction(
                label: 'Copy Link',
                icon: NaviGlyph.copy,
                keepOpen: true,
                onTap: _busy ? null : _copy,
              ),
            ],
          ),
          if (_busy) const Padding(padding: EdgeInsets.only(bottom: Space.md), child: CupertinoActivityIndicator()),
          const SizedBox(height: Space.sm),
        ],
      ),
    );
  }
}
