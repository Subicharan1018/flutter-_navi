import 'dart:math' as math;
import 'dart:typed_data';

/// Which colours the robot wears. White is the toy from the reference photo
/// (white helmet, orange rim and feet); grey is its dark sibling with a green
/// LED.
enum MicroduckSkin {
  white,
  grey;

  String get label => switch (this) { white => 'White', grey => 'Grey' };

  /// 0xRRGGBB per colour slot ([sTorso] ...).
  List<int> get colors => switch (this) {
        white => _white,
        grey => _grey,
      };

  static const List<int> _white = [
    0xEFEFEA, // torso
    0x14161A, // screen
    0x17181B, // neck
    0xF5F5F1, // helmet
    0xE8721C, // rim
    0xFF9A3C, // led
    0xEAEAE5, // thigh
    0x2A2B30, // shin
    0xE8721C, // foot
    0x2B2C31, // seam
    0x26272B, // vent
    0xB9BBC0, // metal
    0x18191C, // sole
    0x8FE8FF, // face
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
    0x1D1E22,
    0x17181B,
    0x8E9096,
    0x141517,
    0x3DDC6A,
  ];
}

/// Colour slots. A vertex's slot picks its colour from the skin.
const int sTorso = 0, sScreen = 1, sNeck = 2, sHelmet = 3, sRim = 4, sLed = 5, sThigh = 6;
const int sShin = 7, sFoot = 8, sSeam = 9, sVent = 10, sMetal = 11, sSole = 12, sFace = 13;
const int kSlotCount = 14;

/// Slots that glow rather than catch light.
bool slotEmissive(int s) => s == sLed || s == sFace;

/// Slots with a glossy highlight.
bool slotShiny(int s) => s == sHelmet || s == sRim || s == sMetal || s == sSeam;

/// Matrix ids: which joint moves a vertex.
const int mPelvis = 0, mNeck = 1, mHead = 2, mHipL = 3, mKneeL = 4, mAnkleL = 5;
const int mHipR = 6, mKneeR = 7, mAnkleR = 8;
const int kMatrixCount = 9;

/// Dynamic face pieces on the screen: the renderer scales/offsets them each
/// frame (eyes blinking, bars dancing, a heart).
const int dEyeL = 1, dEyeR = 2, dBar0 = 3, dBarCount = 5, dHeart = 8;
const int kDynCount = 9;

/// Body proportions, in robot units (feet at y 0).
const double kThigh = 0.66, kShin = 0.8, kAnkleH = 0.3, kHipY = 1.76, kHipX = 0.6;
const double kNeckY = 1.15, kHeadY = 0.4;

/// The robot as one triangle soup. Every part's vertices are relative to its
/// own joint, so posing is "transform each part by its joint matrix".
///
/// Built once. Triangles tagged `lod == 1` are fine detail (bolts, screws,
/// vents, servo caps) that the renderer skips for small robots.
class MicroduckMesh {
  final Float32List px, py, pz, nx, ny, nz, ao;
  final Uint8List matrix, slot, dyn, lod;
  final Uint16List tris;
  final Uint8List triLod;
  final Float32List triBias;

  /// Texture coordinates in texels, two per vertex.
  final Float32List uv;

  /// Centre (x, y) of each dynamic piece, for scaling about itself.
  final Float32List dynCx = Float32List(kDynCount), dynCy = Float32List(kDynCount);

  int get vertexCount => px.length;
  int get triCount => tris.length ~/ 3;

  MicroduckMesh._(
    this.px,
    this.py,
    this.pz,
    this.nx,
    this.ny,
    this.nz,
    this.ao,
    this.matrix,
    this.slot,
    this.dyn,
    this.lod,
    this.tris,
    this.triLod,
    this.triBias,
    this.uv,
  );

  static final MicroduckMesh instance = _build();

