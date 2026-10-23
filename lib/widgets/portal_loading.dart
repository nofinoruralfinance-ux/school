import 'dart:math' as math;

import 'package:flutter/material.dart';

Future<T> withPortalLoading<T>(
  BuildContext context, {
  required String label,
  required Future<T> Function() action,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final loadingDialog = showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: PortalLoadingState(
        label: label,
        detail: '',
        size: 72,
      ),
    ),
  );

  await WidgetsBinding.instance.endOfFrame;
  try {
    return await action();
  } finally {
    if (navigator.mounted) navigator.pop();
    await loadingDialog;
  }
}

class PortalOrbitLoader extends StatefulWidget {
  const PortalOrbitLoader({
    super.key,
    this.size = 112,
    this.semanticsLabel = 'Loading',
    this.accentColor = const Color(0xFF14CBE8),
  });

  final double size;
  final String? semanticsLabel;
  final Color accentColor;

  @override
  State<PortalOrbitLoader> createState() => _PortalOrbitLoaderState();
}

class _PortalOrbitLoaderState extends State<PortalOrbitLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: widget.semanticsLabel,
      liveRegion: true,
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _PortalOrbitPainter(
              progress: _controller.value,
              trackColor: colors.outlineVariant.withValues(alpha: .42),
              accentColor: widget.accentColor,
              glowColor: colors.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class PortalLoadingState extends StatelessWidget {
  const PortalLoadingState({
    super.key,
    this.label = 'Loading',
    this.detail = 'SECURE FINANCE PORTAL',
    this.size = 104,
  });

  final String label;
  final String detail;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Card(
        key: const Key('portal-loading-state'),
        margin: const EdgeInsets.all(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PortalOrbitLoader(size: size, semanticsLabel: label),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: textTheme.titleSmall?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (detail.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  detail,
                  textAlign: TextAlign.center,
                  style: textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PortalOrbitPainter extends CustomPainter {
  const _PortalOrbitPainter({
    required this.progress,
    required this.trackColor,
    required this.accentColor,
    required this.glowColor,
  });

  final double progress;
  final Color trackColor;
  final Color accentColor;
  final Color glowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * .43;
    final scale = size.shortestSide / 112;
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, 3 * scale)
      ..isAntiAlias = true;
    canvas.drawCircle(center, radius, trackPaint);

    final segmentPaint = Paint()
      ..color = accentColor.withValues(alpha: .75)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1, 4 * scale)
      ..isAntiAlias = true;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      progress * math.pi * 2 - math.pi / 2,
      math.pi * .52,
      false,
      segmentPaint,
    );

    const dotCount = 28;
    final phase = progress * dotCount;
    for (var index = 0; index < dotCount; index++) {
      final angle = (index / dotCount) * math.pi * 2 - math.pi / 2;
      final position = center +
          Offset(
              math.cos(angle) * radius * .64, math.sin(angle) * radius * .64);
      final distance = (index - phase) % dotCount;
      final trailDistance = math.min(distance, dotCount - distance);
      final intensity = (1 - trailDistance / 10).clamp(0.12, 1.0).toDouble();
      final dotPaint = Paint()
        ..color = Color.lerp(trackColor, accentColor, intensity)!
        ..isAntiAlias = true;
      if (intensity > .78) {
        dotPaint
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * scale)
          ..color = accentColor.withValues(alpha: .45);
        canvas.drawCircle(position, 5.2 * scale, dotPaint);
        dotPaint
          ..maskFilter = null
          ..color = accentColor;
      }
      canvas.drawCircle(position, (2.2 + intensity * 1.25) * scale, dotPaint);
    }

    final centerPaint = Paint()
      ..color = glowColor.withValues(alpha: .10)
      ..isAntiAlias = true;
    canvas.drawCircle(center, radius * .31, centerPaint);
    final centerDot = Paint()
      ..color = accentColor.withValues(alpha: .82)
      ..isAntiAlias = true;
    canvas.drawCircle(center, 3 * scale, centerDot);
  }

  @override
  bool shouldRepaint(covariant _PortalOrbitPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      trackColor != oldDelegate.trackColor ||
      accentColor != oldDelegate.accentColor ||
      glowColor != oldDelegate.glowColor;
}
