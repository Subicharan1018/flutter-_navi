import 'dart:math' as math;
import 'dart:typed_data';

import 'microduck_mesh.dart';

/// Collects triangles into a [MicroduckMesh]; see the primitives below.
class MeshBuilder {
  final List<double> _px = [], _py = [], _pz = [], _nx = [], _ny = [], _nz = [], _ao = [], _wear = [], _bias = [];
  final List<int> _matrix = [], _slot = [], _dyn = [], _lodMin = [], _lodMax = [];
  final List<int> _tris = [];
  final Float32List _dcx = Float32List(kDynCount), _dcy = Float32List(kDynCount);

  int _m = 0, _sl = 0, _d = 0, _lo = 0, _hi = 2;
  int _tierLo = 0, _tierHi = 2;
  double _biasOverride = -1;
  double Function(double, double, double)? ao;

  /// Which detail tier the following parts belong to: false = the ordinary
  /// version (levels 0-1), true = the high-resolution replacement (level 2),
  /// null = both (fine detail added on top).
  void tier(bool? hi) {
    switch (hi) {
      case false:
        _tierLo = 0;
        _tierHi = 1;
      case true:
        _tierLo = 2;
        _tierHi = 2;
      case null:
        _tierLo = 0;
        _tierHi = 2;
    }
  }

  /// Chooses the joint, colour slot and so on for what is added next. [lod] is
  /// the lowest detail level the parts appear at (1 = skipped for tiny robots,
  /// 2 = only for large ones); it is raised to the current tier's own range.
  void use(int m, int slot, {int lod = 0, int dyn = 0, double cx = 0, double cy = 0, double bias = -1}) {
    _m = m;
    _sl = slot;
    _d = dyn;
    _lo = math.max(lod, _tierLo);
    _hi = _tierHi;
    _biasOverride = bias;
    if (dyn > 0) {
      _dcx[dyn] = cx;
      _dcy[dyn] = cy;
    }
  }

  int _v(double x, double y, double z, double nx, double ny, double nz, [double wear = 0]) {
    _px.add(x);
    _py.add(y);
    _pz.add(z);
    _nx.add(nx);
    _ny.add(ny);
    _nz.add(nz);
    _ao.add(ao?.call(x, y, z) ?? 1);
    _wear.add(wear);
    _matrix.add(_m);
    _slot.add(_sl);
    _dyn.add(_d);
    _lodMin.add(_lo);
    _lodMax.add(_hi);
    _bias.add(_biasOverride);
    return _px.length - 1;
  }

  /// A triangle wound to face along its vertices' normals, so culling needs
  /// no per-part care.
  void _tri(int a, int b, int c) {
    final ux = _px[b] - _px[a], uy = _py[b] - _py[a], uz = _pz[b] - _pz[a];
    final vx = _px[c] - _px[a], vy = _py[c] - _py[a], vz = _pz[c] - _pz[a];
    final cx = uy * vz - uz * vy, cy = uz * vx - ux * vz, cz = ux * vy - uy * vx;
    final dot = cx * (_nx[a] + _nx[b] + _nx[c]) + cy * (_ny[a] + _ny[b] + _ny[c]) + cz * (_nz[a] + _nz[b] + _nz[c]);
    if (dot >= 0) {
      _tris.addAll([a, b, c]);
    } else {
      _tris.addAll([a, c, b]);
    }
  }

  /// A flat quad facing +z.
  void quad(double cx, double cy, double z, double hx, double hy) => quadFrom(cx, cy - hy, z, hx, hy * 2);

  /// A flat quad facing +z whose bottom edge sits at [y0] (so scaling its
  /// height about [y0] grows it upward).
  void quadFrom(double cx, double y0, double z, double hx, double height) {
    final y1 = y0 + height;
    final a = _v(cx - hx, y0, z, 0, 0, 1);
    final b = _v(cx + hx, y0, z, 0, 0, 1);
    final c = _v(cx + hx, y1, z, 0, 0, 1);
    final d = _v(cx - hx, y1, z, 0, 0, 1);
    _tri(a, b, c);
    _tri(a, c, d);
  }

  /// A flat triangle facing +z.
  void triangle(double x0, double y0, double x1, double y1, double x2, double y2, double z) {
    _tri(_v(x0, y0, z, 0, 0, 1), _v(x1, y1, z, 0, 0, 1), _v(x2, y2, z, 0, 0, 1));
  }

