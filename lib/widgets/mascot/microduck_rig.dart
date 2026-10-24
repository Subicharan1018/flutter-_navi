import 'dart:math' as math;
import 'dart:typed_data';

import 'microduck_mesh.dart';
import 'microduck_pose.dart';

/// A 3x4 affine matrix (rotation + translation), row-major, with in-place
/// post-multiplying operations so a pose is built without allocating.
class Mat3x4 {
  final Float64List m = Float64List(12);

  Mat3x4() {
    identity();
  }

  void identity() {
    m
      ..fillRange(0, 12, 0)
      ..[0] = 1
      ..[5] = 1
      ..[10] = 1;
  }

  void set(Mat3x4 o) => m.setAll(0, o.m);

  void translate(double x, double y, double z) {
    m[3] += m[0] * x + m[1] * y + m[2] * z;
    m[7] += m[4] * x + m[5] * y + m[6] * z;
    m[11] += m[8] * x + m[9] * y + m[10] * z;
  }

  void rotateX(double a) {
    final c = math.cos(a), s = math.sin(a);
    for (var r = 0; r < 12; r += 4) {
      final c1 = m[r + 1], c2 = m[r + 2];
      m[r + 1] = c * c1 + s * c2;
      m[r + 2] = -s * c1 + c * c2;
    }
  }

  void rotateY(double a) {
    final c = math.cos(a), s = math.sin(a);
    for (var r = 0; r < 12; r += 4) {
      final c0 = m[r], c2 = m[r + 2];
      m[r] = c * c0 - s * c2;
      m[r + 2] = s * c0 + c * c2;
    }
  }

  void rotateZ(double a) {
    final c = math.cos(a), s = math.sin(a);
    for (var r = 0; r < 12; r += 4) {
      final c0 = m[r], c1 = m[r + 1];
      m[r] = c * c0 + s * c1;
      m[r + 1] = -s * c0 + c * c1;
    }
  }
}

/// The joint angles (radians, "forward / outward is positive") and offsets
/// that describe one instant of the robot.
class RigPose {
  static const int x = 0, y = 1, z = 2, yaw = 3, roll = 4, pitch = 5, twist = 6;
  static const int headYaw = 7, headPitch = 8, headRoll = 9;
  static const int hipL = 10, hipR = 11, rollL = 12, rollR = 13;
  static const int kneeL = 14, kneeR = 15, ankleL = 16, ankleR = 17, led = 18;
  static const int count = 19;

  final Float64List v = Float64List(count);

  void clear() => v.fillRange(0, count, 0);

  void lerpFrom(RigPose a, RigPose b, double w) {
    for (var i = 0; i < count; i++) {
      v[i] = a.v[i] + (b.v[i] - a.v[i]) * w;
    }
  }
}

/// Where the user is poking: a tap hops the robot, a finger down turns its
/// head to look. Read by the rig on the animation clock.
class MicroduckInput {
  double lookX = 0, lookY = 0;
  double tapAt = -100;
  double lookUntil = -100;

  /// Clock time until which frames should keep coming at full rate.
  double get activeUntil => math.max(tapAt + _hopSeconds, lookUntil + _lookFade);

  static const double _hopSeconds = 0.95;
  static const double _lookFade = 0.8;

  double lookWeight(double t) => t <= lookUntil ? 1 : math.max(0, 1 - (t - lookUntil) / _lookFade);
  double hopProgress(double t) => (t - tapAt) / _hopSeconds;
}

double _smooth(double x) {
  final c = x.clamp(0.0, 1.0);
  return c * c * (3 - 2 * c);
}

const double _tau = 2 * math.pi;

/// Turns (pose, clock, tempo) into joint angles and then into one matrix per
/// body part. All state is preallocated; [solve] allocates nothing.
class MicroduckRig {
  final RigPose pose = RigPose();
  final RigPose _a = RigPose();
  final RigPose _b = RigPose();

  final Mat3x4 root = Mat3x4(), pelvis = Mat3x4(), neck = Mat3x4(), head = Mat3x4();
  final Mat3x4 hipL = Mat3x4(), kneeL = Mat3x4(), ankleL = Mat3x4();
  final Mat3x4 hipR = Mat3x4(), kneeR = Mat3x4(), ankleR = Mat3x4();

