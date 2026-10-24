import 'dart:math' as math;
import 'dart:typed_data';

/// Which colours the robot wears. White is the toy from the reference photo
/// (white helmet, orange rim and feet); grey is its dark sibling with a green
/// LED.
enum MicroduckSkin {
  white,
  grey;

  String get label => switch (this) { white => 'White', grey => 'Grey' };

  /// ARGB-less 0xRRGGBB per [MicroduckPart] index.
  List<int> get colors => switch (this) {
        white => _white,
        grey => _grey,
      };

  /// LED colour (0xRRGGBB); the white robot's glows a soft orange.
  int get led => this == white ? 0xFF9A3C : 0x3DDC6A;

  static const List<int> _white = [
    0xEFEFEA, // torso
    0x1B1D21, // screen
    0x16171A, // neck
    0xF5F5F1, // helmet
    0xE8721C, // rim
    0xFF9A3C, // led
    0xE9E9E4, // thigh
    0x2A2B30, // shin
    0xE8721C, // foot
  ];

  static const List<int> _grey = [
    0x4A4C52,
    0x15171A,
    0x141517,
    0x5C5E64,
    0xE8721C,
    0x3DDC6A,
    0x44464B,
    0x2A2B30,
    0xE8721C,
  ];
}

/// Indices into [MicroduckSkin.colors]; the legs share three entries, so a
/// mesh part id maps through [kPartColor].
const int kTorso = 0, kScreen = 1, kNeck = 2, kHelmet = 3, kRim = 4, kLed = 5;
const int kThighL = 6, kShinL = 7, kFootL = 8, kThighR = 9, kShinR = 10, kFootR = 11;
const int kPartCount = 12;

/// Mesh part id -> skin colour slot.
const List<int> kPartColor = [0, 1, 2, 3, 4, 5, 6, 7, 8, 6, 7, 8];

/// Body proportions, in robot units (feet at y 0).
const double kThigh = 0.66, kShin = 0.8, kAnkleH = 0.3, kHipY = 1.76, kHipX = 0.6;
const double kNeckY = 1.15, kHeadY = 0.34;

/// The robot as one triangle soup. Every part's vertices are relative to its
/// own joint, so posing is "transform each part by its joint matrix".
///
/// Built once; about a thousand triangles, which is nothing for a CPU
/// transform and `Canvas.drawVertices`.
class MicroduckMesh {
  final Float32List px, py, pz, nx, ny, nz;
  final Uint8List part;
  final Uint16List tris;

  int get vertexCount => px.length;
  int get triCount => tris.length ~/ 3;

  MicroduckMesh._(this.px, this.py, this.pz, this.nx, this.ny, this.nz, this.part, this.tris);

  static final MicroduckMesh instance = _build();

  static MicroduckMesh _build() {
    final b = _Builder();
    // Torso, relative to the pelvis joint at hip height.
    b.roundedBox(kTorso, 0, 0.62, 0, 0.42, 0.55, 0.36, 0.13);
    b.roundedBox(kScreen, 0, 0.62, 0.37, 0.2, 0.34, 0.03, 0.02);
    // Neck, relative to the neck joint.
    b.cylinder(kNeck, 0, 0, 0.12, 0, 0.42, 8);
    // Head, relative to the head joint (helmet equator at y 0).
    b.dome(kHelmet, 0, 0.02, 0, 0.85, 0.9, 16, 5);
    b.cylinder(kRim, 0, 0, 0.9, -0.14, 0.04, 16, bottomCap: true);
    b.sphere(kLed, 0.6, 0.38, 0.42, 0.1, 6, 3);
    // Legs, relative to hip / knee / ankle joints.
    for (final base in const [kThighL, kThighR]) {
      b.roundedBox(base, 0, -0.3, 0, 0.3, 0.38, 0.34, 0.1);
      b.roundedBox(base + 1, 0, -0.38, 0, 0.2, 0.42, 0.24, 0.08);
      b.roundedBox(base + 2, 0, -0.15, 0.14, 0.28, 0.15, 0.46, 0.1);
    }
    return b.pack();
  }
}

class _Builder {
  final List<double> _px = [], _py = [], _pz = [], _nx = [], _ny = [], _nz = [];
  final List<int> _part = [];
  final List<int> _tris = [];

