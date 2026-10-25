import 'dart:math' as math;
import 'dart:typed_data';

import 'mesh_builder.dart';

/// The colourways of the real toy: cream and orange (the default), light blue
/// and orange, grey and yellow with a purple lens, lilac and yellow.
enum MicroduckSkin {
  white,
  blue,
  grey,
  lilac;

  String get label => switch (this) {
        white => 'Cream and orange',
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
    0xEEE8DA, // torso
    0x14161A, // screen
    0x18191C, // neck: black servos
    0xEEE8DA, // helmet (the head shell)
    0xE8721C, // ring decals
    0xFF9A3C, // led
    0xEEE8DA, // thigh panels
    0x202126, // shin: black servo
    0xF5A623, // foot
    0x2B2C31, // seam
    0x1C1D21, // vent / slots
    0xC9CBCE, // metal: silver horns and rods
    0xE8721C, // sole
    0x8FE8FF, // face
    0x2E3640, // glass glint
    0xE4E0CF, // label paper
    0xF5C22B, // lens ring
    0x090B10, // lens glass
    0x233252, // lens inner ring
    0xE8721C, // beak plates
    0xFFFFFF, // eye glint
    0xD6D2C6, // inside of the head shell
  ];

  static final List<int> _blue = _with({
    sTorso: 0xA9D3E6,
    sHelmet: 0xA9D3E6,
    sThigh: 0xA9D3E6,
    sInner: 0x9FA9B0,
    sRim: 0xE8721C,
    sFoot: 0xE8721C,
    sSole: 0xC85A14,
    sBeak: 0xE8721C,
    sLens: 0xF5C22B,
    sPupil: 0x4A3A12,
  });

  static final List<int> _grey = _with({
    sTorso: 0x6B6D72,
    sHelmet: 0x4B4D52,
    sThigh: 0x6B6D72,
    sInner: 0xB4B6BA,
    sRim: 0xF2C230,
    sFoot: 0xF2C230,
    sSole: 0x6B4FA8,
    sBeak: 0xF2C230,
    sLens: 0x8A63D2,
    sPupil: 0x2B1D52,
    sFace: 0x6EE59A,
  });

  static final List<int> _lilac = _with({
    sTorso: 0xB8A3E0,
    sHelmet: 0xB8A3E0,
    sThigh: 0xB8A3E0,
    sInner: 0xD9D6E0,
    sRim: 0xF2C230,
    sFoot: 0xF2C230,
    sSole: 0x6B4FA8,
    sBeak: 0xF2C230,
    sLens: 0x6CC5E8,
    sPupil: 0x0F3A52,
    sFace: 0xC8B8FF,
  });
}

/// Colour slots. A vertex's slot picks its colour from the skin.
const int sTorso = 0, sScreen = 1, sNeck = 2, sHelmet = 3, sRim = 4, sLed = 5, sThigh = 6;
const int sShin = 7, sFoot = 8, sSeam = 9, sVent = 10, sMetal = 11, sSole = 12, sFace = 13;
const int sGlint = 14, sLabel = 15, sLens = 16, sIris = 17, sPupil = 18, sBeak = 19, sGlintW = 20;
const int sInner = 21;
const int kSlotCount = 22;

/// Slots that glow rather than catch light.
bool slotEmissive(int s) => s == sLed || s == sFace || s == sGlintW;

/// How a slot's surface reflects: specular strength, specular tightness (the
/// exponent) and how much of the soft environment band it shows. Soft-touch
/// painted shells, glossy lens glass, brushed silver, black servo plastic.
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
  Material(0.12, 8, 0.02), // neck: black servo plastic
  Material(0.2, 12, 0.1), // head shell: painted, semi-gloss
  Material(0.35, 20, 0.15), // ring decals
  _rubber, // led
  Material(0.2, 12, 0.08), // thigh panels
  Material(0.12, 8, 0.02), // shin servo
  _satin, // foot
  Material(0.45, 24, 0.12), // seam
  _rubber, // slots
  Material(0.8, 12, 0.12), // silver: brushed metal
  _satin, // sole
  _rubber, // face
  _rubber, // glint
  _satin, // label
  Material(0.5, 22, 0.15), // lens ring
  Material(1.0, 56, 0.7), // lens glass
  Material(0.8, 40, 0.4), // lens inner ring
  Material(0.25, 14, 0.1), // beak plates
  _rubber, // eye glint
  _satin, // inside of the shell
];