  /// Matrix for each mesh part (indexes match the mesh's part ids).
  late final List<Mat3x4> partMatrices = [
    pelvis, pelvis, neck, head, head, head, hipL, kneeL, ankleL, hipR, kneeR, ankleR,
  ];

  /// How high the body is off the ground right now, in robot units.
  double lift = 0;

  void solve(MicroduckPose which, double t, double beatSeconds, MicroduckInput input, {bool facingRight = true}) {
    final p = pose;
    p.clear();
    switch (which) {
      case MicroduckPose.idle:
        _idle(p, t);
      case MicroduckPose.walk:
        _walk(p, t * 7, 0.5, 0.8, 0.06);
        p.v[RigPose.yaw] = facingRight ? 1.25 : -1.25;
      case MicroduckPose.run:
        _walk(p, t * 11, 0.85, 1.3, 0.22);
        p.v[RigPose.y] = 0.16 * math.max(0, math.sin(t * 22));
        p.v[RigPose.yaw] = facingRight ? 1.25 : -1.25;
      case MicroduckPose.sleep:
        _sleep(p, t);
      case MicroduckPose.dance:
        _dance(p, t / beatSeconds);
    }

    // A tap interrupts whatever it was doing with a happy hop.
    final u = input.hopProgress(t);
    if (u >= 0 && u <= 1) {
      _hop(_a, u);
      final w = math.min(1, math.min(u * 7, (1 - u) * 7)).toDouble();
      _b.v.setAll(0, p.v);
      p.lerpFrom(_b, _a, w);
    }
    final look = input.lookWeight(t);
    if (look > 0 && which != MicroduckPose.sleep) {
      p.v[RigPose.headYaw] += input.lookX * 0.8 * look;
      p.v[RigPose.headPitch] += input.lookY * 0.35 * look;
    }
    _compose(p);
  }

  void _idle(RigPose p, double t) {
    final v = p.v;
    v[RigPose.yaw] = 0.45 + 0.08 * math.sin(t * 0.37);
    final breath = math.sin(t * 1.9);
    v[RigPose.hipL] = v[RigPose.hipR] = 0.06 + 0.015 * breath;
    v[RigPose.kneeL] = v[RigPose.kneeR] = 0.12 + 0.03 * breath;
    v[RigPose.pitch] = 0.02 * breath;
    v[RigPose.headYaw] = 0.5 * math.sin(t * 0.55) + 0.2 * math.sin(t * 1.4);
    v[RigPose.headPitch] = 0.07 * math.sin(t * 0.9) - 0.03;
    v[RigPose.headRoll] = 0.05 * math.sin(t * 0.7);
    v[RigPose.rollL] = v[RigPose.rollR] = 0.04;
    v[RigPose.led] = (t % 4.2) < 0.13 ? 0.1 : 1;
  }

  void _walk(RigPose p, double ph, double stride, double lift, double lean) {
    final v = p.v;
    final s = math.sin(ph), c = math.cos(ph);
    v[RigPose.hipL] = stride * s;
    v[RigPose.hipR] = -stride * s;
    v[RigPose.kneeL] = 0.14 + lift * math.max(0, c);
    v[RigPose.kneeR] = 0.14 + lift * math.max(0, -c);
    v[RigPose.twist] = 0.2 * s;
    v[RigPose.roll] = 0.05 * s;
    v[RigPose.pitch] = lean;
    v[RigPose.headYaw] = -0.12 * s;
    v[RigPose.headPitch] = 0.04 + 0.03 * math.sin(2 * ph);
    v[RigPose.rollL] = v[RigPose.rollR] = 0.05;
    v[RigPose.led] = 1;
  }

  void _sleep(RigPose p, double t) {
    final v = p.v;
    final breath = math.sin(t * 1.3);
    v[RigPose.yaw] = 0.4;
    v[RigPose.hipL] = v[RigPose.hipR] = 0.95;
    v[RigPose.kneeL] = v[RigPose.kneeR] = 1.55;
    v[RigPose.pitch] = 0.38 + 0.02 * breath;
    v[RigPose.headPitch] = 0.55 + 0.03 * breath;
    v[RigPose.headRoll] = 0.12;
    v[RigPose.rollL] = v[RigPose.rollR] = 0.2;
    v[RigPose.led] = 0.1 + 0.05 * breath;
  }

