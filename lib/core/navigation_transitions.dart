import 'package:flutter/material.dart';

class AppRouteTransitions {
  static const Duration forwardDuration = Duration(milliseconds: 360);
  static const Duration reverseDuration = Duration(milliseconds: 260);

  static Route<T> fadeScale<T>({required WidgetBuilder builder}) {
    // BUG-11: use _CurvedPageRoute so CurvedAnimation is created once and
    // properly disposed, instead of allocating a new one every frame inside
    // transitionsBuilder (which caused GC pressure & frame drops).
    return _FadeScaleRoute<T>(builder: builder);
  }

  static Route<T> slideUp<T>({required WidgetBuilder builder}) {
    // BUG-11: same fix — CurvedAnimation lives for the duration of the route.
    return _SlideUpRoute<T>(builder: builder);
  }
}

// ---------------------------------------------------------------------------
// BUG-11 fix: stateful route that owns + disposes its CurvedAnimation.
// ---------------------------------------------------------------------------

class _FadeScaleRoute<T> extends PageRouteBuilder<T> {
  final WidgetBuilder _builder;

  _FadeScaleRoute({required WidgetBuilder builder})
      : _builder = builder,
        super(
          transitionDuration: AppRouteTransitions.forwardDuration,
          reverseTransitionDuration: AppRouteTransitions.reverseDuration,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
        );

  // One CurvedAnimation for the lifetime of this route.
  late final CurvedAnimation _curved = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: _curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.98, end: 1.0).animate(_curved),
        child: child,
      ),
    );
  }

  @override
  void dispose() {
    _curved.dispose();
    super.dispose();
  }
}

class _SlideUpRoute<T> extends PageRouteBuilder<T> {
  final WidgetBuilder _builder;

  _SlideUpRoute({required WidgetBuilder builder})
      : _builder = builder,
        super(
          opaque: false,
          barrierColor: Colors.transparent,
          transitionDuration: AppRouteTransitions.forwardDuration,
          reverseTransitionDuration: AppRouteTransitions.reverseDuration,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
        );

  late final CurvedAnimation _curved = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(_curved),
      child: child,
    );
  }

  @override
  void dispose() {
    _curved.dispose();
    super.dispose();
  }
}