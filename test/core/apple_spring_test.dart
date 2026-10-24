import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';

void main() {
  group('Motion.appleSpring (WWDC23 "Animate with springs")', () {
    test('stiffness is (2π / duration)² with mass 1', () {
      final s = Motion.appleSpring(0.5);
      expect(s.mass, 1);
      expect(s.stiffness, closeTo(math.pow(2 * math.pi / 0.5, 2), 1e-9));
    });

    test('bounce 0 is critically damped: no overshoot', () {
      final s = Motion.appleSpring(0.5);
      expect(s.damping, closeTo(2 * math.sqrt(s.stiffness * s.mass), 1e-9));
      final sim = SpringSimulation(s, 0, 1, 0);
      for (var t = 0.0; t < 2; t += 0.01) {
        expect(sim.x(t), lessThanOrEqualTo(1 + 1e-6));
      }
    });

    test('positive bounce overshoots slightly, then settles', () {
      final sim = SpringSimulation(Motion.cover, 0.84, 1, 0);
      var peak = 0.0;
      for (var t = 0.0; t < 2; t += 0.005) {
        peak = math.max(peak, sim.x(t));
      }
      expect(peak, greaterThan(1));
      expect(peak, lessThan(1.05), reason: 'a landing, not a wobble');
      expect(sim.x(2), closeTo(1, 1e-3));
    });

    test('negative bounce is overdamped', () {
      final s = Motion.appleSpring(0.5, bounce: -0.3);
      expect(s.damping, greaterThan(2 * math.sqrt(s.stiffness)));
    });
  });
}
