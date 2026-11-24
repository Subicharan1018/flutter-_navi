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
  late final WrappedFilm _film = WrappedFilm(emptyWrapped(widget.year), FilmAssets(), count: PlatformUtils.isConstrained ? 900 : 1500, settled: false);
  final ValueNotifier<int> _arrivals = ValueNotifier(0);
  final Set<String> _wanted = {};
  final Set<String> _asked = {};
  final Stopwatch _clock = Stopwatch()..start();
  WrappedLoad? _load;

  @override
  void initState() {
    super.initState();
    textPoints('${widget.year}', _film.count).then((p) {
      if (!mounted) return;
      _film.assets.year = p;
      debugPrint('[Wrapped] intro ready ${_clock.elapsedMilliseconds} ms');
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
    for (final (i, s) in d.songs.take(5).indexed) {
      if (!_wanted.add('s$i')) continue;
      ref.listenManual(songCoverUrlProvider(s.coverKey), fireImmediately: true, (_, v) => _fetch('s$i', v.asData?.value, (url) => _song(i, url)));
    }
    for (final (i, a) in d.artists.take(6).indexed) {
      if (!_wanted.add('a$i')) continue;
      ref.listenManual(artistCoverUrlProvider(a.name), fireImmediately: true, (_, v) => _fetch('a$i', v.asData?.value, (url) => _artist(i, url)));
    }
  }

  void _fetch(String key, String? url, void Function(String) load) {
    if (url == null || url.isEmpty || !_asked.add(key)) return;
    load(url);
  }

  ImageProvider _provider(String url) => testCoverOverride(url) ?? CachedNetworkImageProvider(url);

  Future<void> _song(int i, String url) async {
    final image = await loadFilmImage(_provider(url), width: 640);
    if (image == null) return;
    final cover = await FilmCover.of(image);
    if (!mounted) return image.dispose();
    _film.assets.songs[i] = cover;
    _arrivals.value++;
    debugPrint('[Wrapped] cover ${i + 1} ${_clock.elapsedMilliseconds} ms');
  }

  Future<void> _artist(int i, String url) async {
    final image = await loadFilmImage(_provider(url), width: 320);
    if (image == null) return;
    if (!mounted) return image.dispose();
    _film.assets.artists[i] = image;
    _arrivals.value++;
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
        Center(child: child),
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
