import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../core/motion.dart';
import '../core/theme.dart';

/// The one motion between Now Playing's two layouts: the player alone, and the
/// player with Lyrics or Queue open. Everything that moves reads [position]
/// (0 alone .. 1 open), so cover, title, controls and pane travel as one.
///
/// It runs on a spring that starts from the current position and velocity, so
/// a second tap mid-flight turns it around instead of restarting it. With
/// motion reduced nothing travels: the layout changes at once and [settle]
/// fades the new one in.
class PaneFlight {
  PaneFlight(TickerProvider vsync, {double initial = 0})
      : position = AnimationController(vsync: vsync, value: initial),
        settle = AnimationController(vsync: vsync, value: 1, duration: Motion.standard);

  final AnimationController position;

  /// Opacity of the stage; only ever dips under reduced motion.
  final AnimationController settle;

  void to(BuildContext context, double target) {
    if (!context.motionFullNow) {
      if (position.value == target && !position.isAnimating) return;
      position.value = target;
      settle.forward(from: 0);
      return;
    }
    // snapToEnd: the flight must finish exactly on 0 or 1, or "closed" never
    // quite is and the cover keeps behaving as if a pane were open.
    position.animateWith(
      SpringSimulation(Motion.flight, position.value, target, position.velocity, snapToEnd: true),
    );
  }

  void dispose() {
    position.dispose();
    settle.dispose();
  }
}

/// How far the incoming pane has arrived at flight position [t]: it holds back
/// while the cover clears its space, then keeps pace with it.
double paneArrival(double t) => ((t - 0.2) / 0.8).clamp(0.0, 1.0);

/// Item [index] of [count] in a row that lands one after another as the flight
/// finishes: 0 not yet there, 1 at rest.
double staggeredArrival(double t, int index) => ((t - 0.35 - index * 0.07) / 0.44).clamp(0.0, 1.0);

/// Where the wide player (desktop window, tablet landscape) puts its two
/// columns at flight position [t]: the player column slides from the middle of
/// the window to the left, and the pane arrives beside it at its final size, so
/// lyrics and queue rows are never re-laid out while they move.
@immutable
class WideGeometry {
  static const double sidePad = 40;
  static const double openLeadPad = 64;
  static const double gap = 56;
  static const double playerFlex = 5;
  static const double paneFlex = 6;

  /// The pane starts this far to the right of its place.
  static const double paneTravel = 48;

  final Rect player;
  final Rect pane;
  const WideGeometry(this.player, this.pane);

  static WideGeometry at(Size area, double t, {required double maxPlayer}) {
    final aloneW = math.max(0.0, math.min(maxPlayer, area.width - 2 * sidePad));
    final alone = (area.width - aloneW) / 2;
    final shared = math.max(0.0, area.width - openLeadPad - sidePad - gap);
    final column = shared * playerFlex / (playerFlex + paneFlex);
    final besideW = math.min(maxPlayer, column);
    final beside = openLeadPad + (column - besideW) / 2;
    final paneLeft = openLeadPad + column + gap;
    return WideGeometry(
      Rect.fromLTWH(lerpDouble(alone, beside, t)!, 0, lerpDouble(aloneW, besideW, t)!, area.height),
      Rect.fromLTWH(paneLeft + (1 - paneArrival(t)) * paneTravel, 0, shared - column, area.height),
    );
  }
}
