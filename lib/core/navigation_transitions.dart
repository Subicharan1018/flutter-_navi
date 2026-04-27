import 'package:flutter/material.dart';

class AppRouteTransitions {
  static const Duration forwardDuration = Duration(milliseconds: 360);
  static const Duration reverseDuration = Duration(milliseconds: 260);

  static Route<T> fadeScale<T>({required WidgetBuilder builder}) {
    return PageRouteBuilder<T>(
      transitionDuration: forwardDuration,
      reverseTransitionDuration: reverseDuration,
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  static Route<T> slideUp<T>({required WidgetBuilder builder}) {
    return PageRouteBuilder<T>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: forwardDuration,
      reverseTransitionDuration: reverseDuration,
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }
}