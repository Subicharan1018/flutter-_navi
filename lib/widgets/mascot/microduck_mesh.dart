import 'dart:math' as math;
import 'dart:typed_data';

import 'mesh_builder.dart';

/// The colourways, after the real toy: white and orange (the default),
/// light blue and orange, grey and yellow with a purple eye, lilac and yellow.
enum MicroduckSkin {
  white,
  blue,
  grey,
  lilac;

  String get label => switch (this) {
        white => 'White and orange',
        blue => 'Light blue and orange',
        grey => 'Grey and yellow',
        lilac => 'Lilac and yellow',
      };

  /// 0xRRGGBB per colour slot ([sTorso] ...).
  List<int> get colors => switch (this) {
        white => _white,
        blue => _blue,
        grey => _grey,
        lilac => _lilac,
      };

  static List<int> _with(Map<int, int> over) {
    final l = [..._white];
    over.forEach((k, v) => l[k] = v);
    return List.unmodifiable(l);
  }

  static const List<int> _white = [
    0xEFEBE0, // torso
    0x14161A, // screen
    0x17181B, // neck: black servos
    0xF6F2E8, // helmet
    0xE8721C, // rim ring decal
    0xFF9A3C, // led
    0xEBE6DA, // thigh
    0x26272C, // shin: black servo
    0xE8721C, // foot
    0x2B2C31, // seam
    0x26272B, // vent
    0xB9BBC0, // metal
    0xF1E7D0, // sole
    0x8FE8FF, // face
    0x2E3640, // glass glint
    0xE4E0CF, // label paper
    0xE8721C, // lens ring
    0x3E86D6, // iris
    0x08090C, // pupil
    0xE8721C, // beak
    0xFFFFFF, // eye glint
  ];

  static final List<int> _blue = _with({
    sTorso: 0x9FCBE6,
    sHelmet: 0xB4D8EE,
    sThigh: 0x9FCBE6,
    sRim: 0xF28A2E,
    sFoot: 0xF28A2E,
    sBeak: 0xF28A2E,
    sLens: 0xF28A2E,
    sIris: 0x2F4F8F,
  });

  static final List<int> _grey = _with({
    sTorso: 0x8F9298,
    sHelmet: 0xA3A6AB,
    sThigh: 0x8F9298,
    sRim: 0xF2C230,
    sFoot: 0xF2C230,
    sBeak: 0xF2C230,
    sLens: 0xF2C230,
    sIris: 0x7B4FD0,
    sSole: 0x3A3B40,
    sFace: 0x6EE59A,
  });

  static final List<int> _lilac = _with({
    sTorso: 0xB9A4E0,
    sHelmet: 0xCDBCEE,
    sThigh: 0xB9A4E0,
    sRim: 0xF2C230,
    sFoot: 0xF2C230,
    sBeak: 0xF2C230,
    sLens: 0xF2C230,
    sIris: 0x3E86D6,
    sFace: 0xC8B8FF,
  });
}

/// Colour slots. A vertex's slot picks its colour from the skin.
const int sTorso = 0, sScreen = 1, sNeck = 2, sHelmet = 3, sRim = 4, sLed = 5, sThigh = 6;
const int sShin = 7, sFoot = 8, sSeam = 9, sVent = 10, sMetal = 11, sSole = 12, sFace = 13;
const int sGlint = 14, sLabel = 15, sLens = 16, sIris = 17, sPupil = 18, sBeak = 19, sGlintW = 20;
const int kSlotCount = 21;

/// Slots that glow rather than catch light.
bool slotEmissive(int s) => s == sLed || s == sFace || s == sGlintW;

/// How a slot's surface reflects: specular strength, specular tightness (the
/// exponent) and how much of the soft environment band it shows. Glossy lens
/// and head, satin soft-touch panels, brushed metal, dark rubber.
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
  Material(0.55, 36, 0.3), // head: painted, with a clear highlight
  Material(0.5, 26, 0.2), // ring decal
  _rubber, // led
  _satin, // thigh
  _rubber, // shin
  _satin, // foot
  Material(0.45, 24, 0.12), // seam
  _rubber, // vent
  Material(0.7, 10, 0.1), // metal, brushed
  _satin, // sole
  _rubber, // face
  _rubber, // glint
  _satin, // label
  Material(0.8, 30, 0.2), // lens ring
  Material(1.0, 44, 0.6), // iris: glossy glass
  Material(0.9, 52, 0.5), // pupil
  _satin, // beak
  _rubber, // eye glint
];