  /// A heart from a fan around its middle, facing +z.
  void heart(double cx, double cy, double z, double s) {
    const n = 16;
    final centre = _v(cx, cy, z, 0, 0, 1);
    final ring = <int>[];
    for (var i = 0; i < n; i++) {
      final t = 2 * math.pi * i / n;
      final x = 16 * math.pow(math.sin(t), 3);
      final y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t);
      ring.add(_v(cx + x / 17 * s, cy + (y + 2.5) / 17 * s, z, 0, 0, 1));
    }
    for (var i = 0; i < n; i++) {
      _tri(centre, ring[i], ring[(i + 1) % n]);
    }
  }

  /// Pixel text on a face looking along +x (or -x for negative [x]): each 'X'
  /// in [rows] is a small raised box, [px] units on a side, starting at depth
  /// [z0] and height [y0] (top row), reading left to right as seen from
  /// outside.
  void pixelText(List<String> rows, double x, double y0, double z0, double px) {
    final dir = x < 0 ? -1.0 : 1.0; // viewer on the +x side sees -z to the right
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < rows[r].length; c++) {
        if (rows[r][c] != 'X') continue;
        simpleBox(x, y0 - r * px, z0 - dir * c * px, 0.008, px * 0.46, px * 0.46);
      }
    }
  }

  /// A hard-edged box (12 triangles), for small details.
  void simpleBox(double cx, double cy, double cz, double hx, double hy, double hz) {
    void face(List<List<double>> pts, double nx, double ny, double nz) {
      final ids = [for (final p in pts) _v(cx + p[0] * hx, cy + p[1] * hy, cz + p[2] * hz, nx, ny, nz)];
      _tri(ids[0], ids[1], ids[2]);
      _tri(ids[0], ids[2], ids[3]);
    }

    face([[-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1]], 0, 0, 1);
    face([[1, -1, -1], [-1, -1, -1], [-1, 1, -1], [1, 1, -1]], 0, 0, -1);
    face([[1, -1, 1], [1, -1, -1], [1, 1, -1], [1, 1, 1]], 1, 0, 0);
    face([[-1, -1, -1], [-1, -1, 1], [-1, 1, 1], [-1, 1, -1]], -1, 0, 0);
    face([[-1, 1, 1], [1, 1, 1], [1, 1, -1], [-1, 1, -1]], 0, 1, 0);
    face([[-1, -1, -1], [1, -1, -1], [1, -1, 1], [-1, -1, 1]], 0, -1, 0);
  }

  /// A box with rounded edges: flat faces joined by a bevel with smooth
  /// normals, so light rolls over the corners. [bevel] is how many steps the
  /// rounding is cut into (1 is a single chamfer-like step). Outer-edge
  /// vertices carry wear, which the renderer turns into worn paint.
  void roundedBox(double cx, double cy, double cz, double hx, double hy, double hz, double r, {int bevel = 1}) {
    final h = [hx, hy, hz];
    final rr = math.min(r, math.min(hx, math.min(hy, hz)) * 0.95);
    for (var axis = 0; axis < 3; axis++) {
      for (final sign in const [-1.0, 1.0]) {
        final a = (axis + 1) % 3, b = (axis + 2) % 3;
        final ka = (h[a] - rr) / h[a], kb = (h[b] - rr) / h[b];
        List<double> steps(double k) => [
              for (var i = bevel; i >= 0; i--) -(k + (1 - k) * i / bevel),
              for (var i = 0; i <= bevel; i++) k + (1 - k) * i / bevel,
            ];
        final qa = steps(ka), qb = steps(kb);
        final g = qa.length;
        final grid = List.filled(g * g, 0);
        for (var i = 0; i < g; i++) {
          for (var j = 0; j < g; j++) {
            final q = [0.0, 0.0, 0.0];
            q[axis] = sign;
            q[a] = qa[i];
            q[b] = qb[j];
            final p = [q[0] * hx, q[1] * hy, q[2] * hz];
            final inner = [
              p[0].clamp(-(hx - rr), hx - rr).toDouble(),
              p[1].clamp(-(hy - rr), hy - rr).toDouble(),
              p[2].clamp(-(hz - rr), hz - rr).toDouble(),
            ];
            final d = [p[0] - inner[0], p[1] - inner[1], p[2] - inner[2]];
            final len = math.sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
            final n = [d[0] / len, d[1] / len, d[2] / len];
            // Worn where the face turns the corner: the outer rings.
            final edge = (i == 0 || i == g - 1 ? 1.0 : 0.0) + (j == 0 || j == g - 1 ? 1.0 : 0.0);
            grid[i * g + j] = _v(
              cx + inner[0] + n[0] * rr,
              cy + inner[1] + n[1] * rr,
              cz + inner[2] + n[2] * rr,
              n[0],
              n[1],
              n[2],
              edge > 0 ? math.min(1.0, 0.55 + 0.25 * edge) : 0,
            );
          }
        }
        for (var i = 0; i < g - 1; i++) {
          for (var j = 0; j < g - 1; j++) {
            final v00 = grid[i * g + j], v01 = grid[i * g + j + 1];
            final v10 = grid[(i + 1) * g + j], v11 = grid[(i + 1) * g + j + 1];
            _tri(v00, v10, v11);
            _tri(v00, v11, v01);
          }
        }
      }
    }
  }

  /// A hemisphere (equator at y = cy) squashed to [squash] of its radius.
  void dome(double cx, double cy, double cz, double radius, double squash, int seg, int rings) {
    final grid = <List<int>>[];
    for (var i = 0; i <= rings; i++) {
      final phi = (math.pi / 2) * i / rings;
      final ring = <int>[];
      for (var j = 0; j <= seg; j++) {
        final th = 2 * math.pi * j / seg;
        final nx = math.cos(phi) * math.cos(th), ny = math.sin(phi), nz = math.cos(phi) * math.sin(th);
        ring.add(_v(cx + nx * radius, cy + ny * radius * squash, cz + nz * radius, nx, ny, nz));
      }
      grid.add(ring);
    }
    for (var i = 0; i < rings; i++) {
      for (var j = 0; j < seg; j++) {
        _tri(grid[i][j], grid[i + 1][j], grid[i + 1][j + 1]);
        _tri(grid[i][j], grid[i + 1][j + 1], grid[i][j + 1]);
      }
    }
    // Flat underside so the helmet is closed when the head tips back.
    final c = _v(cx, cy, cz, 0, -1, 0);
    final rim = [
      for (var j = 0; j <= seg; j++)
        _v(cx + math.cos(2 * math.pi * j / seg) * radius, cy, cz + math.sin(2 * math.pi * j / seg) * radius, 0, -1, 0),
    ];
    for (var j = 0; j < seg; j++) {
      _tri(c, rim[j], rim[j + 1]);
    }
  }

  void sphere(double cx, double cy, double cz, double radius, int seg, int rings) {
    final grid = <List<int>>[];
    for (var i = 0; i <= rings * 2; i++) {
      final phi = -math.pi / 2 + math.pi * i / (rings * 2);
      final ring = <int>[];
      for (var j = 0; j <= seg; j++) {
        final th = 2 * math.pi * j / seg;
        final nx = math.cos(phi) * math.cos(th), ny = math.sin(phi), nz = math.cos(phi) * math.sin(th);
        ring.add(_v(cx + nx * radius, cy + ny * radius, cz + nz * radius, nx, ny, nz));
      }
      grid.add(ring);
    }
    for (var i = 0; i < rings * 2; i++) {
      for (var j = 0; j < seg; j++) {
        _tri(grid[i][j], grid[i + 1][j], grid[i + 1][j + 1]);
        _tri(grid[i][j], grid[i + 1][j + 1], grid[i][j + 1]);
      }
    }
  }

  /// A full ellipsoid with radii [rx], [ry], [rz]: the rounded head.
  void ellipsoid(double cx, double cy, double cz, double rx, double ry, double rz, int seg, int rings) {
    final grid = <List<int>>[];
    for (var i = 0; i <= rings; i++) {
      final phi = -math.pi / 2 + math.pi * i / rings;
      final ring = <int>[];
      for (var j = 0; j <= seg; j++) {
        final th = 2 * math.pi * j / seg;
        final ux = math.cos(phi) * math.cos(th), uy = math.sin(phi), uz = math.cos(phi) * math.sin(th);
        // The normal of an ellipsoid follows the gradient x/rx^2, y/ry^2, z/rz^2.
        var nx = ux / rx, ny = uy / ry, nz = uz / rz;
        final len = math.sqrt(nx * nx + ny * ny + nz * nz);
        nx /= len;
        ny /= len;
        nz /= len;
        ring.add(_v(cx + ux * rx, cy + uy * ry, cz + uz * rz, nx, ny, nz));
      }
      grid.add(ring);
    }
    for (var i = 0; i < rings; i++) {
      for (var j = 0; j < seg; j++) {
        _tri(grid[i][j], grid[i + 1][j], grid[i + 1][j + 1]);
        _tri(grid[i][j], grid[i + 1][j + 1], grid[i][j + 1]);
      }
    }
  }

  /// A flat disc facing +z.
  void disc(double cx, double cy, double z, double r, int seg) {
    final c = _v(cx, cy, z, 0, 0, 1);
    final ring = [for (var j = 0; j < seg; j++) _v(cx + r * math.cos(2 * math.pi * j / seg), cy + r * math.sin(2 * math.pi * j / seg), z, 0, 0, 1)];
    for (var j = 0; j < seg; j++) {
      _tri(c, ring[j], ring[(j + 1) % seg]);
    }
  }

  /// A ring facing +z (the lens's rim), around the z axis.
  void torusZ(double cx, double cy, double cz, double major, double minor, int seg, int tube) {
    final grid = <List<int>>[];
    for (var i = 0; i <= seg; i++) {
      final u = 2 * math.pi * i / seg;
      final ring = <int>[];
      for (var j = 0; j <= tube; j++) {
        final v = 2 * math.pi * j / tube;
        final r = major + minor * math.cos(v);
        ring.add(_v(
          cx + r * math.cos(u),
          cy + r * math.sin(u),
          cz + minor * math.sin(v),
          math.cos(v) * math.cos(u),
          math.cos(v) * math.sin(u),
          math.sin(v),
        ));
      }
      grid.add(ring);
    }
    for (var i = 0; i < seg; i++) {
      for (var j = 0; j < tube; j++) {
        _tri(grid[i][j], grid[i + 1][j], grid[i + 1][j + 1]);
        _tri(grid[i][j], grid[i + 1][j + 1], grid[i][j + 1]);
      }
    }
  }

  /// A ring around the y axis (the helmet's orange rim).
  void torus(double cx, double cy, double cz, double major, double minor, int seg, int tube) {
    final grid = <List<int>>[];
    for (var i = 0; i <= seg; i++) {
      final u = 2 * math.pi * i / seg;
      final ring = <int>[];
      for (var j = 0; j <= tube; j++) {
        final v = 2 * math.pi * j / tube;
        final r = major + minor * math.cos(v);
        ring.add(_v(
          cx + r * math.cos(u),
          cy + minor * math.sin(v),
          cz + r * math.sin(u),
          math.cos(v) * math.cos(u),
          math.sin(v),
          math.cos(v) * math.sin(u),
        ));
      }
      grid.add(ring);
    }
    for (var i = 0; i < seg; i++) {
      for (var j = 0; j < tube; j++) {
        _tri(grid[i][j], grid[i + 1][j], grid[i + 1][j + 1]);
        _tri(grid[i][j], grid[i + 1][j + 1], grid[i][j + 1]);
      }
    }
  }

  /// A ring around the x axis (a cable loop).
  void torusX(double cx, double cy, double cz, double major, double minor, int seg, int tube) {
    final grid = <List<int>>[];
    for (var i = 0; i <= seg; i++) {
      final u = 2 * math.pi * i / seg;
      final ring = <int>[];
      for (var j = 0; j <= tube; j++) {
        final v = 2 * math.pi * j / tube;
        final r = major + minor * math.cos(v);
        ring.add(_v(
          cx + minor * math.sin(v),
          cy + r * math.cos(u),
          cz + r * math.sin(u),
          math.sin(v),
          math.cos(v) * math.cos(u),
          math.cos(v) * math.sin(u),
        ));
      }
      grid.add(ring);
    }
    for (var i = 0; i < seg; i++) {
      for (var j = 0; j < tube; j++) {
        _tri(grid[i][j], grid[i + 1][j], grid[i + 1][j + 1]);
        _tri(grid[i][j], grid[i + 1][j + 1], grid[i][j + 1]);
      }
    }
  }

  /// A cylinder along y, from [y0] to [y1].
  void cylinder(double cx, double cz, double radius, double y0, double y1, int seg, {bool caps = false}) {
    final lo = <int>[], hi = <int>[];
    for (var j = 0; j <= seg; j++) {
      final th = 2 * math.pi * j / seg;
      final nx = math.cos(th), nz = math.sin(th);
      lo.add(_v(cx + nx * radius, y0, cz + nz * radius, nx, 0, nz));
      hi.add(_v(cx + nx * radius, y1, cz + nz * radius, nx, 0, nz));
    }
    for (var j = 0; j < seg; j++) {
      _tri(lo[j], hi[j], hi[j + 1]);
      _tri(lo[j], hi[j + 1], lo[j + 1]);
    }
    if (caps) {
      for (final top in const [false, true]) {
        final y = top ? y1 : y0, ny = top ? 1.0 : -1.0;
        final c = _v(cx, y, cz, 0, ny, 0);
        final ring = [
          for (var j = 0; j <= seg; j++)
            _v(cx + math.cos(2 * math.pi * j / seg) * radius, y, cz + math.sin(2 * math.pi * j / seg) * radius, 0, ny, 0),
        ];
        for (var j = 0; j < seg; j++) {
          _tri(c, ring[j], ring[j + 1]);
        }
      }
    }
  }

  /// A capped cylinder along x with total [length], centred at (cx, cy, cz).
  void cylinderX(double cx, double cy, double cz, double radius, double length, int seg) {
    final h = length / 2;
    final a = <int>[], b = <int>[];
    for (var j = 0; j <= seg; j++) {
      final th = 2 * math.pi * j / seg;
      final ny = math.cos(th), nz = math.sin(th);
      a.add(_v(cx - h, cy + ny * radius, cz + nz * radius, 0, ny, nz));
      b.add(_v(cx + h, cy + ny * radius, cz + nz * radius, 0, ny, nz));
    }
    for (var j = 0; j < seg; j++) {
      _tri(a[j], b[j], b[j + 1]);
      _tri(a[j], b[j + 1], a[j + 1]);
    }
    for (final right in const [false, true]) {
      final x = right ? cx + h : cx - h, nx = right ? 1.0 : -1.0;
      final c = _v(x, cy, cz, nx, 0, 0);
      final ring = [
        for (var j = 0; j <= seg; j++)
          _v(x, cy + math.cos(2 * math.pi * j / seg) * radius, cz + math.sin(2 * math.pi * j / seg) * radius, nx, 0, 0),
      ];
      for (var j = 0; j < seg; j++) {
        _tri(c, ring[j], ring[j + 1]);
      }
    }
  }

  /// Texture-coordinate scale per slot: brushed metal is stretched into
  /// streaks, rubber is coarser, glowing parts are soft.
  (double, double) _uvScale(int slot) => switch (slot) {
        sMetal || sSeam => (1.0, 0.1),
        sNeck || sShin || sSole || sVent => (0.55, 0.55),
        sFace || sLed || sScreen || sGlint || sIris || sPupil || sGlintW => (0.12, 0.12),
        _ => (1.0, 1.0),
      };

  MicroduckMesh pack() {
    final tris = Uint16List.fromList(_tris);
    final lodMin = Uint8List.fromList(_lodMin), lodMax = Uint8List.fromList(_lodMax);
    final n = tris.length ~/ 3;
    final triMin = Uint8List(n), triMax = Uint8List(n);
    final triBias = Float32List(n);
    for (var i = 0; i < n; i++) {
      final v = tris[i * 3];
      triMin[i] = lodMin[v];
      triMax[i] = lodMax[v];
      // Decals sit a hair in front of the surface they are on; nudge their
      // depth so the sort never buries them in it.
      final sl = _slot[v];
      triBias[i] = _bias[v] >= 0
          ? _bias[v]
          : sl == sFace
              ? 14.0
              : sl == sScreen
                  ? 12.0
                  : (lodMin[v] >= 1 || sl == sSeam || sl == sMetal)
                      ? 3.0
                      : 0;
    }
    // Texture coordinates: triplanar from the face's dominant axis, 64 per
    // robot unit. The side faces map v to world height, so the 3D-print layer
    // lines in the texture run level, as on a real print.
    final uv = Float32List(_px.length * 2);
    for (var i = 0; i < _px.length; i++) {
      final ax = _nx[i].abs(), ay = _ny[i].abs(), az = _nz[i].abs();
      const k = 64.0;
      final shift = _slot[i] * 23.0 + _matrix[i] * 11.0; // different parts, different grain
      double u, v;
      if (ay >= ax && ay >= az) {
        u = _px[i] * k + shift;
        v = _pz[i] * k;
      } else if (az >= ax) {
        u = _px[i] * k + shift;
        v = _py[i] * k;
      } else {
        u = _pz[i] * k + shift;
        v = _py[i] * k;
      }
      final s = _uvScale(_slot[i]);
      uv[i * 2] = u * s.$1;
      uv[i * 2 + 1] = v * s.$2;
    }
    final mesh = MicroduckMesh.raw(
      Float32List.fromList(_px),
      Float32List.fromList(_py),
      Float32List.fromList(_pz),
      Float32List.fromList(_nx),
      Float32List.fromList(_ny),
      Float32List.fromList(_nz),
      Float32List.fromList(_ao),
      Float32List.fromList(_wear),
      Uint8List.fromList(_matrix),
      Uint8List.fromList(_slot),
      Uint8List.fromList(_dyn),
      lodMin,
      lodMax,
      tris,
      triMin,
      triMax,
      triBias,
      uv,
    );
    mesh.dynCx.setAll(0, _dcx);
    mesh.dynCy.setAll(0, _dcy);
    return mesh;
  }
}
