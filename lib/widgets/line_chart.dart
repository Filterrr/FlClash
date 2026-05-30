import 'dart:ui';

import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';

class Point {
  final double x;
  final double y;

  const Point(this.x, this.y);

  @override
  String toString() {
    return 'Point{x: $x, y: $y}';
  }
}

class LineChart extends StatefulWidget {
  final List<Point> points;
  final Color color;
  final double height;
  final Duration duration;

  const LineChart({
    super.key,
    required this.points,
    required this.color,
    this.duration = const Duration(milliseconds: 0),
    required this.height,
  });

  @override
  State<LineChart> createState() => _LineChartState();
}

typedef ComputedPath = Path Function(Size size);

class _LineChartState extends State<LineChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  List<Point> _prevPoints = [];
  List<Point> _points = [];
  List<Point> _prevRenderPoints = [];
  List<Point> _renderPoints = [];
  Path? _cachedPrevFullPath;
  Path? _cachedNextFullPath;
  Size? _cachedSize;
  int _pointsHash = 0;

  static final Paint _paint = Paint()
    ..strokeWidth = 2.0
    ..style = PaintingStyle.stroke;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _points = widget.points;
    _prevPoints = _points;
    _pointsHash = _computePointsHash(_points);
    _prevRenderPoints = _normalizePoints(_prevPoints);
    _renderPoints = _prevRenderPoints;
  }

  static int _computePointsHash(List<Point> pts) {
    return Object.hashAll(pts);
  }

  static List<Point> _normalizePoints(List<Point> points) {
    if (points.isEmpty) return [];
    double maxX = points[0].x;
    double minX = points[0].x;
    double maxY = points[0].y;
    double minY = points[0].y;
    for (final point in points) {
      if (point.x > maxX) maxX = point.x;
      if (point.x < minX) minX = point.x;
      if (point.y > maxY) maxY = point.y;
      if (point.y < minY) minY = point.y;
    }
    final double xRange = maxX - minX;
    final double yRange = maxY - minY;
    final bool xFlat = xRange == 0;
    final bool yFlat = yRange == 0;
    return List.generate(points.length, (i) {
      final e = points[i];
      final x = xFlat ? 0.5 : (e.x - minX) / xRange;
      final y = yFlat ? 0.5 : (e.y - minY) / yRange;
      return Point(x, y);
    });
  }

  static Path _buildPath(List<Point> points, Size size) {
    final path = Path()
      ..moveTo(points[0].x * size.width, (1 - points[0].y) * size.height);
    for (var i = 1; i < points.length - 1; i++) {
      final nextPoint = points[i + 1];
      final currentPoint = points[i];
      final midX = (currentPoint.x + nextPoint.x) / 2;
      final midY = (currentPoint.y + nextPoint.y) / 2;
      path.quadraticBezierTo(
        currentPoint.x * size.width,
        (1 - currentPoint.y) * size.height,
        midX * size.width,
        (1 - midY) * size.height,
      );
    }
    path.lineTo(
      points.last.x * size.width,
      (1 - points.last.y) * size.height,
    );
    return path;
  }

  @override
  void didUpdateWidget(LineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.points != _points) {
      final newHash = _computePointsHash(widget.points);
      if (newHash != _pointsHash) {
        _prevPoints = _points;
        _prevRenderPoints = _renderPoints;
        _points = widget.points;
        _pointsHash = newHash;
        _renderPoints = _normalizePoints(_points);
        _cachedPrevFullPath = null;
        _cachedNextFullPath = null;
        if (globalState.isAppPaused) {
          _controller.value = 1.0;
        } else {
          _controller.forward(from: 0);
        }
      }
    }
  }

  void _drawChart(Canvas canvas, Size size) {
    if (_prevRenderPoints.isEmpty || _renderPoints.isEmpty) return;

    if (_cachedSize != size) {
      _cachedPrevFullPath = null;
      _cachedNextFullPath = null;
      _cachedSize = size;
    }

    final progress = _controller.value;

    _paint.color = widget.color;

    if (progress >= 1.0) {
      _cachedNextFullPath ??= _buildPath(_renderPoints, size);
      canvas.drawPath(_cachedNextFullPath!, _paint);
      return;
    }

    _cachedPrevFullPath ??= _buildPath(_prevRenderPoints, size);
    _cachedNextFullPath ??= _buildPath(_renderPoints, size);

    final prevMetric = _cachedPrevFullPath!.computeMetrics().first;
    final nextMetric = _cachedNextFullPath!.computeMetrics().first;
    final targetLength = prevMetric.length +
        (nextMetric.length - prevMetric.length) * progress;
    final extractedPath =
        nextMetric.extractPath(0, targetLength.clamp(0.0, nextMetric.length));
    canvas.drawPath(extractedPath, _paint);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller.view,
        builder: (_, __) {
          return CustomPaint(
            painter: _LineChartPainter(
              painter: this,
              pointsHash: _pointsHash,
              progress: _controller.value,
              color: widget.color,
            ),
            isComplex: true,
            willChange: true,
            child: SizedBox(
              height: widget.height,
              width: double.infinity,
            ),
          );
        },
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final _LineChartState painter;
  final int pointsHash;
  final double progress;
  final Color color;

  _LineChartPainter({
    required this.painter,
    required this.pointsHash,
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    painter._drawChart(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return pointsHash != oldDelegate.pointsHash ||
        progress != oldDelegate.progress ||
        color != oldDelegate.color;
  }
}