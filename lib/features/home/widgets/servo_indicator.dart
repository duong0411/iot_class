import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class ServoIndicator extends StatelessWidget {
  final double angle;
  final String label;
  final bool isActive;

  const ServoIndicator({
    super.key,
    required this.angle,
    required this.label,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgDark.withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? AppTheme.secondary.withOpacity(0.3) : AppTheme.bgCardLight,
        ),
      ),
      child: Row(
        children: [
          // Servo visual
          SizedBox(
            width: 60,
            height: 60,
            child: CustomPaint(
              painter: _ServoPainter(
                angle: angle,
                isActive: isActive,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                // Angle display
                Row(
                  children: [
                    const Text('0°', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: angle / 180,
                          backgroundColor: AppTheme.bgCardLight,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isActive ? AppTheme.secondary : AppTheme.textMuted,
                          ),
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text('180°', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                  ],
                ),
                const SizedBox(height: 4),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 300),
                  style: TextStyle(
                    color: isActive ? AppTheme.secondary : AppTheme.textMuted,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  child: Text('${angle.toStringAsFixed(0)}°'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServoPainter extends CustomPainter {
  final double angle;
  final bool isActive;

  _ServoPainter({required this.angle, required this.isActive});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Background circle
    final bgPaint = Paint()
      ..color = AppTheme.bgCardLight
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bgPaint);

    // Arc indicating range
    final arcPaint = Paint()
      ..color = isActive ? AppTheme.secondary.withOpacity(0.2) : AppTheme.textMuted.withOpacity(0.1)
      ..style = PaintingStyle.fill;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      math.pi,
      true,
      arcPaint,
    );

    // Border circle
    final borderPaint = Paint()
      ..color = isActive ? AppTheme.secondary.withOpacity(0.5) : AppTheme.bgCardLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, borderPaint);

    // Arm
    final radians = math.pi - (angle * math.pi / 180);
    final armEnd = Offset(
      center.dx + radius * 0.7 * math.cos(radians),
      center.dy - radius * 0.7 * math.sin(radians),
    );

    final armPaint = Paint()
      ..color = isActive ? AppTheme.secondary : AppTheme.textMuted
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, armEnd, armPaint);

    // Center dot
    final dotPaint = Paint()
      ..color = isActive ? AppTheme.secondary : AppTheme.textMuted
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 5, dotPaint);
  }

  @override
  bool shouldRepaint(_ServoPainter oldDelegate) =>
      oldDelegate.angle != angle || oldDelegate.isActive != isActive;
}
