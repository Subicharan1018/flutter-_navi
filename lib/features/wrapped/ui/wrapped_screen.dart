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
import '../logic/wrapped_providers.dart';
import 'wrapped_stage.dart';

/// Opens Wrapped for [year], full screen.
Future<void> showWrapped(BuildContext context, {int? year}) => Navigator.of(context, rootNavigator: true).push(
  PageRouteBuilder<void>(
    transitionDuration: Motion.slow,
    reverseTransitionDuration: Motion.standard,
    pageBuilder: (_, _, _) => WrappedScreen(year: year),
    transitionsBuilder: (context, a, _, child) => MediaQuery.disableAnimationsOf(context) ? child : FadeTransition(opacity: a, child: child),
  ),
);

/// Loads the year, then plays it.
class WrappedScreen extends ConsumerWidget {
  final int? year;
  const WrappedScreen({super.key, this.year});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final y = year ?? ref.read(wrappedNowProvider)().year;
    final async = ref.watch(wrappedProvider(y));
    final user = ref.watch(settingsProvider.select((s) => s.username));
    void close() => Navigator.of(context).maybePop();
    final data = async.asData?.value;
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFF000000),
      child: data != null && !data.isEmpty
          ? WrappedFilmLoader(data: data, name: user.isEmpty ? null : user, onClose: close)
          : SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: async.when(
                      loading: () => const CupertinoActivityIndicator(color: kInk, radius: 14),
                      error: (_, _) => MessageState.error(
                        title: 'Wrapped didn’t load',
                        message: 'It comes from your Smart Shuffle server. Check your connection, then try again.',
                        onRetry: () => ref.invalidate(wrappedProvider(y)),
                      ),
                      data: (_) => MessageState(icon: NaviGlyph.calendar, title: 'Nothing to wrap yet', message: 'Play some music in $y and your Wrapped builds here.'),
                    ),
                  ),
                  Positioned(
                    top: Space.sm,
                    right: Space.md,
                    child: CupertinoClickable(
                      onTap: close,
                      semanticLabel: 'Close',
                      child: const SizedBox.square(
                        dimension: 44,
                        child: Center(child: NaviIcon(NaviGlyph.close, size: 20, color: kInk)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Gathers the covers and portraits while the film already runs, and hands each over as it arrives.
class WrappedFilmLoader extends ConsumerStatefulWidget {
  final WrappedData data;
  final String? name;
  final VoidCallback? onClose;
  const WrappedFilmLoader({super.key, required this.data, this.name, this.onClose});

  @override
  ConsumerState<WrappedFilmLoader> createState() => _WrappedFilmLoaderState();
}

class _WrappedFilmLoaderState extends ConsumerState<WrappedFilmLoader> {
  late final WrappedFilm _film = WrappedFilm(widget.data, FilmAssets(), count: PlatformUtils.isConstrained ? 900 : 1500);
  final ValueNotifier<int> _arrivals = ValueNotifier(0);
  final Set<String> _asked = {};
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    textPoints('${widget.data.year}', _film.count).then((p) {
      if (!mounted) return;
      _film.assets.year = p;
      setState(() => _ready = true);
    });
    for (final (i, s) in widget.data.songs.take(5).indexed) {
      ref.listenManual(songCoverUrlProvider(s.coverKey), fireImmediately: true, (_, v) => _fetch('s$i', v.asData?.value, (url) => _song(i, url)));
    }
    for (final (i, a) in widget.data.artists.take(6).indexed) {
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

  @override
  Widget build(BuildContext context) =>
      _ready ? WrappedStage(film: _film, name: widget.name, onClose: widget.onClose, arrivals: _arrivals) : const ColoredBox(color: Color(0xFF000000), child: SizedBox.expand());
}
