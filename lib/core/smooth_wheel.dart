import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Eased mouse-wheel scrolling for the desktop.
///
/// Flutter jumps a wheel notch's whole distance in one frame, which on a 60 Hz
/// screen reads as a stutter next to apps that glide (Spotify, browsers). This
/// turns each notch into a short ease-out animation toward a target that
/// accumulates, so a quick spin glides and a single notch settles in
/// [duration].
///
/// It sits in front of the engine's pointer packets: a wheel event over a
/// scrollable that can move is consumed here and eased frame by frame;
/// everything else (a text field, a list already at
/// its end, a horizontal shelf without Shift) continues down the normal path.
class SmoothWheel {
  SmoothWheel._();

  static const Duration duration = Duration(milliseconds: 260);
  static const Curve curve = Curves.easeOutCubic;

  static final _glides = Expando<_Glide>('SmoothWheel glide');
  static bool _installed = false;

  /// Hooks the engine's pointer packets. Call once, on desktop.
  static void install() {
    if (_installed) return;
    final dispatcher = ui.PlatformDispatcher.instance;
    final next = dispatcher.onPointerDataPacket;
    if (next == null) return;
    _installed = true;
    dispatcher.onPointerDataPacket = (ui.PointerDataPacket packet) {
      List<ui.PointerData>? kept;
      for (final (i, d) in packet.data.indexed) {
        if (d.signalKind == ui.PointerSignalKind.scroll && _consume(d)) {
          kept ??= packet.data.sublist(0, i);
        } else {
          kept?.add(d);
        }
      }
      if (kept == null) return next(packet);
      if (kept.isNotEmpty) next(ui.PointerDataPacket(data: kept));
    };
  }

  static bool _consume(ui.PointerData d) {
    final binding = WidgetsBinding.instance;
    final view = ui.PlatformDispatcher.instance.view(id: d.viewId);
    if (view == null) return false;
    final events = PointerEventConverter.expand([d], (_) => view.devicePixelRatio);
    final event = events.whereType<PointerScrollEvent>().firstOrNull;
    if (event == null) return false;
    final result = HitTestResult();
    binding.hitTestInView(result, event.position, d.viewId);
    return handle(event, result);
  }

  /// Animates the scrollable under [result] for [event]. True when it took the
  /// wheel; false leaves the event to Flutter's own handling.
  static bool handle(PointerScrollEvent event, HitTestResult result) {
    final shift = HardwareKeyboard.instance.logicalKeysPressed.any(
      (k) => k == LogicalKeyboardKey.shiftLeft || k == LogicalKeyboardKey.shiftRight,
    );
    for (final entry in result.path) {
      final target = entry.target;
      // A text field scrolls itself.
      if (target is RenderEditable) return false;
      final offset = target is RenderViewportBase ? target.offset : null;
      if (offset is! ScrollPosition || !offset.hasContentDimensions) continue;
      final isVertical = offset.axis == Axis.vertical;
      // Vertical lists take the wheel's up/down; a horizontal one only with Shift
      // (or a sideways wheel), as the scrollable itself does.
      var delta = isVertical ? event.scrollDelta.dy : (shift ? event.scrollDelta.dy : event.scrollDelta.dx);
      if (isVertical && shift && event.scrollDelta.dx != 0) delta = 0;
      if (delta == 0) continue;
      if (axisDirectionIsReversed(offset.axisDirection)) delta = -delta;
      if (!offset.physics.shouldAcceptUserOffset(offset)) continue;
      final glide = _glides[offset] ??= _Glide(offset);
      final base = glide.active ? glide.to : offset.pixels;
      final to = (base + delta).clamp(offset.minScrollExtent, offset.maxScrollExtent).toDouble();
      if (to == offset.pixels) continue; // at its end: let the next one out take it
      glide.retarget(to);
      return true;
    }
    return false;
  }
}

/// One scroll position's glide: from where it is now to [to], eased, one
/// `jumpTo` a frame. (Not `animateTo`: a driven activity makes the scrollable
/// ignore the pointer, so the next notch could not find the list under it.)
class _Glide {
  final ScrollPosition position;
  _Glide(this.position);

  double from = 0;
  double to = 0;
  double _last = 0;
  Duration? _t0;
  bool active = false;

  void retarget(double target) {
    from = position.pixels;
    to = target;
    _last = from;
    _t0 = null;
    if (!active) {
      active = true;
      SchedulerBinding.instance.scheduleFrameCallback(_frame);
    }
  }

  void _frame(Duration stamp) {
    // Gone (page closed), or something else moved the list (a scrollbar drag,
    // a keyboard jump): stop rather than fight it.
    final mounted = position.context.notificationContext?.mounted ?? false;
    if (!mounted || !position.hasContentDimensions || (position.pixels - _last).abs() > 0.5) {
      active = false;
      return;
    }
    final t0 = _t0 ??= stamp;
    final p = ((stamp - t0).inMicroseconds / SmoothWheel.duration.inMicroseconds).clamp(0.0, 1.0);
    final v = from + (to - from) * SmoothWheel.curve.transform(p);
    position.jumpTo(v);
    _last = position.pixels;
    if (p >= 1) {
      active = false;
    } else {
      SchedulerBinding.instance.scheduleFrameCallback(_frame);
    }
  }
}
