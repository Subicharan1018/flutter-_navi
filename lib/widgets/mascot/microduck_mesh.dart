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
    0x17181B, // neck / cable rubber
    0xF5F5F1, // helmet
    0xE8721C, // rim
    0xFF9A3C, // led
    0xEAEAE5, // thigh
    0x2A2B30, // shin
    0xE8721C, // foot
    0x2B2C31, // seam
    0x26272B, // vent
    0xB9BBC0, // metal
    0x1C1D21, // sole
    0x8FE8FF, // face
    0x2E3640, // glass glint
    0xE4E0CF, // label paper
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
    0x2A343A,
    0xA9ABA8,
  ];
}

/// Colour slots. A vertex's slot picks its colour from the skin.
const int sTorso = 0, sScreen = 1, sNeck = 2, sHelmet = 3, sRim = 4, sLed = 5, sThigh = 6;
const int sShin = 7, sFoot = 8, sSeam = 9, sVent = 10, sMetal = 11, sSole = 12, sFace = 13;
const int sGlint = 14, sLabel = 15;
const int kSlotCount = 16;

/// Slots that glow rather than catch light.
bool slotEmissive(int s) => s == sLed || s == sFace;

/// How a slot's surface reflects: specular strength, specular tightness (the
/// exponent) and how much of the soft environment band it shows. Glossy
/// helmet and rim, satin body panels, brushed metal, dark rubber.
class Material {
  final double spec, power, env;
  const Material(this.spec, this.power, this.env);
}

const Material _rubber = Material(0.03, 6, 0);
const Material _satin = Material(0.1, 5, 0.04);

/// Per-slot materials.
const List<Material> kMaterials = [
  _satin, // torso
  Material(0.1, 12, 0), // screen glass (a big quad: keep its sheen gentle)
  _rubber, // neck
  Material(0.95, 48, 0.38), // helmet: sharp hotspot + environment band
  Material(0.7, 28, 0.25), // rim
  _rubber, // led
  _satin, // thigh
  _rubber, // shin
  _satin, // foot
  Material(0.45, 24, 0.12), // seam
  _rubber, // vent
  Material(0.7, 10, 0.1), // metal, brushed: broad highlight
  _rubber, // sole
  _rubber, // face
  _rubber, // glint
  _satin, // label
];

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

/// Detail levels the renderer picks from the robot's size on screen: 0 for
/// tiny (the mini player), 1 for ordinary, 2 for large (empty states, close
/// ups). A triangle shows when `lodMin <= level <= lodMax`.
int meshLevel(double size) => size >= 130 ? 2 : (size >= 48 ? 1 : 0);

/// The robot as one triangle soup. Every part's vertices are relative to its
/// own joint, so posing is "transform each part by its joint matrix".
class MicroduckMesh {
  final Float32List px, py, pz, nx, ny, nz, ao, wear;
  final Uint8List matrix, slot, dyn, lodMin, lodMax;
  final Uint16List tris;
  final Uint8List triMin, triMax;
  final Float32List triBias;

  /// Texture coordinates in texels, two per vertex.
  final Float32List uv;

  /// Centre (x, y) of each dynamic piece, for scaling about itself.
  final Float32List dynCx = Float32List(kDynCount), dynCy = Float32List(kDynCount);

