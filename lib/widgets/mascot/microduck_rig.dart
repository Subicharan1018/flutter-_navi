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

  void copy(RigPose o) => v.setAll(0, o.v);

  void lerpFrom(RigPose a, RigPose b, double w) {
    for (var i = 0; i < count; i++) {
      v[i] = a.v[i] + (b.v[i] - a.v[i]) * w;
    }
  }
}

/// One robot's live state: where a finger is, what reactions are running,
/// and its own rig (so several robots can move independently). Times are on
/// the robot's animation clock, in seconds.
class MicroduckInput {
  double lookX = 0, lookY = 0;
  double lookUntil = -100;

  double tapAt = -100;
  int tapCount = 0;
  double bowAt = -100;
  double startleAt = -100;
  double loveAt = -100;

  final MicroduckRig rig = MicroduckRig();

  static const double hopSeconds = 1.0;
  static const double bowSeconds = 1.8;
  static const double startleSeconds = 0.8;
  static const double loveSeconds = 1.8;
  static const double _lookFade = 0.8;

  /// Clock time until which frames should keep coming at full rate.
  double get activeUntil => math.max(
        math.max(tapAt + hopSeconds, bowAt + bowSeconds),
        math.max(math.max(startleAt + startleSeconds, loveAt + loveSeconds), lookUntil + _lookFade),
      );

  double lookWeight(double t) => t <= lookUntil ? 1 : math.max(0, 1 - (t - lookUntil) / _lookFade);

  /// 0..1 progress of a reaction that started at [at] and lasts [seconds],
  /// or -1 when it is not running.
  static double progress(double t, double at, double seconds) {
    final u = (t - at) / seconds;
    return u >= 0 && u <= 1 ? u : -1;
  }
}

double _smooth(double x) {
  final c = x.clamp(0.0, 1.0);
  return c * c * (3 - 2 * c);
}

/// 0 -> 1 -> 0 over [0, 1].
double _bump(double x) => x <= 0 || x >= 1 ? 0 : math.sin(math.pi * x);

const double _tau = 2 * math.pi;

/// Turns (pose, clock, tempo) into joint angles and then into one matrix per
/// joint. All state is preallocated; [solve] allocates nothing.
class MicroduckRig {
  final RigPose pose = RigPose();
  final RigPose _a = RigPose();
  final RigPose _b = RigPose();
  final RigPose _from = RigPose();
  final RigPose _final = RigPose();

  final Mat3x4 root = Mat3x4(), pelvis = Mat3x4(), neck = Mat3x4(), head = Mat3x4();
  final Mat3x4 hipL = Mat3x4(), kneeL = Mat3x4(), ankleL = Mat3x4();
  final Mat3x4 hipR = Mat3x4(), kneeR = Mat3x4(), ankleR = Mat3x4();

  /// Matrix for each joint, indexed by the mesh's matrix ids.
  late final List<Mat3x4> matrices = [pelvis, neck, head, hipL, kneeL, ankleL, hipR, kneeR, ankleR];

  /// How high the body is off the ground right now, in robot units.
  double lift = 0;

  /// Vertical squash(-)/stretch(+) from jumping and landing.
  double squash = 0;

  /// Face pieces' scale and offset on the screen (see the mesh's dyn ids).
  final Float32List faceSx = Float32List(kDynCount), faceSy = Float32List(kDynCount);
  final Float32List faceOx = Float32List(kDynCount), faceOy = Float32List(kDynCount);

  MicroduckPose? _prevPose;
  double _changeT = 0;
  double _lastT = -1;

  // Head spring (secondary motion): angle and velocity for yaw/pitch/roll.
  final Float64List _hAng = Float64List(3), _hVel = Float64List(3);
  double _sqVel = 0, _prevY = 0;

  void solve(
    MicroduckPose which,
    double t,
    double beatSeconds,
    MicroduckInput input, {
    bool facingRight = true,
    double energy = 1,
  }) {
    final p = pose;
    var dt = t - _lastT;
    final fresh = _lastT < 0 || dt <= 0 || dt > 0.25;
    if (fresh) dt = 0;
    _lastT = t;
    final amp = energy.clamp(0.6, 1.3);

    p.clear();
    var move = -1;
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
      case MicroduckPose.sit:
        _sit(p, t);
      case MicroduckPose.sleep:
        _sleep(p, t);
      case MicroduckPose.dance:
        move = _dance(p, t / beatSeconds, amp);
    }

