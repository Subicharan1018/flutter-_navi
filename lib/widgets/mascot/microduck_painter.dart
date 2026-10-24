import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'microduck_mesh.dart';
import 'microduck_pose.dart';
import 'microduck_rig.dart';

/// Draws the Microduck robot: a posed triangle mesh, Lambert-shaded per
/// vertex from one fixed light, depth-sorted back to front and sent to
/// `Canvas.drawVertices` in a single call, with a soft shadow on the ground.
///
/// Everything it touches each frame (matrices, vertex/colour/index buffers,
/// the depth order) is allocated once and shared by every robot on screen,
/// since painting is synchronous.
class MicroduckPainter extends CustomPainter {
  final MicroduckPose pose;

  /// The animation clock, in seconds.
  final ValueListenable<double> time;
  final MicroduckSkin skin;

  /// Beats per minute while dancing.
  final int bpm;
  final MicroduckInput input;

  /// Walks to the right; false walks to the left.
  final bool facingRight;

  const MicroduckPainter({
    required this.pose,
    required this.time,
    required this.input,
    this.skin = MicroduckSkin.white,
    this.bpm = defaultDanceBpm,
    this.facingRight = true,
  }) : super(repaint: time);

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    if (s <= 0) return;
    _Renderer.shared.draw(
      canvas,
      Offset((size.width - s) / 2, (size.height - s) / 2),
      s,
      pose,
      time.value,
      60 / bpm,
      skin,
      input,
      facingRight,
    );
  }

  @override
  bool shouldRepaint(MicroduckPainter old) =>
      old.pose != pose ||
      old.skin != skin ||
      old.bpm != bpm ||
      old.facingRight != facingRight ||
      old.time != time ||
      old.input != input;
}

class _Renderer {
  static final _Renderer shared = _Renderer();

  final MicroduckMesh mesh = MicroduckMesh.instance;
  final MicroduckRig rig = MicroduckRig();

  late final int _v = mesh.vertexCount;
  late final int _t = mesh.triCount;
  late final Float32List _pos = Float32List(_v * 2);
  late final Int32List _col = Int32List(_v);
  late final Float32List _depth = Float32List(_v);
  late final Float32List _triDepth = Float32List(_t);
  late final Uint8List _front = Uint8List(_t);
  late final Uint16List _order = Uint16List.fromList([for (var i = 0; i < _t; i++) i]);
  late final Uint16List _idx = Uint16List(_t * 3);

  final Float64List _baseR = Float64List(kPartCount);
  final Float64List _baseG = Float64List(kPartCount);
  final Float64List _baseB = Float64List(kPartCount);

  final Paint _paint = Paint();
  final Paint _shadow = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
  final Paint _zPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Path _zPath = Path();

  // Fixed light, up-left-front, normalised.
  static final double _lx = -0.5 / _llen, _ly = 0.72 / _llen, _lz = 0.7 / _llen;
  static final double _llen = math.sqrt(0.25 + 0.5184 + 0.49);

  static const double _elev = 0.22; // camera looks down a little
  static final double _ce = math.cos(_elev), _se = math.sin(_elev);

  int _lastSkinKey = -1;
  double _ledR = 0, _ledG = 0, _ledB = 0;

  void _setSkin(MicroduckSkin skin) {
    if (_lastSkinKey == skin.index) return;
    _lastSkinKey = skin.index;
    final c = skin.colors;
    for (var p = 0; p < kPartCount; p++) {
      final rgb = c[kPartColor[p]];
      _baseR[p] = ((rgb >> 16) & 0xFF).toDouble();
      _baseG[p] = ((rgb >> 8) & 0xFF).toDouble();
      _baseB[p] = (rgb & 0xFF).toDouble();
    }
    _ledR = ((skin.led >> 16) & 0xFF).toDouble();
    _ledG = ((skin.led >> 8) & 0xFF).toDouble();
    _ledB = (skin.led & 0xFF).toDouble();
  }

