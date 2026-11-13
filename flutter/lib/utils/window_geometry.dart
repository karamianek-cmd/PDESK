import 'dart:math' as math;
import 'dart:ui';

Rect? fitWindowBoundsToWorkAreas(Rect bounds, Iterable<Rect> workAreas) {
  Rect? workArea;
  double largestOverlap = -1;
  for (final area in workAreas) {
    final intersection = bounds.intersect(area);
    final overlap = intersection.isEmpty
        ? 0.0
        : intersection.width * intersection.height;
    if (overlap > largestOverlap) {
      workArea = area;
      largestOverlap = overlap;
    }
  }
  if (workArea == null) return null;

  final width = math.min(bounds.width, workArea.width);
  final height = math.min(bounds.height, workArea.height);
  return Rect.fromLTWH(
    bounds.left.clamp(workArea.left, workArea.right - width).toDouble(),
    bounds.top.clamp(workArea.top, workArea.bottom - height).toDouble(),
    width,
    height,
  );
}