/// Matrix ids: which joint moves a vertex.
const int mPelvis = 0, mNeck = 1, mHead = 2, mHipL = 3, mKneeL = 4, mAnkleL = 5;
const int mHipR = 6, mKneeR = 7, mAnkleR = 8, mNeckMid = 9;
const int kMatrixCount = 10;

/// Dynamic face pieces: the renderer scales/offsets them each frame. The
/// chest screen's pixel eyes, equaliser bars, mouth and heart; the lens eye's
/// pupil, lids and glint; the beak's lower plate.
const int dEyeL = 1, dEyeR = 2, dBar0 = 3, dBarCount = 5, dHeart = 8;
const int dPupil = 9, dLidTop = 10, dLidBot = 11, dGlint = 12, dJaw = 13, dMouth = 14;
const int kDynCount = 15;

/// Body proportions, in robot units (feet at y 0).
const double kThigh = 0.66, kShin = 0.8, kAnkleH = 0.3, kHipY = 1.76, kHipX = 0.64;

/// The neck is two black servo segments (and a collar on the head);
/// [kNeckBase] is where it leaves the torso (above the pelvis joint) and
/// [kNeckSeg] is each segment's length.
const double kNeckBase = 1.0, kNeckSeg = 0.54;

/// The head shell's centre height above the neck's top, and where the lens
/// eye sits on its face, in the head's frame.
const double kHeadCy = 0.72;
const double kEyeX = -0.22, kEyeY = kHeadCy + 0.05, kEyeZ = 1.02;

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

  /// A silver servo horn: a disc with a ring of screw holes, on the x axis.
  static void _horn(MeshBuilder b, int m, double x, double y, double z, double r, {double dir = 1}) {
    b
      ..use(m, sMetal)
      ..cylinderX(x, y, z, r, 0.05, 18)
      ..use(m, sVent, lod: 1);
    for (var k = 0; k < 5; k++) {
      final a = k * 2 * math.pi / 5;
      b.cylinderX(x + dir * 0.028, y + r * 0.58 * math.sin(a), z + r * 0.58 * math.cos(a), r * 0.12, 0.02, 6);
    }
  }

  static MicroduckMesh _build() {
    final b = MeshBuilder();
    const sz = 0.435; // the chest screen's plane

    // ---- Black pelvis servo block under the torso ----
    b
      ..tier(null)
      ..use(mPelvis, sNeck)
      ..roundedBox(0, 0.1, 0, 0.5, 0.11, 0.3, 0.07, bevel: 1);
    _horn(b, mPelvis, -0.52, 0.1, 0, 0.12, dir: -1);
    _horn(b, mPelvis, 0.52, 0.1, 0, 0.12);

    // ---- Torso (relative to the pelvis joint at hip height): a soft block ----
    for (final hi in const [false, true]) {
      b
        ..tier(hi)
        ..use(mPelvis, sTorso)
        ..ao = ((x, y, z) => 1 - 0.3 * _s((y - 0.95) / 0.2) - 0.16 * _s((0.25 - y) / 0.2))
        ..roundedBox(0, 0.64, 0, 0.5, 0.46, 0.42, 0.2, bevel: hi ? 3 : 2)
        ..ao = null;
    }
    b.tier(null);

    // The chest HUD: bezel, glass, glint, a pixel grid and scanlines, and the
    // face on it.
    b
      ..use(mPelvis, sMetal)
      ..simpleBox(0, 0.66 + 0.29, sz, 0.255, 0.02, 0.03)
      ..simpleBox(0, 0.66 - 0.29, sz, 0.255, 0.02, 0.03)
      ..simpleBox(-0.235, 0.66, sz, 0.02, 0.27, 0.03)
      ..simpleBox(0.235, 0.66, sz, 0.02, 0.27, 0.03)
      ..use(mPelvis, sScreen)
      ..quad(0, 0.66, sz, 0.215, 0.27)
      ..use(mPelvis, sGlint, lod: 1, bias: 13)
      ..triangle(-0.205, 0.915, -0.205, 0.78, -0.06, 0.915, sz + 0.009);
    for (final side in const [-1, 1]) {
      b
        ..use(mPelvis, sFace, dyn: side < 0 ? dEyeL : dEyeR, cx: side * 0.105, cy: 0.74)
        ..quad(side * 0.105, 0.74, sz + 0.017, 0.05, 0.07);
    }
    for (var i = 0; i < dBarCount; i++) {
      const bottom = 0.52;
      final x = (i - 2) * 0.075;
      b
        ..use(mPelvis, sFace, dyn: dBar0 + i, cx: x, cy: bottom)
        ..quadFrom(x, bottom, sz + 0.017, 0.026, 0.28);
    }
    b
      ..use(mPelvis, sFace, dyn: dHeart, cx: 0, cy: 0.66)
      ..heart(0, 0.66, sz + 0.017, 0.15)
      // A pixel smile: five little squares in a curve.
      ..use(mPelvis, sFace, dyn: dMouth, cx: 0, cy: 0.54);
    for (final (x, y) in const [(-0.1, 0.565), (-0.05, 0.535), (0.0, 0.525), (0.05, 0.535), (0.1, 0.565)]) {
      b.quad(x, y, sz + 0.017, 0.022, 0.016);
    }
    b.use(mPelvis, sScreen, lod: 1, bias: 16);
    for (var j = 0; j < 13; j++) {
      b.quadFrom(0, 0.41 + j * 0.036, sz + 0.019, 0.215, 0.007);
    }
    // Pixel grid: faint vertical gaps between the LCD's columns.
    for (var i = -6; i <= 6; i++) {
      b.quadFrom(i * 0.032, 0.39, sz + 0.019, 0.0035, 0.54);
    }

    // BB-8-style panel work on the torso: seam outlines, ring decals with a
    // little hub, rivets, and a vent strip.
    b.use(mPelvis, sSeam, lod: 1);
    for (final sx in const [-1.0, 1.0]) {
      b
        ..simpleBox(sx * 0.505, 0.93, 0.0, 0.012, 0.008, 0.22)
        ..simpleBox(sx * 0.505, 0.35, 0.0, 0.012, 0.008, 0.22)
        ..simpleBox(sx * 0.505, 0.64, 0.22, 0.012, 0.29, 0.008)
        ..simpleBox(sx * 0.505, 0.64, -0.22, 0.012, 0.29, 0.008);
    }
    b.use(mPelvis, sMetal, lod: 1);
    for (final sx in const [-1.0, 1.0]) {
      for (final y in const [0.35, 0.93]) {
        for (final z in const [-0.22, 0.22]) {
          b.cylinderX(sx * 0.51, y, z, 0.03, 0.026, 8);
        }
      }
    }
    // Orange ring decals on both sides, each with a silver hub and spokes.
    for (final sx in const [-1.0, 1.0]) {
      b
        ..use(mPelvis, sRim, lod: 1, bias: 3.4)
        ..torusX(sx * 0.505, 0.64, 0.0, 0.17, 0.02, 20, 4)
        ..use(mPelvis, sMetal, lod: 1, bias: 3.5)
        ..cylinderX(sx * 0.508, 0.64, 0.0, 0.07, 0.014, 12)
        ..use(mPelvis, sSeam, lod: 1, bias: 3.6)
        ..simpleBox(sx * 0.512, 0.64, 0.0, 0.004, 0.012, 0.12)
        ..simpleBox(sx * 0.512, 0.64, 0.0, 0.004, 0.12, 0.012)
        // Grey panel greebles inside the ring, like BB-8's.
        ..use(mPelvis, sMetal, lod: 1, bias: 3.65)
        ..simpleBox(sx * 0.514, 0.7, 0.05, 0.003, 0.012, 0.07)
        ..simpleBox(sx * 0.514, 0.66, 0.05, 0.003, 0.012, 0.05)
        ..simpleBox(sx * 0.514, 0.6, -0.05, 0.003, 0.012, 0.06)
        ..simpleBox(sx * 0.514, 0.56, -0.05, 0.003, 0.012, 0.08);
    }
    b
      ..use(mPelvis, sVent, lod: 1)
      ..simpleBox(0, 0.23, 0.408, 0.17, 0.012, 0.01)
      ..simpleBox(0, 0.18, 0.408, 0.17, 0.012, 0.01)
      // The printed label on the back: paper, text, barcode, a dot.
      ..use(mPelvis, sLabel, lod: 1, bias: 3.2)
      ..simpleBox(0, 0.64, -0.426, 0.22, 0.18, 0.006)
      ..use(mPelvis, sSeam, lod: 1, bias: 3.8);
    for (var i = 0; i < 4; i++) {
      b.simpleBox(0.07 - (i == 1 ? 0.05 : 0), 0.74 - i * 0.045, -0.433, i == 1 ? 0.1 : 0.14, 0.008, 0.004);
    }
    for (var i = 0; i < 9; i++) {
      b.simpleBox(-0.17 + i * 0.03, 0.58, -0.433, i.isEven ? 0.008 : 0.004, 0.03, 0.004);
    }

    // ---- Neck: three black servo blocks with silver horns and wires ----
    for (final m in const [mNeck, mNeckMid]) {
      b
        ..tier(null)
        ..use(m, sNeck)
        ..roundedBox(0, 0.27, 0, 0.2, 0.27, 0.18, 0.08)
        ..use(m, sNeck, lod: 1)
        ..torusX(0, 0.14, -0.17, 0.11, 0.02, 10, 5)
        ..torusX(0.05, 0.28, -0.17, 0.08, 0.016, 10, 5);
      _horn(b, m, 0.19, 0.2, 0.0, 0.11);
      _horn(b, m, -0.19, 0.2, 0.0, 0.11, dir: -1);
    }

    // ---- Head (relative to the neck's top): a rounded hood with a lens eye
    // set in its face and a beak plate under it, like the real toy ----
    const cy = kHeadCy;
    for (final hi in const [false, true]) {
      b
        ..tier(hi)
        ..use(mHead, sHelmet)
        ..ao = ((x, y, z) => 1 - 0.16 * _s((cy - 0.2 - y) / 0.4))
        ..roundedBox(0, cy, -0.02, 0.84, 0.68, 0.98, 0.38, bevel: hi ? 3 : 2)
        ..ao = null
        // The recessed inside of the hood, which the face looks out of.
        ..use(mHead, sInner)
        ..roundedBox(0, cy + 0.02, 0.96, 0.7, 0.5, 0.04, 0.16, bevel: 1)
        // The lens: a coloured ring around black glass.
        ..use(mHead, sLens)
        ..torusZ(kEyeX, kEyeY, kEyeZ + 0.03, 0.34, 0.085, hi ? 32 : 18, hi ? 8 : 5)
        ..use(mHead, sIris)
        ..disc(kEyeX, kEyeY, kEyeZ + 0.04, 0.3, hi ? 32 : 18);
    }
    b
      ..tier(null)
      ..use(mHead, sPupil, dyn: dPupil, cx: kEyeX, cy: kEyeY, bias: 6)
      ..disc(kEyeX, kEyeY, kEyeZ + 0.052, 0.15, 18)
      ..use(mHead, sGlintW, dyn: dGlint, cx: kEyeX + 0.09, cy: kEyeY + 0.09, bias: 7)
      ..disc(kEyeX + 0.09, kEyeY + 0.09, kEyeZ + 0.06, 0.06, 10)
      // Eyelids: ring-coloured discs that close over the lens.
      ..use(mHead, sLens, dyn: dLidTop, cx: kEyeX, cy: kEyeY + 0.34, bias: 9)
      ..disc(kEyeX, kEyeY, kEyeZ + 0.07, 0.34, 24)
      ..use(mHead, sLens, dyn: dLidBot, cx: kEyeX, cy: kEyeY - 0.34, bias: 9)
      ..disc(kEyeX, kEyeY, kEyeZ + 0.07, 0.34, 24)
      // A small oval slot beside the lens, and the beak: a flat upper plate
      // under the face and a lower plate that can open.
      ..use(mHead, sVent, lod: 1, bias: 3)
      ..roundedBox(0.46, cy + 0.06, 0.995, 0.11, 0.05, 0.012, 0.04)
      ..use(mHead, sBeak)
      ..roundedBox(0.0, cy - 0.46, 1.08, 0.82, 0.07, 0.44, 0.07, bevel: 2)
      ..use(mHead, sBeak, dyn: dJaw, cx: 0, cy: 0, bias: 1)
      ..roundedBox(0.0, cy - 0.58, 1.02, 0.76, 0.05, 0.4, 0.05, bevel: 2)
      // A black servo collar where the neck meets the head, with a horn.
      ..use(mHead, sNeck)
      ..roundedBox(0, 0.1, 0, 0.2, 0.12, 0.17, 0.06);
    _horn(b, mHead, 0.22, 0.1, 0.0, 0.1);
    _horn(b, mHead, -0.22, 0.1, 0.0, 0.1, dir: -1);
    // BB-8-style decals on the shell: a ring with a hub on each side,
    // seams and rivets, and the rivets on the back corner like the real toy.
    for (final sx in const [-1.0, 1.0]) {
      b
        ..use(mHead, sRim, lod: 1, bias: 3.4)
        ..torusX(sx * 0.845, cy + 0.02, -0.12, 0.32, 0.03, 26, 4)
        ..use(mHead, sInner, lod: 1, bias: 3.5)
        ..cylinderX(sx * 0.85, cy + 0.02, -0.12, 0.22, 0.014, 20)
        ..use(mHead, sMetal, lod: 1, bias: 3.6)
        ..cylinderX(sx * 0.856, cy + 0.02, -0.12, 0.08, 0.014, 12)
        ..use(mHead, sSeam, lod: 1, bias: 3.7)
        ..simpleBox(sx * 0.86, cy + 0.02, -0.12, 0.004, 0.01, 0.22)
        ..simpleBox(sx * 0.86, cy + 0.02, -0.12, 0.004, 0.22, 0.01)
        ..use(mHead, sMetal, lod: 1);
      for (var k = 0; k < 4; k++) {
        b.cylinderX(sx * 0.82, cy - 0.5 + k * 0.1, -0.8, 0.022, 0.03, 6);
      }
    }
    b.use(mHead, sSeam, lod: 1, bias: 2);
    for (var k = 0; k < 3; k++) {
      b.simpleBox(0, cy + 0.685, 0.35 - k * 0.45, 0.4, 0.006, 0.006);
    }

    // ---- Legs (relative to hip / knee / ankle joints): black servos, silver
    // horns, a coloured panel on each thigh, chunky coloured feet ----
    for (final m in const [mHipL, mHipR]) {
      final hip = m, knee = m + 1, ankle = m + 2;
      final inward = m == mHipL ? 1.0 : -1.0; // +x side of a left leg faces the body
      final out = -inward;
      for (final hi in const [false, true]) {
        final bevel = hi ? 3 : 2, seg = hi ? 28 : 12;
        b
          ..tier(hi)
          ..use(hip, sNeck)
          ..roundedBox(0, -0.3, 0, 0.3, 0.36, 0.32, 0.14, bevel: bevel)
          ..cylinderX(0, 0, 0, 0.2, 0.86, seg)
          ..use(hip, sThigh)
          ..ao = ((x, y, z) => 1 - 0.25 * _s((-y - 0.55) / 0.15))
          ..roundedBox(out * 0.42, -0.3, -0.02, 0.07, 0.48, 0.44, 0.08, bevel: hi ? 2 : 1)
          ..ao = null
          ..use(knee, sShin)
          ..roundedBox(0, -0.4, 0, 0.17, 0.32, 0.19, 0.08, bevel: hi ? 2 : 1)
          ..use(knee, sNeck)
          ..cylinderX(0, 0, 0, 0.15, 0.5, seg)
          ..use(ankle, sShin)
          ..roundedBox(0, -0.04, 0, 0.15, 0.1, 0.17, 0.06, bevel: 1)
          ..use(ankle, sFoot)
          ..ao = ((x, y, z) => 0.85 + 0.15 * _s((y + 0.28) / 0.2))
          ..roundedBox(0, -0.17, 0.2, 0.34, 0.13, 0.52, 0.13, bevel: bevel)
          ..ao = null
          ..use(ankle, sSole)
          ..roundedBox(0, -0.285, 0.2, 0.355, 0.03, 0.535, 0.03, bevel: 1);
      }
      b.tier(null);
      // Silver horns on the hip, knee and ankle hubs, with their hole rings.
      _horn(b, hip, out * 0.46, 0.0, 0.0, 0.2, dir: out);
      _horn(b, knee, out * 0.27, 0.0, 0.0, 0.14, dir: out);
      _horn(b, ankle, out * 0.2, 0.0, 0.0, 0.11, dir: out);
      // Two silver rods down the shin, wires, hinge screws.
      b
        ..use(knee, sMetal, lod: 1)
        ..cylinder(-0.12, 0.17, 0.028, -0.76, -0.12, 8)
        ..cylinder(0.12, 0.17, 0.028, -0.76, -0.12, 8)
        ..use(knee, sNeck, lod: 1)
        ..cylinder(0, -0.2, 0.03, -0.7, -0.05, 6)
        ..torusX(0, -0.04, -0.2, 0.08, 0.02, 10, 5)
        ..use(hip, sNeck, lod: 1)
        ..torusX(inward * 0.12, 0.06, -0.38, 0.12, 0.024, 12, 5)
        ..cylinder(inward * 0.12, -0.38, 0.028, -0.62, -0.06, 6)
        // Foot details: perforations across the toe, tread on the sole.
        ..use(ankle, sSeam, lod: 1, bias: 2.5);
      for (var i = 0; i < 6; i++) {
        final x = -0.18 + (i % 3) * 0.18;
        final z = 0.5 + (i ~/ 3) * 0.1;
        b.cylinder(x, z, 0.03, -0.045, -0.04, 6, caps: true);
      }
      for (var i = 0; i < 7; i++) {
        b.simpleBox(out * 0.355, -0.285, -0.12 + i * 0.13, 0.012, 0.02, 0.04);
      }
    }
    return b.pack();
  }
}
