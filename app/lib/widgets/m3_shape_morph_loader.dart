import 'dart:math' as math;
import 'package:flutter/material.dart';

/// The 7 Canonical Material 3 Expressive Shapes.
enum M3CanonicalShape {
  circle, // 0: Circle
  roundedSquare, // 1: Squircle / Rounded Square
  pill, // 2: Pill / Capsule
  clover, // 3: 4-Leaf Clover / Scallop
  burst, // 4: 8-Point Star / Burst
  diamond, // 5: Diamond / Rhombus
  triangle, // 6: Rounded Triangle / Arch
}

/// A signature Material 3 Expressive loader widget that continuously
/// morphs between all 7 canonical M3 shapes in sequence.
class M3ShapeMorphLoader extends StatefulWidget {
  final double size;
  final Color? color;
  final List<Color>? gradientColors;
  final double strokeWidth;
  final bool isFilled;
  final String? label;
  final Duration morphDuration;

  const M3ShapeMorphLoader({
    super.key,
    this.size = 56.0,
    this.color,
    this.gradientColors,
    this.strokeWidth = 3.5,
    this.isFilled = true,
    this.label,
    this.morphDuration = const Duration(milliseconds: 1400),
  });

  @override
  State<M3ShapeMorphLoader> createState() => _M3ShapeMorphLoaderState();
}

class _M3ShapeMorphLoaderState extends State<M3ShapeMorphLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  static const int _shapeCount = 7;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.morphDuration.inMilliseconds * _shapeCount),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = widget.color ?? theme.colorScheme.primary;
    final tertiary = theme.colorScheme.tertiary;
    final secondary = theme.colorScheme.secondary;

    final defaultGradient = widget.gradientColors ?? [
      primary,
      tertiary,
      secondary,
      primary,
    ];

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final totalProgress = _controller.value * _shapeCount;
        final currentShapeIndex = totalProgress.floor() % _shapeCount;
        final nextShapeIndex = (currentShapeIndex + 1) % _shapeCount;
        final stepProgress = totalProgress - totalProgress.floor();

        final curvedT = Curves.easeInOutCubicEmphasized.transform(stepProgress);
        final rotation = (_controller.value * 2 * math.pi) + (curvedT * math.pi / 4);
        final scale = 1.0 - (math.sin(curvedT * math.pi) * 0.08);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.rotate(
              angle: rotation,
              child: Transform.scale(
                scale: scale,
                child: CustomPaint(
                  size: Size(widget.size, widget.size),
                  painter: _M3ShapeMorphPainter(
                    fromShape: currentShapeIndex,
                    toShape: nextShapeIndex,
                    progress: curvedT,
                    color: primary,
                    gradientColors: defaultGradient,
                    overallProgress: _controller.value,
                    strokeWidth: widget.strokeWidth,
                    isFilled: widget.isFilled,
                    glowColor: primary.withOpacity(0.28),
                  ),
                ),
              ),
            ),
            if (widget.label != null) ...[
              const SizedBox(height: 14),
              Text(
                widget.label!,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _M3ShapeMorphPainter extends CustomPainter {
  final int fromShape;
  final int toShape;
  final double progress;
  final Color color;
  final List<Color> gradientColors;
  final double overallProgress;
  final double strokeWidth;
  final bool isFilled;
  final Color glowColor;

  static const int _vertexCount = 120;

  _M3ShapeMorphPainter({
    required this.fromShape,
    required this.toShape,
    required this.progress,
    required this.color,
    required this.gradientColors,
    required this.overallProgress,
    required this.strokeWidth,
    required this.isFilled,
    required this.glowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.42;

    final path = Path();

    for (int i = 0; i < _vertexCount; i++) {
      final theta = (2 * math.pi * i) / _vertexCount;

      final rFrom = _getRadiusForShape(fromShape, theta, radius);
      final rTo = _getRadiusForShape(toShape, theta, radius);

      final r = rFrom + (rTo - rFrom) * progress;

      final x = center.dx + r * math.cos(theta);
      final y = center.dy + r * math.sin(theta);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    final glowPaint = Paint()
      ..color = glowColor
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
      ..style = isFilled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 2;
    canvas.drawPath(path, glowPaint);

    final rect = Rect.fromCircle(center: center, radius: radius);
    final gradient = SweepGradient(
      colors: gradientColors,
      transform: GradientRotation(overallProgress * 2 * math.pi),
    );

    if (isFilled) {
      final fillPaint = Paint()
        ..shader = gradient.createShader(rect)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, fillPaint);

      final contourPaint = Paint()
        ..color = Colors.white.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawPath(path, contourPaint);
    } else {
      final strokePaint = Paint()
        ..shader = gradient.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, strokePaint);
    }
  }

  static double _getRadiusForShape(int shape, double theta, double r) {
    switch (shape) {
      case 0: // Circle
        return r;
      case 1: // Squircle
        final c = math.cos(theta);
        final s = math.sin(theta);
        final denom = math.pow(math.pow(c, 4) + math.pow(s, 4), 0.25);
        return denom > 0.001 ? (r * 0.95) / denom : r;
      case 2: // Pill
        final oval = 1.0 + 0.26 * math.cos(2 * theta);
        return r * 0.88 * oval;
      case 3: // 4-Leaf Clover
        return r * (0.76 + 0.24 * math.cos(4 * theta));
      case 4: // Burst
        return r * (0.78 + 0.22 * math.cos(8 * theta));
      case 5: // Diamond
        final rot = theta - (math.pi / 4);
        final cD = math.cos(rot);
        final sD = math.sin(rot);
        final denomD = math.pow(math.pow(cD, 4) + math.pow(sD, 4), 0.25);
        return denomD > 0.001 ? (r * 0.92) / denomD : r;
      case 6: // Triangle
        return r * (0.80 + 0.20 * math.cos(3 * theta - (math.pi / 2)));
      default:
        return r;
    }
  }

  @override
  bool shouldRepaint(covariant _M3ShapeMorphPainter oldDelegate) {
    return oldDelegate.fromShape != fromShape ||
        oldDelegate.toShape != toShape ||
        oldDelegate.progress != progress ||
        oldDelegate.overallProgress != overallProgress ||
        oldDelegate.color != color;
  }
}