/// Matrix ids: which joint moves a vertex.
const int mPelvis = 0, mNeck = 1, mHead = 2, mHipL = 3, mKneeL = 4, mAnkleL = 5;
const int mHipR = 6, mKneeR = 7, mAnkleR = 8, mNeckMid = 9;
const int kMatrixCount = 10;

/// Dynamic face pieces: the renderer scales/offsets them each frame. The
/// chest screen's pixel eyes, equaliser bars, mouth and heart; the lens eye's
/// pupil, lids and glint; the beak's lower lip.
const int dEyeL = 1, dEyeR = 2, dBar0 = 3, dBarCount = 5, dHeart = 8;
const int dPupil = 9, dLidTop = 10, dLidBot = 11, dGlint = 12, dJaw = 13, dMouth = 14;
const int kDynCount = 15;

/// Body proportions, in robot units (feet at y 0).
const double kThigh = 0.66, kShin = 0.8, kAnkleH = 0.3, kHipY = 1.76, kHipX = 0.64;

/// The neck is two servo segments; [kNeckBase] is where it leaves the torso
/// (above the pelvis joint) and [kNeckSeg] is each segment's length.
const double kNeckBase = 1.08, kNeckSeg = 0.36;

/// Where the lens eye sits in the head's frame.
const double kEyeX = 0.14, kEyeY = 0.9, kEyeZ = 0.93;

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

  int get vertexCount => px.length;
  int get triCount => tris.length ~/ 3;

  MicroduckMesh.raw(
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

  static double _s(double x) {
    final c = x.clamp(0.0, 1.0);
    return c * c * (3 - 2 * c);
  }

  static MicroduckMesh _build() {
    final b = MeshBuilder();
    const sz = 0.435; // the chest screen's plane

    // ---- Torso (relative to the pelvis joint at hip height): a soft block ----
    for (final hi in const [false, true]) {
      b
        ..tier(hi)
        ..use(mPelvis, sTorso)
        ..ao = ((x, y, z) => 1 - 0.3 * _s((y - 0.95) / 0.2) - 0.16 * _s((0.25 - y) / 0.2))
        ..roundedBox(0, 0.62, 0, 0.5, 0.52, 0.42, 0.2, bevel: hi ? 3 : 2)
        ..ao = null;
    }
    b.tier(null);

    // The chest HUD: bezel, glass, glint, a pixel grid and scanlines, and the
    // face on it.
    b
      ..use(mPelvis, sMetal)
      ..simpleBox(0, 0.64 + 0.31, sz, 0.255, 0.02, 0.03)
      ..simpleBox(0, 0.64 - 0.31, sz, 0.255, 0.02, 0.03)
      ..simpleBox(-0.235, 0.64, sz, 0.02, 0.29, 0.03)
      ..simpleBox(0.235, 0.64, sz, 0.02, 0.29, 0.03)
      ..use(mPelvis, sScreen)
      ..quad(0, 0.64, sz, 0.215, 0.29)
      ..use(mPelvis, sGlint, lod: 1, bias: 13)
      ..triangle(-0.205, 0.915, -0.205, 0.77, -0.06, 0.915, sz + 0.009);
    for (final side in const [-1, 1]) {
      b
        ..use(mPelvis, sFace, dyn: side < 0 ? dEyeL : dEyeR, cx: side * 0.105, cy: 0.74)
        ..quad(side * 0.105, 0.74, sz + 0.017, 0.05, 0.07);
    }
    for (var i = 0; i < dBarCount; i++) {
      const bottom = 0.5;
      final x = (i - 2) * 0.075;
      b
        ..use(mPelvis, sFace, dyn: dBar0 + i, cx: x, cy: bottom)
        ..quadFrom(x, bottom, sz + 0.017, 0.026, 0.3);
    }
    b
      ..use(mPelvis, sFace, dyn: dHeart, cx: 0, cy: 0.64)
      ..heart(0, 0.64, sz + 0.017, 0.16)
      // A pixel smile: five little squares in a curve.
      ..use(mPelvis, sFace, dyn: dMouth, cx: 0, cy: 0.52);
    for (final (x, y) in const [(-0.1, 0.545), (-0.05, 0.515), (0.0, 0.505), (0.05, 0.515), (0.1, 0.545)]) {
      b.quad(x, y, sz + 0.017, 0.022, 0.016);
    }
    b.use(mPelvis, sScreen, lod: 1, bias: 16);
    for (var j = 0; j < 14; j++) {
      b.quadFrom(0, 0.38 + j * 0.036, sz + 0.019, 0.215, 0.007);
    }
    // Pixel grid: faint vertical gaps between the LCD's columns.
    for (var i = -6; i <= 6; i++) {
      b.quadFrom(i * 0.032, 0.36, sz + 0.019, 0.0035, 0.56);
    }

    // Panel outlines (grooves), rivets as discs, a vent strip, an orange ring
    // decal around the middle of the torso.
    b.use(mPelvis, sSeam, lod: 1);
    for (final sx in const [-1.0, 1.0]) {
      b
        ..simpleBox(sx * 0.505, 0.95, 0.0, 0.012, 0.008, 0.22)
        ..simpleBox(sx * 0.505, 0.25, 0.0, 0.012, 0.008, 0.22)
        ..simpleBox(sx * 0.505, 0.6, 0.22, 0.012, 0.35, 0.008)
        ..simpleBox(sx * 0.505, 0.6, -0.22, 0.012, 0.35, 0.008);
    }
    b.use(mPelvis, sMetal, lod: 1);
    for (final sx in const [-1.0, 1.0]) {
      for (final y in const [0.25, 0.95]) {
        for (final z in const [-0.22, 0.22]) {
          b.cylinderX(sx * 0.51, y, z, 0.033, 0.026, 8);
        }
      }
    }
    b
      ..use(mPelvis, sVent, lod: 1)
      ..simpleBox(0, 0.17, 0.408, 0.17, 0.012, 0.01)
      ..simpleBox(0, 0.1, 0.408, 0.17, 0.012, 0.01)
      // "NV" in orange pixels on the right side, a stripe on the left.
      ..use(mPelvis, sRim, lod: 1, bias: 3.4)
      ..pixelText(const ['X..X.X..X', 'XX.X.X..X', 'X.XX.X..X', 'X..X..XX.', 'X..X..XX.'], 0.51, 0.46, 0.145, 0.024)
      ..simpleBox(-0.51, 0.6, 0.0, 0.01, 0.3, 0.035)
      // The printed label on the back: paper, text, barcode, a dot.
      ..use(mPelvis, sLabel, lod: 1, bias: 3.2)
      ..simpleBox(0, 0.62, -0.416, 0.22, 0.2, 0.006)
      ..use(mPelvis, sSeam, lod: 1, bias: 3.8);
    for (var i = 0; i < 4; i++) {
      b.simpleBox(0.07 - (i == 1 ? 0.05 : 0), 0.74 - i * 0.045, -0.423, i == 1 ? 0.1 : 0.14, 0.008, 0.004);
    }
    for (var i = 0; i < 9; i++) {
      b.simpleBox(-0.17 + i * 0.03, 0.56, -0.423, i.isEven ? 0.008 : 0.004, 0.03, 0.004);
    }
    b
      ..use(mPelvis, sRim, lod: 1, bias: 3.8)
      ..simpleBox(0.15, 0.55, -0.423, 0.025, 0.025, 0.004)
      // A band of hazard stripes along the torso's lower edge.
      ..use(mPelvis, sBeak, lod: 1, bias: 3.5);
    for (var i = 0; i < 6; i++) {
      if (i.isEven) b.simpleBox(-0.3 + i * 0.12, 0.045, 0.424, 0.045, 0.02, 0.004);
    }

    // ---- Neck: two black servo segments with hubs, collars and wires ----
    for (final m in const [mNeck, mNeckMid]) {
      b
        ..tier(null)
        ..use(m, sNeck)
        ..roundedBox(0, 0.17, 0, 0.15, 0.17, 0.15, 0.07)
        ..use(m, sMetal)
        ..cylinderX(0, 0.17, 0, 0.12, 0.38, 14)
        ..cylinder(0, 0, 0.17, 0.0, 0.05, 14, caps: true)
        ..use(m, sNeck, lod: 1)
        ..torusX(0, 0.12, -0.17, 0.1, 0.018, 10, 5)
        ..torusX(0.04, 0.24, -0.17, 0.07, 0.014, 10, 5)
        ..use(m, sMetal, lod: 1)
        ..cylinderX(-0.2, 0.17, 0, 0.05, 0.03, 8)
        ..cylinderX(0.2, 0.17, 0, 0.05, 0.03, 8);
    }

    // ---- Head (relative to the neck's top): big, round and cheerful ----
    const cy = 0.82; // the head's centre height
    for (final hi in const [false, true]) {
      b
        ..tier(hi)
        ..use(mHead, sHelmet)
        ..ao = ((x, y, z) => 1 - 0.2 * _s((cy - 0.15 - y) / 0.5))
        ..ellipsoid(0, cy, 0.04, 0.94, 0.84, 0.92, hi ? 36 : 20, hi ? 18 : 10)
        ..ao = null
        // The lens eye: a coloured ring, a glossy iris, a dark pupil.
        ..use(mHead, sLens)
        ..torusZ(kEyeX, kEyeY, kEyeZ - 0.02, 0.4, 0.07, hi ? 28 : 16, hi ? 8 : 5)
        ..use(mHead, sIris)
        ..disc(kEyeX, kEyeY, kEyeZ + 0.003, 0.34, hi ? 28 : 16);
    }
    b
      ..tier(null)
      ..use(mHead, sPupil, dyn: dPupil, cx: kEyeX, cy: kEyeY, bias: 6)
      ..disc(kEyeX, kEyeY, kEyeZ + 0.012, 0.17, 18)
      ..use(mHead, sGlintW, dyn: dGlint, cx: kEyeX + 0.11, cy: kEyeY + 0.11, bias: 7)
      ..disc(kEyeX + 0.11, kEyeY + 0.11, kEyeZ + 0.02, 0.07, 10)
      // The eyelids: head-coloured discs that close from the top and bottom.
      ..use(mHead, sHelmet, dyn: dLidTop, cx: kEyeX, cy: kEyeY + 0.38, bias: 9)
      ..disc(kEyeX, kEyeY, kEyeZ + 0.03, 0.385, 24)
      ..use(mHead, sHelmet, dyn: dLidBot, cx: kEyeX, cy: kEyeY - 0.38, bias: 9)
      ..disc(kEyeX, kEyeY, kEyeZ + 0.03, 0.385, 24)
      // The beak: a soft lip below the eye, and a lower jaw that can open.
      ..use(mHead, sBeak)
      ..roundedBox(0.0, cy - 0.46, 0.76, 0.46, 0.1, 0.3, 0.09, bevel: 2)
      ..use(mHead, sBeak, dyn: dJaw, cx: 0, cy: 0, bias: 1)
      ..roundedBox(0.0, cy - 0.59, 0.7, 0.4, 0.07, 0.24, 0.06, bevel: 2)
      // Cheek hubs on the sides, with caps.
      ..use(mHead, sNeck);
    for (final sx in const [-1.0, 1.0]) {
      b
        ..use(mHead, sNeck)
        ..cylinderX(sx * 0.97, cy - 0.05, 0.0, 0.26, 0.14, 18)
        ..use(mHead, sMetal)
        ..cylinderX(sx * 1.05, cy - 0.05, 0.0, 0.15, 0.06, 14)
        ..use(mHead, sMetal, lod: 1);
      for (var k = 0; k < 4; k++) {
        final a = k * math.pi / 2 + math.pi / 4;
        b.cylinderX(sx * 1.02, cy - 0.05 + 0.2 * math.sin(a), 0.2 * math.cos(a), 0.022, 0.03, 6);
      }
    }
    // Painted details, BB-8 style: an orange ring around the head, a dark
    // seam over the top, and a couple of rivets.
    b
      ..use(mHead, sRim, lod: 1, bias: 4)
      ..torus(0, cy + 0.3, 0.04, 0.92, 0.05, 28, 5)
      ..torus(0, cy + 0.42, 0.04, 0.83, 0.022, 28, 4)
      ..use(mHead, sMetal, lod: 1);
    for (var k = -2; k <= 2; k++) {
      b.sphere(-0.55 + k * 0.1, cy + 0.67 - (k * k) * 0.012, 0.58 - (k * k) * 0.025, 0.026, 5, 2);
    }

    // ---- Legs (relative to hip / knee / ankle joints): chunky and round ----
    for (final m in const [mHipL, mHipR]) {
      final hip = m, knee = m + 1, ankle = m + 2;
      final inward = m == mHipL ? 1.0 : -1.0; // +x side of a left leg faces the body
      final out = -inward;
      for (final hi in const [false, true]) {
        final bevel = hi ? 3 : 2, seg = hi ? 28 : 12;
        b
          ..tier(hi)
          ..use(hip, sThigh)
          ..ao = ((x, y, z) => 1 - 0.3 * _s((x * inward) / 0.25) - 0.1 * _s((-y - 0.55) / 0.15))
          ..roundedBox(0, -0.3, 0, 0.36, 0.4, 0.4, 0.2, bevel: bevel)
          ..ao = null
          ..use(hip, sNeck)
          ..cylinderX(0, 0, 0, 0.2, 0.86, seg)
          ..use(hip, sMetal)
          ..cylinderX(0, 0, 0, 0.12, 0.98, seg)
          ..use(knee, sShin)
          ..roundedBox(0, -0.4, 0, 0.2, 0.4, 0.24, 0.12, bevel: hi ? 2 : 1)
          ..use(knee, sNeck)
          ..cylinderX(0, 0, 0, 0.15, 0.56, seg)
          ..use(ankle, sFoot)
          ..ao = ((x, y, z) => 0.8 + 0.2 * _s((y + 0.28) / 0.2))
          ..roundedBox(0, -0.15, 0.2, 0.34, 0.15, 0.54, 0.15, bevel: bevel)
          ..ao = null
          ..use(ankle, sNeck)
          ..cylinderX(0, 0, 0, 0.12, 0.7, hi ? 22 : 10)
          ..use(ankle, sSole)
          ..roundedBox(0, -0.285, 0.2, 0.36, 0.03, 0.56, 0.02, bevel: 1);
      }
      b
        ..tier(null)
        // Hinge pins through each joint, with hex heads, and sole tread.
        ..use(hip, sMetal, lod: 1)
        ..cylinderX(-0.5, 0, 0, 0.065, 0.04, 6)
        ..cylinderX(0.5, 0, 0, 0.065, 0.04, 6)
        ..use(knee, sMetal, lod: 1)
        ..cylinderX(-0.31, 0, 0, 0.055, 0.04, 6)
        ..cylinderX(0.31, 0, 0, 0.055, 0.04, 6)
        ..use(ankle, sMetal, lod: 1)
        ..cylinderX(-0.37, 0, 0, 0.05, 0.04, 6)
        ..cylinderX(0.37, 0, 0, 0.05, 0.04, 6);
      for (var i = 0; i < 7; i++) {
        b
          ..use(ankle, sSeam, lod: 1)
          ..simpleBox(out * 0.365, -0.285, -0.12 + i * 0.13, 0.012, 0.022, 0.04);
      }
      // Hazard stripes across the toes; servo screws and cables on the leg.
      b.use(ankle, sBeak, lod: 1, bias: 2.5);
      for (var i = 0; i < 4; i++) {
        b.simpleBox(-0.21 + i * 0.14, -0.002, 0.62, 0.05, 0.006, 0.07);
      }
      b
        ..use(hip, sMetal, lod: 1)
        ..cylinderX(out * 0.37, -0.3, 0.2, 0.03, 0.02, 8)
        ..cylinderX(out * 0.37, -0.3, -0.2, 0.03, 0.02, 8)
        ..use(hip, sNeck, lod: 1)
        ..torusX(inward * 0.12, 0.06, -0.44, 0.12, 0.024, 12, 5)
        ..cylinder(inward * 0.12, -0.44, 0.028, -0.62, -0.06, 6)
        ..use(knee, sNeck, lod: 1)
        ..cylinder(0, -0.27, 0.03, -0.7, -0.05, 6)
        ..torusX(0, -0.04, -0.27, 0.08, 0.02, 10, 5);
    }
    return b.pack();
  }
}
