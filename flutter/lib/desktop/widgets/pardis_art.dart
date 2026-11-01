import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// Animated artwork along the bottom of the main window in the ParsiDesk
// bright theme: morphing liquid layers with a light sheen, a heartbeat line
// with a travelling pulse, rising bubbles and a breathing molecular lattice.
class ParsiDeskBottomArt extends StatefulWidget {
  const ParsiDeskBottomArt({super.key});

  @override
  State<ParsiDeskBottomArt> createState() => _ParsiDeskBottomArtState();
}

class _ParsiDeskBottomArtState extends State<ParsiDeskBottomArt>
    with SingleTickerProviderStateMixin {
  static const _loopSeconds = 3600;
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(seconds: _loopSeconds));

  @override
  void initState() {
    super.initState();
    _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    if (still && _c.isAnimating) _c.stop();
    return IgnorePointer(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black, Colors.black, Colors.transparent],
          stops: [0, 0.55, 1],
        ).createShader(r),
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => CustomPaint(
              painter: _ArtPainter(_c.value * _loopSeconds),
              size: Size.infinite,
            ),
          ),
        ),
      ),
    );
  }
}

const _teal = Color(0xFF12807A);
const _tealLight = Color(0xFF6FB5AB);
const _gold = Color(0xFFB8925A);

class _Wave {
  final List<List<double>> frames;
  final double seconds;
  const _Wave(this.frames, this.seconds);
}

List<double> _nums(String d) => RegExp(r'-?\d+(\.\d+)?')
    .allMatches(d)
    .map((m) => double.parse(m.group(0)!))
    .toList();

final _waves = <_Wave>[
  _Wave([
    _nums(
        'M0 210 C 160 150 300 270 470 215 S 800 120 960 190 S 1130 240 1200 200 V360 H0Z'),
    _nums(
        'M0 190 C 180 250 320 160 500 200 S 780 260 950 170 S 1120 150 1200 215 V360 H0Z'),
    _nums(
        'M0 225 C 150 170 330 230 460 180 S 820 160 980 225 S 1140 200 1200 185 V360 H0Z'),
  ], 14),
  _Wave([
    _nums(
        'M0 260 C 190 205 330 300 520 255 S 860 190 1010 245 S 1150 285 1200 255 V360 H0Z'),
    _nums(
        'M0 245 C 200 290 350 215 540 250 S 850 300 1020 230 S 1160 240 1200 270 V360 H0Z'),
    _nums(
        'M0 270 C 170 235 320 265 500 230 S 880 230 1000 270 S 1140 260 1200 245 V360 H0Z'),
  ], 11),
  _Wave([
    _nums(
        'M0 305 C 220 270 360 335 560 300 S 900 255 1060 295 S 1160 320 1200 300 V360 H0Z'),
    _nums(
        'M0 295 C 230 320 380 280 570 305 S 890 320 1050 280 S 1170 300 1200 310 V360 H0Z'),
    _nums(
        'M0 312 C 210 290 350 310 550 290 S 910 290 1070 310 S 1150 295 1200 295 V360 H0Z'),
  ], 9),
];

// [x%, size px, seconds, delay seconds]
const _bubbles = <List<double>>[
  [6, 10, 9, -2],
  [14, 15, 12, -7],
  [23, 8, 8, -4],
  [31, 13, 11, -9],
  [42, 9, 10, -1],
  [55, 17, 13, -6],
  [63, 8, 8.5, -3],
  [71, 12, 11.5, -8],
  [80, 9, 9.5, -5],
  [88, 14, 12.5, -10],
  [95, 8, 8, -6.5],
];

class _ArtPainter extends CustomPainter {
  final double t;
  _ArtPainter(this.t);

  static double _ease(double x) => x * x * (3 - 2 * x);

  Path _wavePath(_Wave w, double sx, double sy) {
    final u = (t / w.seconds % 1) * 3;
    final i = u.floor() % 3;
    final f = _ease(u - u.floor());
    final a = w.frames[i], b = w.frames[(i + 1) % 3];
    final n = List<double>.generate(a.length, (k) => a[k] + (b[k] - a[k]) * f);
    final p = Path()..moveTo(n[0] * sx, n[1] * sy);
    p.cubicTo(n[2] * sx, n[3] * sy, n[4] * sx, n[5] * sy, n[6] * sx, n[7] * sy);
    var px = n[6], py = n[7], pcx = n[4], pcy = n[5];
    for (var s = 8; s < 16; s += 4) {
      final c1x = 2 * px - pcx, c1y = 2 * py - pcy;
      p.cubicTo(c1x * sx, c1y * sy, n[s] * sx, n[s + 1] * sy, n[s + 2] * sx,
          n[s + 3] * sy);
      px = n[s + 2];
      py = n[s + 3];
      pcx = n[s];
      pcy = n[s + 1];
    }
    p
      ..lineTo(n[14] * sx, n[16] * sy)
      ..lineTo(0, n[16] * sy)
      ..close();
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 1200, sy = size.height / 360;

    // liquid layers
    final layer0 = Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(size.width, 0), [
        _tealLight.withOpacity(0.28),
        _teal.withOpacity(0.10),
      ]);
    canvas.drawPath(_wavePath(_waves[0], sx, sy), layer0);