  void draw(
    Canvas canvas,
    Offset origin,
    double s,
    MicroduckPose pose,
    double t,
    double beatSeconds,
    MicroduckSkin skin,
    MicroduckInput input,
    bool facingRight,
  ) {
    _setSkin(skin);
    rig.solve(pose, t, beatSeconds, input, facingRight: facingRight);
    final unit = s / 5.7;
    final ox = origin.dx + s / 2;
    final oy = origin.dy + s * 0.955;
    final led = rig.pose.v[RigPose.led];

    // Ground shadow: smaller and fainter the higher the robot is.
    final air = math.max(0.0, rig.lift - 0.0);
    final fade = 1 / (1 + air * 0.9);
    _shadow.color = Color.fromARGB((120 * fade).round(), 0, 0, 0);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(ox + rig.pose.v[RigPose.x] * unit, oy + 0.05 * unit),
        width: 2.3 * unit * (0.6 + 0.4 * fade),
        height: 0.62 * unit * (0.6 + 0.4 * fade),
      ),
      _shadow,
    );

    final px = mesh.px, py = mesh.py, pz = mesh.pz;
    final nx = mesh.nx, ny = mesh.ny, nz = mesh.nz;
    final part = mesh.part;
    final mats = rig.partMatrices;
    final pos = _pos, col = _col, depth = _depth;
    for (var i = 0; i < _v; i++) {
      final p = part[i];
      final m = mats[p].m;
      final x = px[i], y = py[i], z = pz[i];
      final wx = m[0] * x + m[1] * y + m[2] * z + m[3];
      final wy = m[4] * x + m[5] * y + m[6] * z + m[7];
      final wz = m[8] * x + m[9] * y + m[10] * z + m[11];
      final yc = wy * _ce - wz * _se;
      final d = wy * _se + wz * _ce;
      final f = 1 / (1 - 0.045 * d) * unit;
      pos[i * 2] = ox + wx * f;
      pos[i * 2 + 1] = oy - yc * f;
      depth[i] = d;

      double r, g, b;
      if (p == kLed) {
        final k = 0.25 + 0.75 * led;
        r = _ledR * k;
        g = _ledG * k;
        b = _ledB * k;
      } else {
        final ax = nx[i], ay = ny[i], az = nz[i];
        final wnx = m[0] * ax + m[1] * ay + m[2] * az;
        final wny = m[4] * ax + m[5] * ay + m[6] * az;
        final wnz = m[8] * ax + m[9] * ay + m[10] * az;
        final key = math.max(0.0, wnx * _lx + wny * _ly + wnz * _lz);
        final fill = math.max(0.0, wnx * 0.6 - wnz * 0.2 + wny * 0.1) * 0.14;
        final k = 0.34 + 0.12 * wny + 0.82 * key + fill;
        r = _baseR[p] * k;
        g = _baseG[p] * k;
        b = _baseB[p] * k;
      }
      col[i] = 0xFF000000 |
          (math.min(255, r.round()) << 16) |
          (math.min(255, g.round()) << 8) |
          math.min(255, b.round());
    }

    // Cull back faces and order the rest far to near.
    final tris = mesh.tris;
    final tdepth = _triDepth, front = _front, order = _order;
    for (var k = 0; k < _t; k++) {
      final a = tris[k * 3], b = tris[k * 3 + 1], c = tris[k * 3 + 2];
      final cross = (pos[b * 2] - pos[a * 2]) * (pos[c * 2 + 1] - pos[a * 2 + 1]) -
          (pos[c * 2] - pos[a * 2]) * (pos[b * 2 + 1] - pos[a * 2 + 1]);
      front[k] = cross < 0 ? 1 : 0;
      tdepth[k] = depth[a] + depth[b] + depth[c];
    }
    // Insertion sort: the order from the last frame is nearly right.
    for (var i = 1; i < _t; i++) {
      final cur = order[i];
      final key = tdepth[cur];
      var j = i - 1;
      while (j >= 0 && tdepth[order[j]] > key) {
        order[j + 1] = order[j];
        j--;
      }
      order[j + 1] = cur;
    }
    var n = 0;
    final idx = _idx;
    for (var i = 0; i < _t; i++) {
      final k = order[i];
      if (front[k] == 0) continue;
      idx[n++] = tris[k * 3];
      idx[n++] = tris[k * 3 + 1];
      idx[n++] = tris[k * 3 + 2];
    }
    if (n > 0) {
      final vertices = ui.Vertices.raw(
        ui.VertexMode.triangles,
        pos,
        colors: col,
        indices: Uint16List.sublistView(idx, 0, n),
      );
      canvas.drawVertices(vertices, BlendMode.src, _paint);
      vertices.dispose();
    }

    if (pose == MicroduckPose.sleep) {
      // Head position on screen, for the z's.
      final hm = rig.head.m;
      final hy = hm[7], hz = hm[11];
      final f = 1 / (1 - 0.045 * (hy * _se + hz * _ce)) * unit;
      _zzz(canvas, ox + hm[3] * f + 0.9 * unit, oy - (hy * _ce - hz * _se) * f - 0.2 * unit, unit, t);
    }
  }

  /// Three z's rising from the helmet and fading.
  void _zzz(Canvas canvas, double x0, double y0, double unit, double t) {
    for (var i = 0; i < 3; i++) {
      final p = ((t / 3.4) + i / 3) % 1;
      final size = unit * (0.28 + p * 0.3);
      final x = x0 + p * unit * 0.8;
      final y = y0 - p * unit * 1.4;
      final a = (p < 0.15 ? p / 0.15 : (1 - p) / 0.85).clamp(0.0, 1.0);
      _zPaint
        ..color = Color.fromRGBO(255, 255, 255, a * 0.9)
        ..strokeWidth = math.max(1, unit * 0.1);
      _zPath
        ..reset()
        ..moveTo(x, y)
        ..lineTo(x + size, y)
        ..lineTo(x, y + size)
        ..lineTo(x + size, y + size);
      canvas.drawPath(_zPath, _zPaint);
    }
  }
}
