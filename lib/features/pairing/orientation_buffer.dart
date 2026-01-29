import 'orientation_models.dart';
import 'circular_math.dart';

/// Ring buffer maintaining last N seconds of orientation samples
class OrientationRingBuffer {
  final List<OrientationSample> _samples = [];
  final int _maxDurationMs;

  OrientationRingBuffer(this._maxDurationMs);

  /// Add sample and prune old entries
  void add(OrientationSample sample) {
    _samples.add(sample);
    _pruneOld(sample.timestampMs);
  }

  /// Get all valid samples (within time window)
  List<OrientationSample> getSamples() => List.unmodifiable(_samples);

  /// Get recent N samples
  List<OrientationSample> getLastN(int n) {
    final start = (_samples.length - n).clamp(0, _samples.length);
    return _samples.sublist(start);
  }

  /// Get samples within time window (milliseconds from latest)
  List<OrientationSample> getSamplesInWindow(int windowMs) {
    if (_samples.isEmpty) return [];
    
    final latest = _samples.last.timestampMs;
    final cutoff = latest - windowMs;
    
    final filtered = _samples.where((s) => s.timestampMs >= cutoff).toList();
    return filtered;
  }

  /// Calculate statistics for current window
  WindowStats? getStats({required int windowMs}) {
    final samples = getSamplesInWindow(windowMs);
    if (samples.length < 2) return null;
    
    final yaws = samples.map((s) => s.yawDeg).toList();
    final mags = samples.map((s) => s.magStrengthUT).toList();
    final accs = samples.map((s) => s.accuracy).toList();
    
    final medianYaw = CircularMath.circularMedian(yaws);
    final yawStd = CircularMath.circularStd(yaws);
    
    final avgMag = mags.reduce((a, b) => a + b) / mags.length;
    final magStd = CircularMath.linearStd(mags);
    final minAcc = accs.reduce((a, b) => a < b ? a : b);
    
    return WindowStats(
      medianYaw: medianYaw,
      yawStd: yawStd,
      avgMagStrength: avgMag,
      magStrengthStd: magStd,
      minAccuracy: minAcc,
      sampleCount: samples.length,
      durationMs: samples.last.timestampMs - samples.first.timestampMs,
    );
  }

  /// Clear all samples
  void clear() => _samples.clear();

  /// Get buffer size
  int get length => _samples.length;

  void _pruneOld(int currentTimeMs) {
    final cutoff = currentTimeMs - _maxDurationMs;
    _samples.removeWhere((s) => s.timestampMs < cutoff);
  }
}