    final layer1 = Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), [
        _teal.withOpacity(0.20),
        _teal.withOpacity(0.02),
      ]);
    final mid = _wavePath(_waves[1], sx, sy);
    canvas.drawPath(mid, layer1);

    // sheen drifting across the middle layer
    final phase = (t / 9) % 1;
    final cx = size.width * (-0.3 + 1.6 * phase);
    final sheen = Paint()
      ..blendMode = BlendMode.softLight
      ..shader = ui.Gradient.linear(
        Offset(cx - size.width * 0.25, 0),
        Offset(cx + size.width * 0.25, 0),
        [
          Colors.white.withOpacity(0),
          Colors.white.withOpacity(0.35),
          Colors.white.withOpacity(0),
        ],
        [0, 0.5, 1],
      );
    canvas.drawPath(mid, sheen);

    canvas.drawPath(
        _wavePath(_waves[2], sx, sy), Paint()..color = _teal.withOpacity(0.10));

    _heartbeat(canvas, size, sx, sy);
    _lattice(canvas, size);
    _bubblesPaint(canvas, size);
  }

  void _heartbeat(Canvas canvas, Size size, double sx, double sy) {
    final p = Path()
      ..moveTo(0, 318 * sy)
      ..lineTo(300 * sx, 318 * sy)
      ..lineTo(330 * sx, 296 * sy)
      ..lineTo(366 * sx, 336 * sy)
      ..lineTo(404 * sx, 270 * sy)
      ..lineTo(440 * sx, 330 * sy)
      ..lineTo(468 * sx, 318 * sy)
      ..lineTo(1200 * sx, 318 * sy);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = _teal.withOpacity(0.16);
    canvas.drawPath(p, base);
    final m = p.computeMetrics().first;
    final pulse = m.length * 0.09;
    final start = ((t / 6) % 1) * (m.length + pulse) - pulse;
    final a = start.clamp(0.0, m.length).toDouble();
    final b = (start + pulse).clamp(0.0, m.length).toDouble();
    if (b > a) {
      canvas.drawPath(
          m.extractPath(a, b),
          base
            ..strokeWidth = 2.8
            ..color = _teal.withOpacity(0.55));
    }
  }

  void _lattice(Canvas canvas, Size size) {
    final scale = math.min(size.width * 0.24 / 200, size.height * 0.62 / 150);
    final breathe = 1 + 0.03 * math.sin(t * 2 * math.pi / 8);
    canvas.save();
    canvas.translate(size.width * 0.02, size.height * 0.96 - 150 * scale);
    canvas.scale(scale * breathe);
    canvas.translate(-200, -50);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = _teal.withOpacity(0.22);
    for (final h in const [
      [300.0, 60.0],
      [360.0, 94.0],
      [300.0, 128.0],
      [240.0, 94.0],
    ]) {
      final x = h[0], y = h[1];
      canvas.drawPath(
          Path()
            ..moveTo(x, y)
            ..lineTo(x + 30, y + 17)
            ..lineTo(x + 30, y + 51)
            ..lineTo(x, y + 68)
            ..lineTo(x - 30, y + 51)
            ..lineTo(x - 30, y + 17)
            ..close(),
          line);
    }
    for (final n in const [
      [300.0, 60.0, 5.0, 3.2],
      [360.0, 94.0, 4.0, 4.1],
      [240.0, 94.0, 4.0, 3.7],
      [300.0, 196.0, 5.0, 4.6],
    ]) {
      final k = (math.sin(t * 2 * math.pi / n[3]) + 1) / 2;
      canvas.drawCircle(Offset(n[0], n[1]), n[2] * (1 + 0.6 * k),
          Paint()..color = _teal.withOpacity(0.3 + 0.35 * k));
    }
    canvas.restore();
  }

  void _bubblesPaint(Canvas canvas, Size size) {
    for (var i = 0; i < _bubbles.length; i++) {
      final b = _bubbles[i];
      final prog = (((t - b[3]) / b[2]) % 1 + 1) % 1;
      final r = b[1] / 2;
      final x = size.width * b[0] / 100 +
          math.sin(prog * math.pi * 2) * 10 * (i.isEven ? 1 : -1);
      final y = size.height - prog * (size.height + 20) + 4;
      final alpha = (prog < 0.1
              ? prog / 0.1
              : prog > 0.8
                  ? (1 - prog) / 0.2
                  : 1.0) *
          0.9;
      final ring = i % 3 == 0 ? _gold : _tealLight;
      final c = Offset(x, y);
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader =
                ui.Gradient.radial(c.translate(-r * 0.4, -r * 0.4), r * 1.2, [
              Colors.white.withOpacity(0.7 * alpha),
              Colors.white.withOpacity(0),
            ], [
              0,
              0.6
            ]));
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = ring.withOpacity(alpha));
    }
  }

  @override
  bool shouldRepaint(_ArtPainter old) => old.t != t;
}
