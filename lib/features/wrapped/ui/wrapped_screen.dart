import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../player/artwork.dart' show testCoverOverride;
import '../../../providers/library_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../utils/platform_utils.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/states.dart';
import '../data/wrapped_models.dart';
import '../film/film.dart';
import '../film/film_assets.dart';
import '../logic/wrapped_loader.dart';
import '../logic/wrapped_providers.dart';
import 'wrapped_stage.dart';

/// Opens Wrapped for [year], full screen.
Future<void> showWrapped(BuildContext context, {int? year}) => Navigator.of(context, rootNavigator: true).push(
  PageRouteBuilder<void>(
    transitionDuration: Motion.slow,
    reverseTransitionDuration: Motion.standard,
    pageBuilder: (context, _, _) => Consumer(
      builder: (context, ref, _) => WrappedScreen(
        year: year ?? ref.read(wrappedNowProvider)().year,
        name: ref.watch(settingsProvider.select((s) => s.username)),
      ),
    ),
    transitionsBuilder: (context, a, _, child) => MediaQuery.disableAnimationsOf(context) ? child : FadeTransition(opacity: a, child: child),
  ),
);

/// The film of a year. It starts at once with the year alone; the numbers, covers and portraits join as they arrive.
class WrappedScreen extends ConsumerStatefulWidget {
  final int year;
  final String? name;
  const WrappedScreen({super.key, required this.year, this.name});

  @override
  ConsumerState<WrappedScreen> createState() => _WrappedScreenState();
}

class _WrappedScreenState extends ConsumerState<WrappedScreen> {
  late final WrappedFilm _film = WrappedFilm(emptyWrapped(widget.year), FilmAssets(), quality: PlatformUtils.isConstrained ? 0.5 : 1, settled: false);
  final ValueNotifier<int> _arrivals = ValueNotifier(0);
  final Set<String> _wanted = {};
  final Set<String> _asked = {};
  final Stopwatch _clock = Stopwatch()..start();
  WrappedLoad? _load;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => debugPrint('[Wrapped] intro on screen ${_clock.elapsedMilliseconds} ms'));
    textPoints('${widget.year}', 1300).then((p) {
      if (!mounted) return;
      _film.assets.year = p;
      _arrivals.value++;
    });
    ref.listenManual(wrappedProvider(widget.year), fireImmediately: true, (_, next) {
      final load = next.asData?.value;
      if (load == null || identical(load, _load)) return;
      setState(() {
        _load = load;
        _film.update(load.data, settled: load.settled);
      });
      _wantArt(load.data);
    });
  }

  void _wantArt(WrappedData d) {
    final o = d.story.obsession, b = d.busiestMonth;
    for (final key in {
      for (final s in d.songs.take(5)) s.coverKey,
      if (o != null) '${o.title}|${o.artist}',
      for (final a in d.story.albums.take(5)) a.cover,
      if (b != null && b.topSong != null && b.topArtist != null) '${b.topSong}|${b.topArtist}',
    }) {
      if (!_wanted.add('s$key')) continue;
      ref.listenManual(songCoverUrlProvider(key), fireImmediately: true, (_, v) => _fetch('s$key', v.asData?.value, (url) => _picture(_film.assets.covers, key, url, 640)));
    }
    for (final name in {for (final a in d.artists.take(6)) a.name, ...d.story.race.keys, ?d.story.loyal?.name}) {
      if (!_wanted.add('a$name')) continue;
      ref.listenManual(artistCoverUrlProvider(name), fireImmediately: true, (_, v) => _fetch('a$name', v.asData?.value, (url) => _picture(_film.assets.people, name, url, 256)));
    }
  }

  void _fetch(String key, String? url, void Function(String) load) {
    if (url == null || url.isEmpty || !_asked.add(key)) return;
    load(url);
  }

  ImageProvider _provider(String url) => testCoverOverride(url) ?? CachedNetworkImageProvider(url);

  Future<void> _picture(Map<String, ui.Image> into, String key, String url, int width) async {
    final image = await loadFilmImage(_provider(url), width: width);
    if (image == null) return;
    if (!mounted) return image.dispose();
    into[key] = image;
    if (identical(into, _film.assets.covers)) _film.assets.hues[key] = await imageHue(image);
    if (!mounted) return;
    _arrivals.value++;
    debugPrint('[Wrapped] picture ${_film.assets.covers.length + _film.assets.people.length} at ${_clock.elapsedMilliseconds} ms');
  }

  @override
  void dispose() {
    _arrivals.dispose();
    _film.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final failed = ref.watch(wrappedProvider(widget.year).select((v) => v.hasError)) && _load == null;
    final load = _load;
    final empty = load != null && load.settled && load.data.isEmpty;
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFF000000),
      child: failed || empty
          ? _Message(
              onClose: _close,
              child: failed
                  ? MessageState.error(
                      title: 'Wrapped didn’t load',
                      message: 'It comes from your Smart Shuffle server. Check your connection, then try again.',
                      onRetry: () => ref.invalidate(wrappedProvider(widget.year)),
                    )
                  : MessageState(icon: NaviGlyph.calendar, title: 'Nothing to wrap yet', message: 'Play some music in ${widget.year} and your Wrapped builds here.'),
            )
          : WrappedStage(
              film: _film,
              name: (widget.name?.isEmpty ?? true) ? null : widget.name,
              onClose: _close,
              arrivals: _arrivals,
              waiting: load == null
                  ? 'Gathering your year'
                  : load.settled
                  ? null
                  : 'Adding your months, ${load.done} of ${load.total}',
              progress: load == null || load.total == 0 ? null : load.done / load.total,
            ),
    );
  }
}

class _Message extends StatelessWidget {
  final Widget child;
  final VoidCallback onClose;
  const _Message({required this.child, required this.onClose});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Stack(
      children: [
        Center(child: DefaultTextStyle(style: const TextStyle(decoration: TextDecoration.none), child: child)),
        Positioned(
          top: Space.sm,
          right: Space.md,
          child: CupertinoClickable(
            onTap: onClose,
            semanticLabel: 'Close',
            child: const SizedBox.square(
              dimension: 44,
              child: Center(child: NaviIcon(NaviGlyph.close, size: 20, color: kInk)),
            ),
          ),
        ),
      ],
    ),
  );
}
