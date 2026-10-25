import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'microduck_mesh.dart';
import 'microduck_pose.dart';
import 'microduck_rig.dart';
import 'microduck_texture.dart';

/// Draws the Microduck robot: a posed triangle mesh, lit per vertex by a key
/// light and a rim light with materials (a glossy helmet with a sharp
/// highlight and a soft environment band, satin panels, brushed metal, dark
/// rubber), baked ambient occlusion and edge wear, multiplied by a surface
/// texture, depth-sorted back to front and sent to `Canvas.drawVertices` in a
/// single call, with a contact shadow and a bloom around the LED.
///
/// Detail follows the size on screen ([meshLevel]): tiny robots skip bolts and
/// screws, large ones swap in higher-polygon parts.
///
/// Everything it touches each frame (buffers, the depth order) is allocated
/// once and shared by every robot on screen, since painting is synchronous.
class MicroduckPainter extends CustomPainter {
  final MicroduckPose pose;

  /// The animation clock, in seconds.
  final ValueListenable<double> time;
  final MicroduckSkin skin;

  /// Beats per minute while dancing.
  final int bpm;

  /// The robot's own state (rig, reactions).
  final MicroduckInput input;

  /// Walks to the right; false walks to the left.
  final bool facingRight;

  MicroduckPainter({
    required this.pose,
    required this.time,
    required this.input,
    this.skin = MicroduckSkin.white,
    this.bpm = defaultDanceBpm,
    this.facingRight = true,
  }) : super(repaint: Listenable.merge([time, MicroduckTexture.ready]));

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
      danceBeatSeconds(bpm),
      danceEnergy(bpm),
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

  late final int _v = mesh.vertexCount;
  late final int _t = mesh.triCount;
  late final Float32List _pos = Float32List(_v * 2);
  late final Int32List _col = Int32List(_v);
  late final Float32List _depth = Float32List(_v);
  late final Float32List _triDepth = Float32List(_t);
  late final Uint8List _front = Uint8List(_t);
  late final Uint16List _order = Uint16List.fromList([for (var i = 0; i < _t; i++) i]);
  late final Uint16List _idx = Uint16List(_t * 3);

  final Float64List _baseR = Float64List(kSlotCount);
  final Float64List _baseG = Float64List(kSlotCount);
  final Float64List _baseB = Float64List(kSlotCount);
  final Float64List _spec = Float64List(kSlotCount);
  final Float64List _power = Float64List(kSlotCount);
  final Float64List _env = Float64List(kSlotCount);

  final Paint _paint = Paint();
  final Paint _shadow = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
  final Paint _core = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
  final Paint _glow = Paint()..blendMode = BlendMode.plus;
  double _glowUnit = -1;
  final Paint _zPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Path _zPath = Path();

  // Key light up-left-front, rim light behind-right, view half-vector.
  static final double _klen = math.sqrt(0.25 + 0.5184 + 0.49);
  static final double _lx = -0.5 / _klen, _ly = 0.72 / _klen, _lz = 0.7 / _klen;
  static final double _rlen = math.sqrt(0.49 + 0.0625 + 0.4225);
  static final double _rx = 0.7 / _rlen, _ry = 0.25 / _rlen, _rz = -0.65 / _rlen;
  static const double _elev = 0.22; // camera looks down a little
  static final double _ce = math.cos(_elev), _se = math.sin(_elev);
  // The direction to the camera is (0, sin e, cos e).
  static final double _hlen = math.sqrt(_lx * _lx + (_ly + _se) * (_ly + _se) + (_lz + _ce) * (_lz + _ce));
  static final double _hx = _lx / _hlen, _hy = (_ly + _se) / _hlen, _hz = (_lz + _ce) / _hlen;

  int _lastSkinKey = -1;

  ui.ImageShader? _shader;