  static MicroduckMesh _build() {
    final b = _Builder();

    // ---- Torso (relative to the pelvis joint at hip height) ----
    b
      ..use(mPelvis, sTorso)
      ..ao = ((x, y, z) => 1 - 0.34 * _s((y - 0.95) / 0.2) - 0.16 * _s((0.25 - y) / 0.2))
      ..roundedBox(0, 0.62, 0, 0.42, 0.55, 0.36, 0.13)
      ..ao = null;
    // Screen bezel and glass.
    b
      ..use(mPelvis, sMetal)
      ..simpleBox(0, 0.64 + 0.31, 0.375, 0.255, 0.02, 0.03)
      ..simpleBox(0, 0.64 - 0.31, 0.375, 0.255, 0.02, 0.03)
      ..simpleBox(-0.235, 0.64, 0.375, 0.02, 0.29, 0.03)
      ..simpleBox(0.235, 0.64, 0.375, 0.02, 0.29, 0.03)
      ..use(mPelvis, sScreen)
      ..quad(0, 0.64, 0.375, 0.215, 0.29);
    // Face pieces on the glass: eyes, and equaliser bars that share the spot.
    for (final side in const [-1, 1]) {
      b
        ..use(mPelvis, sFace, dyn: side < 0 ? dEyeL : dEyeR, cx: side * 0.105, cy: 0.7)
        ..quad(side * 0.105, 0.7, 0.392, 0.045, 0.075);
    }
    for (var i = 0; i < dBarCount; i++) {
      const bottom = 0.5;
      final x = (i - 2) * 0.075;
      b
        ..use(mPelvis, sFace, dyn: dBar0 + i, cx: x, cy: bottom)
        ..quadFrom(x, bottom, 0.392, 0.026, 0.3);
    }
    // A heart for "liked": a diamond and two lobes.
    b
      ..use(mPelvis, sFace, dyn: dHeart, cx: 0, cy: 0.64)
      ..heart(0, 0.64, 0.392, 0.16);
    // Panel lines, screws and a vent strip on the torso.
    b
      ..use(mPelvis, sSeam, lod: 1)
      ..simpleBox(-0.425, 0.62, 0.02, 0.012, 0.38, 0.012)
      ..simpleBox(0.425, 0.62, 0.02, 0.012, 0.38, 0.012)
      ..simpleBox(-0.425, 0.3, 0.16, 0.012, 0.012, 0.16)
      ..simpleBox(0.425, 0.3, 0.16, 0.012, 0.012, 0.16)
      ..use(mPelvis, sMetal, lod: 1);
    for (final sx in const [-1.0, 1.0]) {
      for (final y in const [0.28, 0.96]) {
        b.sphere(sx * 0.43, y, 0.18, 0.032, 5, 2);
      }
    }
    b
      ..use(mPelvis, sVent, lod: 1)
      ..simpleBox(0, 0.17, 0.362, 0.17, 0.012, 0.01)
      ..simpleBox(0, 0.1, 0.362, 0.17, 0.012, 0.01);

    // ---- Neck (relative to the neck joint): rod and joint collars ----
    b
      ..use(mNeck, sNeck)
      ..cylinder(0, 0, 0.07, 0.0, 0.5, 8)
      ..use(mNeck, sMetal)
      ..cylinder(0, 0, 0.16, 0.0, 0.09, 12, caps: true)
      ..cylinder(0, 0, 0.14, 0.33, 0.4, 12, caps: true);

    // ---- Head (relative to the head joint; helmet equator at y 0) ----
    b
      ..use(mHead, sHelmet)
      ..ao = ((x, y, z) => 1 - 0.18 * _s((0.1 - y) / 0.2))
      ..dome(0, 0.02, 0, 0.85, 0.9, 16, 5)
      ..ao = null
      ..use(mHead, sRim)
      ..torus(0, -0.03, 0, 0.93, 0.09, 16, 5)
      ..use(mHead, sSeam)
      ..cylinder(0, 0, 0.815, 0.25, 0.31, 16)
      ..use(mHead, sLed)
      ..sphere(0.6, 0.44, 0.42, 0.095, 6, 3);
    // Vent slits and bolts on both sides of the helmet.
    for (final sx in const [-1.0, 1.0]) {
      b.use(mHead, sVent, lod: 1);
      for (final z in const [-0.22, -0.1, 0.02]) {
        b.simpleBox(sx * 0.775, 0.2, z, 0.03, 0.075, 0.025);
      }
      b
        ..use(mHead, sMetal, lod: 1)
        ..sphere(sx * 0.84, -0.03, 0.4, 0.06, 5, 2)
        ..sphere(sx * 0.84, -0.03, -0.4, 0.06, 5, 2);
    }

    // ---- Legs (relative to hip / knee / ankle joints) ----
    for (final m in const [mHipL, mHipR]) {
      final hip = m, knee = m + 1, ankle = m + 2;
      final inward = m == mHipL ? 1.0 : -1.0; // +x side of a left leg faces the body
      b
        ..use(hip, sThigh)
        ..ao = ((x, y, z) => 1 - 0.3 * _s((x * inward) / 0.25) - 0.1 * _s((-y - 0.55) / 0.15))
        ..roundedBox(0, -0.3, 0, 0.34, 0.38, 0.38, 0.11)
        ..ao = null
        ..use(hip, sMetal)
        ..cylinderX(0, 0, 0, 0.17, 0.42, 12)
        ..use(knee, sShin)
        ..roundedBox(0, -0.4, 0, 0.2, 0.4, 0.24, 0.08)
        ..use(knee, sMetal)
        ..cylinderX(0, 0, 0, 0.14, 0.27, 12)
        ..use(knee, sSole, lod: 1)
        ..cylinder(0, -0.2, 0.035, -0.7, -0.05, 6)
        ..use(ankle, sFoot)
        ..ao = ((x, y, z) => 0.8 + 0.2 * _s((y + 0.28) / 0.2))
        ..roundedBox(0, -0.15, 0.14, 0.28, 0.15, 0.46, 0.1)
        ..ao = null
        ..use(ankle, sMetal)
        ..cylinderX(0, 0, 0, 0.11, 0.3, 10)
        ..use(ankle, sSole)
        ..roundedBox(0, -0.285, 0.14, 0.3, 0.03, 0.5, 0.02)
        ..use(ankle, sFoot)
        ..roundedBox(0, -0.2, -0.3, 0.2, 0.1, 0.1, 0.05)
        ..use(ankle, sFoot, lod: 1)
        ..roundedBox(0, -0.1, 0.56, 0.22, 0.1, 0.03, 0.03);
    }
    return b.pack();
  }