    // Ease from whatever it was doing a moment ago.
    if (_prevPose != null && _prevPose != which && !fresh) {
      _from.copy(_final);
      _from.v[RigPose.yaw] = (_from.v[RigPose.yaw] + math.pi) % _tau - math.pi;
      _changeT = t;
    }
    _prevPose = which;
    final since = t - _changeT;
    if (since < 0.5 && _changeT > 0) {
      p.lerpFrom(_from, p, _smooth(since / 0.5));
    }

    // Reactions overlay the pose with an envelope in and out.
    var happy = 0.0, startle = 0.0;
    final hop = MicroduckInput.progress(t, input.tapAt, MicroduckInput.hopSeconds);
    if (hop >= 0) {
      final w = math.min(1.0, math.min(hop * 7, (1 - hop) * 7));
      if (input.tapCount.isOdd) {
        _wave(_a, hop);
      } else {
        _hop(_a, hop);
      }
      _b.copy(p);
      p.lerpFrom(_b, _a, w);
      happy = w;
    }
    final bow = MicroduckInput.progress(t, input.bowAt, MicroduckInput.bowSeconds);
    if (bow >= 0) {
      final w = math.min(1.0, math.min(bow * 5, (1 - bow) * 3));
      _bow(_a);
      _b.copy(p);
      p.lerpFrom(_b, _a, _smooth(w));
      happy = math.max(happy, w);
    }
    final st = MicroduckInput.progress(t, input.startleAt, MicroduckInput.startleSeconds);
    if (st >= 0) {
      final w = math.min(1.0, math.min(st * 12, (1 - st) * 4));
      _startle(_a, st);
      _b.copy(p);
      p.lerpFrom(_b, _a, w);
      startle = w;
    }
    final love = MicroduckInput.progress(t, input.loveAt, MicroduckInput.loveSeconds);
    if (love >= 0) {
      p.v[RigPose.y] += 0.14 * math.sin(_tau * love * 2).abs() * _bump(love * 1.1);
      happy = math.max(happy, _bump(love));
    }
    _final.copy(p);

    // Looking at a finger.
    final look = input.lookWeight(t);
    var tyaw = p.v[RigPose.headYaw], tpitch = p.v[RigPose.headPitch], troll = p.v[RigPose.headRoll];
    if (look > 0 && which != MicroduckPose.sleep) {
      tyaw += input.lookX * 0.8 * look;
      tpitch += input.lookY * 0.35 * look;
    }
    // The head follows through a spring: it lags the body, overshoots a
    // little and settles.
    if (fresh) {
      _hAng[0] = tyaw;
      _hAng[1] = tpitch;
      _hAng[2] = troll;
      _hVel.fillRange(0, 3, 0);
    } else {
      const k = 190.0, c = 15.0;
      final steps = (dt / 0.01).ceil().clamp(1, 12);
      final h = dt / steps;
      for (var s = 0; s < steps; s++) {
        _hVel[0] += (k * (tyaw - _hAng[0]) - c * _hVel[0]) * h;
        _hVel[1] += (k * (tpitch - _hAng[1]) - c * _hVel[1]) * h;
        _hVel[2] += (k * (troll - _hAng[2]) - c * _hVel[2]) * h;
        for (var i = 0; i < 3; i++) {
          _hAng[i] += _hVel[i] * h;
        }
      }
    }
    p.v[RigPose.headYaw] = _hAng[0];
    p.v[RigPose.headPitch] = _hAng[1];
    p.v[RigPose.headRoll] = _hAng[2];