  /// Points the paint at the surface texture (with mip-mapping, so it
  /// averages out smoothly when the robot is small). False while the texture
  /// is still being made.
  bool _useTexture() {
    final img = MicroduckTexture.image;
    if (img == null) {
      MicroduckTexture.ensure();
      _paint.shader = null;
      return false;
    }
    _shader ??= ui.ImageShader(
      img,
      TileMode.repeated,
      TileMode.repeated,
      Float64List.fromList([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
      filterQuality: FilterQuality.medium,
    );
    _paint.shader = _shader;
    return true;
  }

  void _setSkin(MicroduckSkin skin) {
    if (_lastSkinKey == skin.index) return;
    _lastSkinKey = skin.index;
    final c = skin.colors;
    for (var p = 0; p < kSlotCount; p++) {
      _baseR[p] = ((c[p] >> 16) & 0xFF).toDouble();
      _baseG[p] = ((c[p] >> 8) & 0xFF).toDouble();
      _baseB[p] = (c[p] & 0xFF).toDouble();
      _spec[p] = kMaterials[p].spec;
      _power[p] = kMaterials[p].power;
      _env[p] = kMaterials[p].env;
    }
  }

  void draw(
    Canvas canvas,
    Offset origin,
    double s,
    MicroduckPose pose,
    double t,
    double beatSeconds,
    double energy,
    MicroduckSkin skin,
    MicroduckInput input,
    bool facingRight,
  ) {
    _setSkin(skin);
    final rig = input.rig..solve(pose, t, beatSeconds, input, facingRight: facingRight, energy: energy);
    final level = meshLevel(s);
    final unit = s / 7.2;
    final ox = origin.dx + s / 2;
    final oy = origin.dy + s * 0.955;
    final led = rig.pose.v[RigPose.led];
    final sq = rig.squash;

    // Contact shadow: wide and soft, with a tighter dark core that squashes
    // and fades the higher the robot is.
    final fade = 1 / (1 + math.max(0.0, rig.lift) * 0.9);
    final cx = ox + rig.pose.v[RigPose.x] * unit;
    final spread = (0.6 + 0.4 * fade) * (1 - 0.5 * sq);
    _shadow.color = Color.fromARGB((105 * fade).round(), 0, 0, 0);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, oy + 0.05 * unit), width: 2.4 * unit * spread, height: 0.66 * unit * spread),
      _shadow,
    );
    _core.color = Color.fromARGB((120 * fade * fade).round(), 0, 0, 0);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, oy + 0.04 * unit), width: 1.3 * unit * spread, height: 0.3 * unit * spread),
      _core,
    );

    final px = mesh.px, py = mesh.py, pz = mesh.pz;
    final nx = mesh.nx, ny = mesh.ny, nz = mesh.nz;
    final matrixId = mesh.matrix, slotId = mesh.slot, dynId = mesh.dyn, aoA = mesh.ao, wearA = mesh.wear;
    final lodMin = mesh.lodMin, lodMax = mesh.lodMax;
    final mats = rig.matrices;
    final pos = _pos, col = _col, depth = _depth;
    final fsx = rig.faceSx, fsy = rig.faceSy, fox = rig.faceOx, foy = rig.faceOy;
    final dcx = mesh.dynCx, dcy = mesh.dynCy;
    // Volume-preserving: taller means thinner by the square root.
    final stretch = 1 + sq, narrow = 1 / math.sqrt(stretch);
    for (var i = 0; i < _v; i++) {
      if (lodMin[i] > level || lodMax[i] < level) continue;
      final m = mats[matrixId[i]].m;
      var x = px[i], y = py[i];
      final z = pz[i];
      final d0 = dynId[i];
      if (d0 > 0) {
        x = dcx[d0] + (x - dcx[d0]) * fsx[d0] + fox[d0];
        y = dcy[d0] + (y - dcy[d0]) * fsy[d0] + foy[d0];
      }
      final wx = (m[0] * x + m[1] * y + m[2] * z + m[3]) * narrow;
      final wy = (m[4] * x + m[5] * y + m[6] * z + m[7]) * stretch;
      final wz = (m[8] * x + m[9] * y + m[10] * z + m[11]) * narrow;
      final yc = wy * _ce - wz * _se;
      final dp = wy * _se + wz * _ce;
      final f = 1 / (1 - 0.045 * dp) * unit;
      pos[i * 2] = ox + wx * f;
      pos[i * 2 + 1] = oy - yc * f;
      depth[i] = dp;

      final sl = slotId[i];
      double r, g, b;
      if (slotEmissive(sl)) {
        final k = sl == sLed ? 0.25 + 0.75 * led : 1.0;
        r = _baseR[sl] * k;
        g = _baseG[sl] * k;
        b = _baseB[sl] * k;
      } else {
        final ax = nx[i], ay = ny[i], az = nz[i];
        final wnx = m[0] * ax + m[1] * ay + m[2] * az;
        final wny = m[4] * ax + m[5] * ay + m[6] * az;
        final wnz = m[8] * ax + m[9] * ay + m[10] * az;
        final ao = aoA[i];
        final key = math.max(0.0, wnx * _lx + wny * _ly + wnz * _lz);
        final fill = math.max(0.0, wnx * 0.6 - wnz * 0.2 + wny * 0.1) * 0.12;
        final rim = math.max(0.0, wnx * _rx + wny * _ry + wnz * _rz);
        // x1.07: the surface texture averages 0.93 and takes it back down.
        final k = ((0.34 + 0.12 * wny) + 0.82 * key + fill) * ao * 1.07;
        var add = rim * rim * 40;
        final spec = _spec[sl];
        if (spec > 0.05) {
          // Sharp hotspot (the power is the material's tightness) ...
          final h = math.max(0.0, wnx * _hx + wny * _hy + wnz * _hz);
          if (h > 0.05) add += math.pow(h, _power[sl]) * spec * 190 * ao;
          // ... and a soft horizontal band of environment in the reflection.
          final env = _env[sl];
          if (env > 0.03) {
            final nv = wny * _se + wnz * _ce;
            final ry = 2 * nv * wny - _se;
            final band = (ry - 0.32) / 0.16;
            add += math.exp(-band * band) * env * 120 * ao;
          }
        } else if (spec > 0) {
          final h = math.max(0.0, wnx * _hx + wny * _hy + wnz * _hz);
          add += h * h * 6;
        }
        // Worn edges: the paint is rubbed through, a lighter tone shows.
        add += wearA[i] * 26;
        r = _baseR[sl] * k + add;
        g = _baseG[sl] * k + add;
        b = _baseB[sl] * k + add;
      }
      col[i] = 0xFF000000 |
          (math.min(255, r.round()) << 16) |
          (math.min(255, g.round()) << 8) |
          math.min(255, b.round());
    }

    // Cull back faces and what this level skips; order far to near.
    final tris = mesh.tris, triMin = mesh.triMin, triMax = mesh.triMax, bias = mesh.triBias;
    final tdepth = _triDepth, front = _front, order = _order;
    for (var k = 0; k < _t; k++) {
      if (triMin[k] > level || triMax[k] < level) {
        front[k] = 0;
        tdepth[k] = 0;
        continue;
      }
      final a = tris[k * 3], b = tris[k * 3 + 1], c = tris[k * 3 + 2];
      final cross = (pos[b * 2] - pos[a * 2]) * (pos[c * 2 + 1] - pos[a * 2 + 1]) -
          (pos[c * 2] - pos[a * 2]) * (pos[b * 2 + 1] - pos[a * 2 + 1]);
      front[k] = cross < 0 ? 1 : 0;
      tdepth[k] = depth[a] + depth[b] + depth[c] + bias[k];
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
      final textured = _useTexture();
      final vertices = ui.Vertices.raw(
        ui.VertexMode.triangles,
        pos,
        textureCoordinates: textured ? mesh.uv : null,
        colors: col,
        indices: Uint16List.sublistView(idx, 0, n),
      );
      // Vertex colours times the surface texture, or the colours alone while
      // the texture is still being made.
      canvas.drawVertices(vertices, textured ? BlendMode.modulate : BlendMode.src, _paint);
      vertices.dispose();
    }

    _ledBloom(canvas, rig, skin, led, ox, oy, unit);

    if (pose == MicroduckPose.sleep) {
      // Head position on screen, for the z's.
      final hm = rig.head.m;
      final hy = hm[7], hz = hm[11];
      final f = 1 / (1 - 0.045 * (hy * _se + hz * _ce)) * unit;
      _zzz(canvas, ox + hm[3] * f + 1.3 * unit, oy - (hy * _ce - hz * _se) * f - 1.5 * unit, unit, t);
    }
  }

  /// A soft halo around the lens eye, added on top, when it faces the camera.
  void _ledBloom(Canvas canvas, MicroduckRig rig, MicroduckSkin skin, double led, double ox, double oy, double unit) {
    if (led < 0.15) return;
    final m = rig.head.m;
    const lx = kEyeX, ly = kEyeY, lz = kEyeZ;
    final wx = m[0] * lx + m[1] * ly + m[2] * lz + m[3];
    final wy = m[4] * lx + m[5] * ly + m[6] * lz + m[7];
    final wz = m[8] * lx + m[9] * ly + m[10] * lz + m[11];
    // Facing: the direction from the head's centre out to the lens.
    final hx = m[1] * kHeadCy + m[3];
    final hy = m[5] * kHeadCy + m[7];
    final hz = m[9] * kHeadCy + m[11];
    final dx = wx - hx, dy = wy - hy, dz = wz - hz;
    final len = math.sqrt(dx * dx + dy * dy + dz * dz);
    final facing = (dy * _se + dz * _ce) / len;
    if (facing < 0.05) return;
    final yc = wy * _ce - wz * _se;
    final f = 1 / (1 - 0.045 * (wy * _se + wz * _ce)) * unit;
    final c = Offset(ox + wx * f, oy - yc * f);
    if ((unit - _glowUnit).abs() > unit * 0.1) {
      _glow.maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(1.0, unit * 0.2));
      _glowUnit = unit;
    }
    final rgb = skin.colors[sLens];
    final a = (70 * math.min(1.0, facing * 1.6)).round();
    _glow.color = Color.fromARGB(a, (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF);
    canvas.drawCircle(c, unit * 0.3, _glow);
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