  static double _s(double x) {
    final c = x.clamp(0.0, 1.0);
    return c * c * (3 - 2 * c);
  }
}

class _Builder {
  final List<double> _px = [], _py = [], _pz = [], _nx = [], _ny = [], _nz = [], _ao = [];
  final List<int> _matrix = [], _slot = [], _dyn = [], _lod = [];
  final List<int> _tris = [];
  final Float32List _dcx = Float32List(kDynCount), _dcy = Float32List(kDynCount);

  int _m = 0, _sl = 0, _d = 0, _l = 0;
  double Function(double, double, double)? ao;

  void use(int m, int slot, {int lod = 0, int dyn = 0, double cx = 0, double cy = 0}) {
    _m = m;
    _sl = slot;
    _l = lod;
    _d = dyn;
    if (dyn > 0) {
      _dcx[dyn] = cx;
      _dcy[dyn] = cy;
    }
  }

  int _v(double x, double y, double z, double nx, double ny, double nz) {
    _px.add(x);
    _py.add(y);
    _pz.add(z);
    _nx.add(nx);
    _ny.add(ny);
    _nz.add(nz);
    _ao.add(ao?.call(x, y, z) ?? 1);
    _matrix.add(_m);
    _slot.add(_sl);
    _dyn.add(_d);
    _lod.add(_l);
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

  /// A heart from a diamond and two lobes, facing +z.
  void heart(double cx, double cy, double z, double s) {
    // The classic parametric heart, as a fan around its middle.
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

  /// A box with rounded edges: flat faces joined by a one-step bevel with
  /// smooth normals, so light rolls over the corners.
  void roundedBox(double cx, double cy, double cz, double hx, double hy, double hz, double r) {
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

  MicroduckMesh pack() {
    final tris = Uint16List.fromList(_tris);
    final lod = Uint8List.fromList(_lod);
    final triLod = Uint8List(tris.length ~/ 3);
    final triBias = Float32List(triLod.length);
    for (var i = 0; i < triLod.length; i++) {
      final v = tris[i * 3];
      triLod[i] = lod[v];
      // Decals sit a hair in front of the surface they are on; nudge their
      // depth so the sort never buries them in it.
      final sl = _slot[v];
      triBias[i] = sl == sFace
          ? 4.5
          : (lod[v] == 1 || sl == sScreen || sl == sSeam || sl == sMetal)
              ? 3.0
              : 0;
    }
    // Texture coordinates: triplanar, from the face's dominant axis, 36 per
    // robot unit (the renderer scales them to the size on screen).
    final uv = Float32List(_px.length * 2);
    for (var i = 0; i < _px.length; i++) {
      final ax = _nx[i].abs(), ay = _ny[i].abs(), az = _nz[i].abs();
      const k = 36.0; // texels per robot unit
      final shift = _slot[i] * 23.0 + _matrix[i] * 11.0; // different parts, different grain
      if (ay >= ax && ay >= az) {
        uv[i * 2] = _px[i] * k + shift;
        uv[i * 2 + 1] = _pz[i] * k;
      } else if (az >= ax) {
        uv[i * 2] = _px[i] * k + shift;
        uv[i * 2 + 1] = _py[i] * k;
      } else {
        uv[i * 2] = _pz[i] * k + shift;
        uv[i * 2 + 1] = _py[i] * k;
      }
    }
    final mesh = MicroduckMesh._(
      Float32List.fromList(_px),
      Float32List.fromList(_py),
      Float32List.fromList(_pz),
      Float32List.fromList(_nx),
      Float32List.fromList(_ny),
      Float32List.fromList(_nz),
      Float32List.fromList(_ao),
      Uint8List.fromList(_matrix),
      Uint8List.fromList(_slot),
      Uint8List.fromList(_dyn),
      lod,
      tris,
      triLod,
      triBias,
      uv,
    );
    mesh.dynCx.setAll(0, _dcx);
    mesh.dynCy.setAll(0, _dcy);
    return mesh;
  }
}