  /// Where the LED sits in the head's frame, for its glow.
  static const double ledX = 0.6, ledY = 0.44, ledZ = 0.42;

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
    this.wear,
    this.matrix,
    this.slot,
    this.dyn,
    this.lodMin,
    this.lodMax,
    this.tris,
    this.triMin,
    this.triMax,
    this.triBias,
    this.uv,
  );

  static final MicroduckMesh instance = _build();

  static MicroduckMesh _build() {
    final b = _Builder();

    // ---- Torso (relative to the pelvis joint at hip height) ----
    for (final hi in const [false, true]) {
      b
        ..tier(hi)
        ..use(mPelvis, sTorso)
        ..ao = ((x, y, z) => 1 - 0.34 * _s((y - 0.95) / 0.2) - 0.16 * _s((0.25 - y) / 0.2))
        ..roundedBox(0, 0.62, 0, 0.42, 0.55, 0.36, 0.13, bevel: hi ? 3 : 1)
        ..ao = null;
    }
    b.tier(null);

    // Screen: bezel, glass, a glint, scanlines, and the face on it.
    b
      ..use(mPelvis, sMetal)
      ..simpleBox(0, 0.64 + 0.31, 0.375, 0.255, 0.02, 0.03)
      ..simpleBox(0, 0.64 - 0.31, 0.375, 0.255, 0.02, 0.03)
      ..simpleBox(-0.235, 0.64, 0.375, 0.02, 0.29, 0.03)
      ..simpleBox(0.235, 0.64, 0.375, 0.02, 0.29, 0.03)
      ..use(mPelvis, sScreen)
      ..quad(0, 0.64, 0.375, 0.215, 0.29)
      ..use(mPelvis, sGlint, lod: 1, bias: 13)
      ..triangle(-0.205, 0.915, -0.205, 0.77, -0.06, 0.915, 0.384);
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
    b
      ..use(mPelvis, sFace, dyn: dHeart, cx: 0, cy: 0.64)
      ..heart(0, 0.64, 0.392, 0.16)
      // Scanlines across the glow.
      ..use(mPelvis, sScreen, lod: 1, bias: 16);
    for (var j = 0; j < 14; j++) {
      b.quadFrom(0, 0.38 + j * 0.036, 0.394, 0.215, 0.007);
    }

    // Panel outlines (grooves), screws as discs, a vent strip.
    b.use(mPelvis, sSeam, lod: 1);
    for (final sx in const [-1.0, 1.0]) {
      b
        ..simpleBox(sx * 0.425, 0.95, 0.0, 0.012, 0.008, 0.2)
        ..simpleBox(sx * 0.425, 0.25, 0.0, 0.012, 0.008, 0.2)
        ..simpleBox(sx * 0.425, 0.6, 0.2, 0.012, 0.35, 0.008)
        ..simpleBox(sx * 0.425, 0.6, -0.2, 0.012, 0.35, 0.008);
    }
    b.use(mPelvis, sMetal, lod: 1);
    for (final sx in const [-1.0, 1.0]) {
      for (final y in const [0.25, 0.95]) {
        for (final z in const [-0.2, 0.2]) {
          b.cylinderX(sx * 0.43, y, z, 0.033, 0.026, 8);
        }
      }
    }
    b
      ..use(mPelvis, sVent, lod: 1)
      ..simpleBox(0, 0.17, 0.362, 0.17, 0.012, 0.01)
      ..simpleBox(0, 0.1, 0.362, 0.17, 0.012, 0.01);
    // The decal on the right side: "NV" in orange pixels.
    b
      ..use(mPelvis, sRim, lod: 1, bias: 3.4)
      ..pixelText(const ['X..X.X..X', 'XX.X.X..X', 'X.XX.X..X', 'X..X..XX.', 'X..X..XX.'], 0.43, 0.46, 0.145, 0.024)
      // An orange stripe on the left side.
      ..simpleBox(-0.43, 0.6, 0.0, 0.01, 0.3, 0.035)
      // A printed label on the back: paper, text lines, a barcode, a dot.
      ..use(mPelvis, sLabel, lod: 1, bias: 3.2)
      ..simpleBox(0, 0.62, -0.366, 0.22, 0.2, 0.006)
      ..use(mPelvis, sSeam, lod: 1, bias: 3.8);
    for (var i = 0; i < 4; i++) {
      b.simpleBox(0.07 - (i == 1 ? 0.05 : 0), 0.74 - i * 0.045, -0.373, i == 1 ? 0.1 : 0.14, 0.008, 0.004);
    }
    for (var i = 0; i < 9; i++) {
      b.simpleBox(-0.17 + i * 0.03, 0.56, -0.373, i.isEven ? 0.008 : 0.004, 0.03, 0.004);
    }
    b
      ..use(mPelvis, sRim, lod: 1, bias: 3.8)
      ..simpleBox(0.15, 0.55, -0.373, 0.025, 0.025, 0.004);

    // ---- Neck (relative to the neck joint): rod, joint collars and ribs ----
    b
      ..use(mNeck, sNeck)
      ..cylinder(0, 0, 0.07, 0.0, 0.5, 10)
      ..use(mNeck, sMetal)
      ..cylinder(0, 0, 0.16, 0.0, 0.09, 14, caps: true)
      ..cylinder(0, 0, 0.14, 0.33, 0.4, 14, caps: true)
      ..use(mNeck, sMetal, lod: 1);
    for (final y in const [0.15, 0.2, 0.25]) {
      b.cylinder(0, 0, 0.085, y, y + 0.025, 10, caps: true);
    }

    // ---- Head (relative to the head joint; helmet equator at y 0) ----
    for (final hi in const [false, true]) {
      b
        ..tier(hi)
        ..use(mHead, sHelmet)
        ..ao = ((x, y, z) => 1 - 0.18 * _s((0.1 - y) / 0.2))
        ..dome(0, 0.02, 0, 0.85, 0.9, hi ? 40 : 16, hi ? 14 : 5)
        ..ao = null
        ..use(mHead, sRim)
        ..torus(0, -0.03, 0, 0.9, 0.09, hi ? 40 : 16, hi ? 10 : 5)
        ..use(mHead, sSeam)
        ..cylinder(0, 0, 0.815, 0.25, 0.31, hi ? 40 : 16)
        ..use(mHead, sLed)
        ..sphere(MicroduckMesh.ledX, MicroduckMesh.ledY, MicroduckMesh.ledZ, 0.095, hi ? 12 : 6, hi ? 5 : 3);
    }
    b.tier(null);
    for (final sx in const [-1.0, 1.0]) {
      b.use(mHead, sVent, lod: 1);
      for (final z in const [-0.22, -0.1, 0.02]) {
        b.simpleBox(sx * 0.775, 0.2, z, 0.03, 0.075, 0.025);
      }
      b.use(mHead, sMetal, lod: 1);
      for (final z in const [0.4, -0.4]) {
        // Bolt heads: discs on the rim's side with a slot.
        b.cylinderX(sx * 0.9, -0.03, z, 0.06, 0.05, 8);
      }
      b
        ..use(mHead, sSeam, lod: 2)
        ..simpleBox(sx * 0.93, -0.03, 0.4, 0.008, 0.008, 0.045)
        ..simpleBox(sx * 0.93, -0.03, -0.4, 0.008, 0.008, 0.045);
    }

    // ---- Legs (relative to hip / knee / ankle joints) ----
    for (final m in const [mHipL, mHipR]) {
      final hip = m, knee = m + 1, ankle = m + 2;
      final inward = m == mHipL ? 1.0 : -1.0; // +x side of a left leg faces the body
      final out = -inward;
      for (final hi in const [false, true]) {
        final bevel = hi ? 3 : 1, seg = hi ? 28 : 12;
        b
          ..tier(hi)
          ..use(hip, sThigh)
          ..ao = ((x, y, z) => 1 - 0.3 * _s((x * inward) / 0.25) - 0.1 * _s((-y - 0.55) / 0.15))
          ..roundedBox(0, -0.3, 0, 0.34, 0.38, 0.38, 0.11, bevel: bevel)
          ..ao = null
          ..use(hip, sMetal)
          ..cylinderX(0, 0, 0, 0.19, 0.8, seg)
          ..use(knee, sShin)
          ..roundedBox(0, -0.4, 0, 0.2, 0.4, 0.24, 0.08, bevel: bevel)
          ..use(knee, sMetal)
          ..cylinderX(0, 0, 0, 0.14, 0.56, seg)
          ..use(ankle, sFoot)
          ..ao = ((x, y, z) => 0.8 + 0.2 * _s((y + 0.28) / 0.2))
          ..roundedBox(0, -0.15, 0.14, 0.28, 0.15, 0.46, 0.1, bevel: bevel)
          ..ao = null
          ..use(ankle, sMetal)
          ..cylinderX(0, 0, 0, 0.11, 0.66, hi ? 22 : 10)
          ..use(ankle, sSole)
          ..roundedBox(0, -0.285, 0.14, 0.3, 0.03, 0.5, 0.02, bevel: bevel)
          ..use(ankle, sFoot)
          ..roundedBox(0, -0.2, -0.3, 0.2, 0.1, 0.1, 0.05, bevel: bevel);
      }
      b
        ..tier(null)
        ..use(ankle, sFoot, lod: 1)
        ..roundedBox(0, -0.1, 0.56, 0.22, 0.1, 0.03, 0.03)
        // Hinge pins through each joint, with hex heads, and sole tread.
        ..use(hip, sMetal, lod: 1)
        ..cylinderX(0, 0, 0, 0.035, 0.92, 8)
        ..cylinderX(-0.46, 0, 0, 0.065, 0.04, 6)
        ..cylinderX(0.46, 0, 0, 0.065, 0.04, 6)
        ..use(knee, sMetal, lod: 1)
        ..cylinderX(0, 0, 0, 0.03, 0.7, 8)
        ..cylinderX(-0.35, 0, 0, 0.055, 0.04, 6)
        ..cylinderX(0.35, 0, 0, 0.055, 0.04, 6)
        ..use(ankle, sMetal, lod: 1)
        ..cylinderX(0, 0, 0, 0.028, 0.78, 8)
        ..cylinderX(-0.39, 0, 0, 0.05, 0.04, 6)
        ..cylinderX(0.39, 0, 0, 0.05, 0.04, 6);
      for (var i = 0; i < 7; i++) {
        b.simpleBox(out * 0.305, -0.285, -0.2 + i * 0.13, 0.012, 0.022, 0.04);
      }
      // Servo screws on the thigh's outer face, and the cable looping from
      // the torso down into the leg, then along the shin's back.
      b
        ..use(hip, sMetal, lod: 1)
        ..cylinderX(out * 0.34, -0.3, 0.2, 0.03, 0.02, 8)
        ..cylinderX(out * 0.34, -0.3, -0.2, 0.03, 0.02, 8)
        ..use(hip, sNeck, lod: 1)
        ..torusX(inward * 0.12, 0.06, -0.42, 0.12, 0.024, 12, 5)
        ..cylinder(inward * 0.12, -0.42, 0.028, -0.62, -0.06, 6)
        ..use(knee, sNeck, lod: 1)
        ..cylinder(0, -0.27, 0.03, -0.7, -0.05, 6)
        ..torusX(0, -0.04, -0.27, 0.08, 0.02, 10, 5);
    }
    return b.pack();
  }

  static double _s(double x) {
    final c = x.clamp(0.0, 1.0);
    return c * c * (3 - 2 * c);
  }
}

class _Builder {
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
        sFace || sLed || sScreen || sGlint => (0.12, 0.12),
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
    final mesh = MicroduckMesh._(
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
