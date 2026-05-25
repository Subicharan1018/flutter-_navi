import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Full-bleed blurred album art background used by [LyricsView].
///
/// Stack layout:
///   CachedNetworkImage  (fill)
///   ImageFiltered blur  (sigma 80)
///   Dark overlay        (0x99000000)
class LyricsBackground extends StatelessWidget {
  final String imageUrl;

  const LyricsBackground({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Base: album art
        if (imageUrl.isNotEmpty)
          CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        // Blur
        // PERF: reduced from σ80 to σ40 — imperceptible behind dark overlay,
        // but significantly cheaper GPU-side (blur cost ∝ σ²).
        BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: const SizedBox.expand(),
        ),
        // Dark overlay so text is always readable
        const DecoratedBox(decoration: BoxDecoration(color: Color(0xA3000000))),
      ],
    );
  }
}