  int _v(int part, double x, double y, double z, double nx, double ny, double nz) {
    _px.add(x);
    _py.add(y);
    _pz.add(z);
    _nx.add(nx);
    _ny.add(ny);
    _nz.add(nz);
    _part.add(part);
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

  /// A box with rounded edges: flat faces joined by a one-step bevel with
  /// smooth normals, so light rolls over the corners.
  void roundedBox(int part, double cx, double cy, double cz, double hx, double hy, double hz, double r) {
    final h = [hx, hy, hz];
    final rr = math.min(r, math.min(hx, math.min(hy, hz)) * 0.95);
    for (var axis = 0; axis < 3; axis++) {
      for (final sign in const [-1.0, 1.0]) {
        final a = (axis + 1) % 3, b = (axis + 2) % 3;
        final ka = (h[a] - rr) / h[a], kb = (h[b] - rr) / h[b];
        final qa = [-1.0, -ka, ka, 1.0], qb = [-1.0, -kb, kb, 1.0];
        final grid = List.filled(16, 0);
        for (var i = 0; i < 4; i++) {
          for (var j = 0; j < 4; j++) {
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
            grid[i * 4 + j] = _v(
              part,
              cx + inner[0] + n[0] * rr,
              cy + inner[1] + n[1] * rr,
              cz + inner[2] + n[2] * rr,
              n[0],
              n[1],
              n[2],
            );
          }
        }
        for (var i = 0; i < 3; i++) {
          for (var j = 0; j < 3; j++) {
            final v00 = grid[i * 4 + j], v01 = grid[i * 4 + j + 1];
            final v10 = grid[(i + 1) * 4 + j], v11 = grid[(i + 1) * 4 + j + 1];
            _tri(v00, v10, v11);
            _tri(v00, v11, v01);
          }
        }
      }
    }
  }

  /// A hemisphere (equator at y = cy) squashed to [squash] of its radius.
  void dome(int part, double cx, double cy, double cz, double radius, double squash, int seg, int rings) {
    final grid = <List<int>>[];
    for (var i = 0; i <= rings; i++) {
      final phi = (math.pi / 2) * i / rings;
      final ring = <int>[];
      for (var j = 0; j <= seg; j++) {
        final th = 2 * math.pi * j / seg;
        final nx = math.cos(phi) * math.cos(th), ny = math.sin(phi), nz = math.cos(phi) * math.sin(th);
        ring.add(_v(part, cx + nx * radius, cy + ny * radius * squash, cz + nz * radius, nx, ny, nz));
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
    final c = _v(part, cx, cy, cz, 0, -1, 0);
    final rim = [for (var j = 0; j <= seg; j++) _v(part, cx + math.cos(2 * math.pi * j / seg) * radius, cy, cz + math.sin(2 * math.pi * j / seg) * radius, 0, -1, 0)];
    for (var j = 0; j < seg; j++) {
      _tri(c, rim[j], rim[j + 1]);
    }
  }

  void sphere(int part, double cx, double cy, double cz, double radius, int seg, int rings) {
    final grid = <List<int>>[];
    for (var i = 0; i <= rings * 2; i++) {
      final phi = -math.pi / 2 + math.pi * i / (rings * 2);
      final ring = <int>[];
      for (var j = 0; j <= seg; j++) {
        final th = 2 * math.pi * j / seg;
        final nx = math.cos(phi) * math.cos(th), ny = math.sin(phi), nz = math.cos(phi) * math.sin(th);
        ring.add(_v(part, cx + nx * radius, cy + ny * radius, cz + nz * radius, nx, ny, nz));
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

  void cylinder(int part, double cx, double cz0, double radius, double y0, double y1, int seg, {bool bottomCap = false}) {
    final lo = <int>[], hi = <int>[];
    for (var j = 0; j <= seg; j++) {
      final th = 2 * math.pi * j / seg;
      final nx = math.cos(th), nz = math.sin(th);
      lo.add(_v(part, cx + nx * radius, y0, cz0 + nz * radius, nx, 0, nz));
      hi.add(_v(part, cx + nx * radius, y1, cz0 + nz * radius, nx, 0, nz));
    }
    for (var j = 0; j < seg; j++) {
      _tri(lo[j], hi[j], hi[j + 1]);
      _tri(lo[j], hi[j + 1], lo[j + 1]);
    }
    if (bottomCap) {
      final c = _v(part, cx, y0, cz0, 0, -1, 0);
      final ring = [for (var j = 0; j <= seg; j++) _v(part, cx + math.cos(2 * math.pi * j / seg) * radius, y0, cz0 + math.sin(2 * math.pi * j / seg) * radius, 0, -1, 0)];
      for (var j = 0; j < seg; j++) {
        _tri(c, ring[j], ring[j + 1]);
      }
    }
  }

  MicroduckMesh pack() => MicroduckMesh._(
        Float32List.fromList(_px),
        Float32List.fromList(_py),
        Float32List.fromList(_pz),
        Float32List.fromList(_nx),
        Float32List.fromList(_ny),
        Float32List.fromList(_nz),
        Uint8List.fromList(_part),
        Uint16List.fromList(_tris),
      );
}