  void _hop(RigPose p, double u) {
    p.clear();
    final v = p.v;
    final w = math.sin(_tau * u).abs();
    v[RigPose.y] = 0.95 * w * (1 - 0.35 * u);
    v[RigPose.yaw] = 0.2;
    final crouch = 1 - w;
    v[RigPose.hipL] = v[RigPose.hipR] = 0.5 * crouch * crouch;
    v[RigPose.kneeL] = v[RigPose.kneeR] = 0.15 + 0.9 * crouch * crouch;
    v[RigPose.rollL] = v[RigPose.rollR] = 0.3 * w;
    v[RigPose.headPitch] = -0.25 * w;
    v[RigPose.headRoll] = 0.2 * math.sin(_tau * u * 2);
    v[RigPose.led] = 1;
  }

  // -------------------------------------------------------------- dancing

  /// Five moves, four beats each, looping: side-step shuffle, hip twist with
  /// head bobs, spin turn, bounce-jump, head-bang. Each new move eases in
  /// over its first beat and a half from the one before.
  void _dance(RigPose p, double beats) {
    final block = beats ~/ 4;
    final bb = beats - 4 * block;
    final move = block % 5;
    _move(move, p, beats, bb);
    final w = _smooth(bb / 0.6);
    if (w < 1) {
      _move((move + 4) % 5, _a, beats, bb + 4);
      // Whole turns are the same pose: take the short way round.
      _a.v[RigPose.yaw] = (_a.v[RigPose.yaw] + math.pi) % _tau - math.pi;
      p.lerpFrom(_a, p, w);
    }
  }

  void _move(int move, RigPose p, double b, double bb) {
    p.clear();
    final v = p.v;
    final fb = b - b.floorToDouble();
    final pulse = math.sin(_tau * b);
    v[RigPose.yaw] = 0.28;
    v[RigPose.led] = 1 - 0.55 * fb;
    switch (move) {
      case 0: // side-step shuffle
        final side = math.sin(math.pi * b);
        final vel = math.cos(math.pi * b);
        v[RigPose.x] = 0.95 * side;
        v[RigPose.rollR] = 0.45 * math.max(0, vel);
        v[RigPose.rollL] = 0.45 * math.max(0, -vel);
        v[RigPose.kneeL] = 0.35 + 0.35 * math.max(0, vel);
        v[RigPose.kneeR] = 0.35 + 0.35 * math.max(0, -vel);
        v[RigPose.hipL] = v[RigPose.hipR] = 0.18;
        v[RigPose.twist] = 0.25 * side;
        v[RigPose.roll] = -0.1 * side;
        v[RigPose.pitch] = 0.08;
        v[RigPose.headPitch] = 0.22 * pulse;
        v[RigPose.headRoll] = 0.18 * side;
        v[RigPose.y] = 0.05 * pulse.abs();
      case 1: // hip twist with head bobs
        final tw = math.sin(math.pi * b);
        v[RigPose.twist] = 0.95 * tw;
        v[RigPose.roll] = 0.14 * tw;
        v[RigPose.yaw] = 0.28 - 0.25 * tw;
        v[RigPose.kneeL] = v[RigPose.kneeR] = 0.55 + 0.2 * pulse;
        v[RigPose.hipL] = v[RigPose.hipR] = 0.28 + 0.1 * pulse;
        v[RigPose.rollL] = v[RigPose.rollR] = 0.2;
        v[RigPose.headYaw] = -0.7 * tw;
        v[RigPose.headPitch] = 0.1 + 0.4 * math.max(0, pulse);
        v[RigPose.headRoll] = 0.2 * tw;
      case 2: // spin turn
        final s = _smooth(bb / 2.6);
        v[RigPose.yaw] = 0.28 + _tau * s;
        final tuck = math.sin(math.pi * math.min(1, bb / 2.6));
        v[RigPose.kneeL] = v[RigPose.kneeR] = 0.3 + 0.35 * tuck;
        v[RigPose.hipL] = v[RigPose.hipR] = 0.15 + 0.2 * tuck;
        v[RigPose.rollL] = v[RigPose.rollR] = 0.12;
        v[RigPose.y] = 0.1 * tuck + 0.06 * pulse.abs();
        v[RigPose.headPitch] = 0.1 * pulse;
        v[RigPose.headRoll] = 0.1 * math.sin(math.pi * b);
      case 3: // bounce-jump
        final air = math.sin(math.pi * fb);
        final crouch = (1 - air) * (1 - air);
        v[RigPose.y] = 1.3 * air;
        v[RigPose.kneeL] = v[RigPose.kneeR] = 0.12 + 0.95 * crouch;
        v[RigPose.hipL] = v[RigPose.hipR] = 0.5 * crouch;
        v[RigPose.rollL] = v[RigPose.rollR] = 0.12 + 0.3 * air;
        v[RigPose.ankleL] = v[RigPose.ankleR] = 0.3 * air;
        v[RigPose.pitch] = 0.18 * crouch;
        v[RigPose.headPitch] = -0.3 * air + 0.2 * crouch;
        v[RigPose.headRoll] = 0.12 * math.sin(math.pi * b);
      default: // head-bang
        final nod = math.sin(2 * _tau * b);
        v[RigPose.headPitch] = 0.45 + 0.65 * nod;
        v[RigPose.pitch] = 0.3 + 0.2 * math.sin(2 * _tau * b - 0.6);
        v[RigPose.kneeL] = v[RigPose.kneeR] = 0.55 + 0.22 * nod;
        v[RigPose.hipL] = v[RigPose.hipR] = 0.3 + 0.1 * nod;
        v[RigPose.rollL] = v[RigPose.rollR] = 0.22;
        v[RigPose.twist] = 0.2 * pulse;
        v[RigPose.roll] = 0.07 * math.sin(math.pi * b);
        v[RigPose.yaw] = 0.28 + 0.3 * math.sin(math.pi * b / 2);
    }
  }