    _compose(p);
    _squash(p.v[RigPose.y], dt, fresh);
    _face(which, p, t, beatSeconds, happy, startle, love, move, amp, input);
  }

  // ------------------------------------------------------------ base poses

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
    v[RigPose.led] = 1;

    // A fidget every six seconds: tap a foot, check the screen, scratch the
    // helmet, stretch, or just look about.
    final slot = (t / 6).floor();
    final local = t - slot * 6;
    final w = _bump((local - 1.5) / 2.6);
    switch (slot % 5) {
      case 1:
        v[RigPose.kneeL] += 0.25 * w;
        v[RigPose.hipL] += 0.25 * w;
        v[RigPose.ankleL] = 0.55 * w * math.sin(local * 13).abs();
        v[RigPose.headYaw] -= 0.3 * w;
      case 2:
        v[RigPose.headPitch] += 0.75 * w;
        v[RigPose.pitch] += 0.12 * w;
        v[RigPose.headYaw] *= 1 - w;
      case 3:
        v[RigPose.headRoll] += 0.3 * w * math.sin(local * 19);
        v[RigPose.headYaw] = v[RigPose.headYaw] * (1 - w) + 0.4 * w;
      case 4:
        v[RigPose.twist] = 0.5 * w * math.sin(local * 4.5);
        v[RigPose.pitch] -= 0.1 * w;
        v[RigPose.headPitch] -= 0.25 * w;
      default:
        break;
    }
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

  void _sit(RigPose p, double t) {
    final v = p.v;
    final breath = math.sin(t * 1.7);
    v[RigPose.yaw] = 0.5;
    v[RigPose.hipL] = v[RigPose.hipR] = 0.9;
    v[RigPose.kneeL] = v[RigPose.kneeR] = 1.5;
    v[RigPose.pitch] = 0.04 + 0.015 * breath;
    v[RigPose.headYaw] = 0.5 * math.sin(t * 0.5);
    v[RigPose.headPitch] = 0.05 * math.sin(t * 0.8);
    v[RigPose.rollL] = v[RigPose.rollR] = 0.22;
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

  // ------------------------------------------------------------- reactions

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

  /// A wave: one foot up, wagging, head tilted.
  void _wave(RigPose p, double u) {
    p.clear();
    final v = p.v;
    v[RigPose.yaw] = 0.25;
    v[RigPose.hipL] = 0.75;
    v[RigPose.kneeL] = 0.5;
    v[RigPose.ankleL] = 0.5 * math.sin(u * 30);
    v[RigPose.hipR] = 0.05;
    v[RigPose.kneeR] = 0.3;
    v[RigPose.rollL] = 0.2;
    v[RigPose.rollR] = 0.08;
    v[RigPose.roll] = -0.12;
    v[RigPose.headRoll] = 0.25 * math.sin(u * 16);
    v[RigPose.headPitch] = -0.1;
    v[RigPose.led] = 1;
  }

  /// A bow from the hips, head kept up.
  void _bow(RigPose p) {
    p.clear();
    final v = p.v;
    v[RigPose.yaw] = 0.15;
    v[RigPose.pitch] = 0.95;
    v[RigPose.hipL] = v[RigPose.hipR] = 0.5;
    v[RigPose.kneeL] = v[RigPose.kneeR] = 0.3;
    v[RigPose.headPitch] = -0.45;
    v[RigPose.rollL] = v[RigPose.rollR] = 0.08;
    v[RigPose.led] = 1;
  }

  /// A startled jump: up, legs apart, leaning back.
  void _startle(RigPose p, double u) {
    p.clear();
    final v = p.v;
    v[RigPose.y] = 0.8 * math.sin(math.pi * math.min(1, u * 1.4));
    v[RigPose.yaw] = 0.1;
    v[RigPose.rollL] = v[RigPose.rollR] = 0.45;
    v[RigPose.kneeL] = v[RigPose.kneeR] = 0.3;
    v[RigPose.pitch] = -0.22;
    v[RigPose.headPitch] = -0.35;
    v[RigPose.led] = 1;
  }

  // -------------------------------------------------------------- dancing

  /// Nine moves of four beats, looping: shuffle, moonwalk, hip twist, pop and
  /// lock, bounce-jump, spin, side wave, head-bang, sit-down groove. Each new
  /// move eases in from the one before. Returns the move index for the face.
  int _dance(RigPose p, double beats, double amp) {
    const order = [0, 6, 1, 5, 3, 2, 7, 4, 8];
    final block = beats ~/ 4;
    final bb = beats - 4 * block;
    final move = order[block % order.length];
    _move(move, p, beats, bb, amp);
    final w = _smooth(bb / 0.6);
    if (w < 1) {
      final prev = order[(block + order.length - 1) % order.length];
      _move(prev, _a, beats, bb + 4, amp);
      // Whole turns are the same pose: take the short way round.
      _a.v[RigPose.yaw] = (_a.v[RigPose.yaw] + math.pi) % _tau - math.pi;
      p.lerpFrom(_a, p, w);
    }
    return move;
  }

  void _move(int move, RigPose p, double b, double bb, double amp) {
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
      case 4: // head-bang
        final nod = math.sin(2 * _tau * b);
        v[RigPose.headPitch] = 0.45 + 0.65 * nod;
        v[RigPose.pitch] = 0.3 + 0.2 * math.sin(2 * _tau * b - 0.6);
        v[RigPose.kneeL] = v[RigPose.kneeR] = 0.55 + 0.22 * nod;
        v[RigPose.hipL] = v[RigPose.hipR] = 0.3 + 0.1 * nod;
        v[RigPose.rollL] = v[RigPose.rollR] = 0.22;
        v[RigPose.twist] = 0.2 * pulse;
        v[RigPose.roll] = 0.07 * math.sin(math.pi * b);
        v[RigPose.yaw] = 0.28 + 0.3 * math.sin(math.pi * b / 2);
      case 5: // pop and lock: snap to a new pose every half beat, then hold
        final step = (b * 2).floor();
        final fr = b * 2 - step;
        final snap = 1 - math.exp(-14 * fr);
        double pick(List<double> a) => a[(step - 1) % a.length] + (a[step % a.length] - a[(step - 1) % a.length]) * snap;
        v[RigPose.headYaw] = pick(const [-0.8, 0.8, -0.4, 0.4]);
        v[RigPose.twist] = pick(const [0.55, -0.55, 0.55, 0.0]);
        v[RigPose.roll] = pick(const [0.12, -0.12, 0.0, 0.12]);
        v[RigPose.headRoll] = pick(const [0.2, -0.2, 0.3, -0.3]);
        v[RigPose.kneeL] = v[RigPose.kneeR] = 0.45;
        v[RigPose.hipL] = v[RigPose.hipR] = 0.22;
        v[RigPose.rollL] = pick(const [0.3, 0.1, 0.1, 0.3]);
        v[RigPose.rollR] = pick(const [0.1, 0.3, 0.3, 0.1]);
        v[RigPose.headPitch] = 0.25 * math.exp(-8 * fr);
        v[RigPose.yaw] = 0.28 + pick(const [0.0, 0.35, -0.2, 0.2]);
      case 6: // moonwalk: side-on, feet gliding back while it drifts
        final s = math.sin(math.pi * b), c = math.cos(math.pi * b);
        v[RigPose.yaw] = 1.25;
        v[RigPose.hipL] = 0.4 * s;
        v[RigPose.hipR] = -0.4 * s;
        v[RigPose.kneeL] = 0.1 + 0.55 * math.max(0, -c);
        v[RigPose.kneeR] = 0.1 + 0.55 * math.max(0, c);
        v[RigPose.ankleL] = 0.6 * math.max(0, -c);
        v[RigPose.ankleR] = 0.6 * math.max(0, c);
        v[RigPose.pitch] = -0.1;
        v[RigPose.headYaw] = -0.9;
        v[RigPose.headPitch] = 0.05 * pulse;
        v[RigPose.x] = 0.5 - 0.25 * bb;
        v[RigPose.y] = 0.03 * pulse.abs();
      case 7: // side wave: a ripple through legs, hips and head
        final w = math.sin(math.pi * b);
        v[RigPose.x] = 0.3 * w;
        v[RigPose.roll] = 0.25 * w;
        v[RigPose.twist] = 0.4 * math.sin(math.pi * b - 0.7);
        v[RigPose.headRoll] = 0.5 * math.sin(math.pi * b - 1.2);
        v[RigPose.headYaw] = 0.4 * math.sin(math.pi * b - 0.4);
        v[RigPose.kneeL] = 0.45 + 0.35 * w;
        v[RigPose.kneeR] = 0.45 - 0.35 * w;
        v[RigPose.hipL] = v[RigPose.hipR] = 0.2;
        v[RigPose.rollL] = 0.18 + 0.2 * math.max(0, w);
        v[RigPose.rollR] = 0.18 + 0.2 * math.max(0, -w);
      default: // sit-down groove: low and loose
        v[RigPose.hipL] = v[RigPose.hipR] = 0.95 + 0.06 * pulse;
        v[RigPose.kneeL] = v[RigPose.kneeR] = 1.5 + 0.1 * pulse;
        v[RigPose.rollL] = v[RigPose.rollR] = 0.24;
        v[RigPose.pitch] = 0.1 + 0.05 * pulse;
        v[RigPose.twist] = 0.3 * math.sin(math.pi * b);
        v[RigPose.headPitch] = 0.1 + 0.3 * math.max(0, pulse);
        v[RigPose.headRoll] = 0.25 * math.sin(math.pi * b);
        v[RigPose.roll] = 0.1 * math.sin(math.pi * b);
    }
    // Louder songs move bigger.
    for (final i in const [
      RigPose.x,
      RigPose.y,
      RigPose.twist,
      RigPose.roll,
      RigPose.headPitch,
      RigPose.headRoll,
      RigPose.pitch,
    ]) {
      v[i] *= amp;
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

  /// Stretch while rising, squash on landing, through a spring so it wobbles.
  void _squash(double y, double dt, bool fresh) {
    if (fresh || dt <= 0) {
      squash = 0;
      _sqVel = 0;
      _prevY = y;
      return;
    }
    final vy = (y - _prevY) / dt;
    _prevY = y;
    final target = (vy * 0.05).clamp(-0.22, 0.16);
    const k = 320.0, c = 18.0;
    final steps = (dt / 0.01).ceil().clamp(1, 12);
    final h = dt / steps;
    for (var s = 0; s < steps; s++) {
      _sqVel += (k * (target - squash) - c * _sqVel) * h;
      squash += _sqVel * h;
    }
    squash = squash.clamp(-0.3, 0.25);
  }

  // -------------------------------------------------------------------- face

  /// What the screen shows: eyes that blink, look and squint, equaliser bars
  /// while dancing, a heart when liked.
  void _face(
    MicroduckPose which,
    RigPose p,
    double t,
    double beatSeconds,
    double happy,
    double startle,
    double love,
    int move,
    double amp,
    MicroduckInput input,
  ) {
    final sx = faceSx, sy = faceSy, ox = faceOx, oy = faceOy;
    sx.fillRange(0, kDynCount, 0);
    sy.fillRange(0, kDynCount, 0);
    ox.fillRange(0, kDynCount, 0);
    oy.fillRange(0, kDynCount, 0);

    if (love >= 0) {
      final pulse = 1 + 0.16 * math.sin(t * 14);
      sx[dHeart] = sy[dHeart] = pulse * _smooth(love * 6) * _smooth((1 - love) * 5);
      return;
    }
    if (which == MicroduckPose.dance) {
      final b = t / beatSeconds;
      for (var i = 0; i < dBarCount; i++) {
        final h = 0.18 + 0.82 * math.sin(_tau * (b * 0.5 + i * 0.19 + move * 0.07)).abs();
        sx[dBar0 + i] = 1;
        sy[dBar0 + i] = (h * (0.6 + 0.4 * amp)).clamp(0.12, 1.0);
      }
      return;
    }
    var open = 1.0;
    if (which == MicroduckPose.sleep) {
      open = 0.07;
    } else if ((t % 3.7) < 0.13) {
      open = 0.08;
    }
    var wide = 1.0, tall = open;
    if (happy > 0) {
      tall = open * (1 - 0.65 * happy);
      oy[dEyeL] = oy[dEyeR] = 0.015 * happy;
    }
    if (startle > 0) {
      wide = 1 + 0.35 * startle;
      tall = open * (1 + 0.4 * startle);
    }
    final look = input.lookWeight(t);
    final shift = (p.v[RigPose.headYaw] * 0.05 + input.lookX * 0.03 * look).clamp(-0.05, 0.05);
    final lookUp = (-p.v[RigPose.headPitch] * 0.03).clamp(-0.03, 0.03);
    for (final d in const [dEyeL, dEyeR]) {
      sx[d] = wide;
      sy[d] = tall;
      ox[d] = shift;
      oy[d] += lookUp;
    }
  }
}