  // ---------------------------------------------------------------- matrices

  void _compose(RigPose p) {
    final v = p.v;
    // Stand on the lower foot: the body sits so the lowest ankle touches the
    // ground, whatever the legs are doing.
    final dropL = _drop(v[RigPose.hipL], v[RigPose.kneeL], v[RigPose.rollL]);
    final dropR = _drop(v[RigPose.hipR], v[RigPose.kneeR], v[RigPose.rollR]);
    final hipWorld = kAnkleH + math.max(dropL, dropR) + v[RigPose.y];
    lift = hipWorld - kHipY;

    root
      ..identity()
      ..translate(v[RigPose.x], hipWorld, v[RigPose.z])
      ..rotateY(v[RigPose.yaw]);
    pelvis
      ..set(root)
      ..rotateY(v[RigPose.twist])
      ..rotateX(v[RigPose.pitch])
      ..rotateZ(v[RigPose.roll]);
    neck
      ..set(pelvis)
      ..translate(0, kNeckY, 0);
    head
      ..set(neck)
      ..translate(0, kHeadY, 0)
      ..rotateY(v[RigPose.headYaw])
      ..rotateX(v[RigPose.headPitch])
      ..rotateZ(v[RigPose.headRoll]);
    _leg(hipL, kneeL, ankleL, -kHipX, v[RigPose.hipL], v[RigPose.kneeL], v[RigPose.rollL], v[RigPose.ankleL], -1);
    _leg(hipR, kneeR, ankleR, kHipX, v[RigPose.hipR], v[RigPose.kneeR], v[RigPose.rollR], v[RigPose.ankleR], 1);
  }

  /// Hip-to-ankle height for a leg swung forward by [hip] and bent by [knee].
  static double _drop(double hip, double knee, double roll) =>
      (kThigh * math.cos(hip) + kShin * math.cos(hip - knee)) * math.cos(roll);

  void _leg(Mat3x4 hip, Mat3x4 knee, Mat3x4 ankle, double x, double a, double k, double roll, double ankleExtra, double side) {
    hip
      ..set(root)
      ..translate(x, 0, 0)
      ..rotateZ(roll * side)
      ..rotateX(-a);
    knee
      ..set(hip)
      ..translate(0, -kThigh, 0)
      ..rotateX(k);
    ankle
      ..set(knee)
      ..translate(0, -kShin, 0)
      ..rotateX(a - k + ankleExtra);
  }
}
