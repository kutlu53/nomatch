import 'dart:async';
import 'dart:developer' as dev;
import 'dart:math' as math;
import 'package:nomatch/models/orientation_vector_sample.dart';

/// Robust face-to-face detection using fused orientation vectors
/// Validates phones face each other by comparing horizontal projections of forward vectors
class RobustFaceToFaceDetector {
  // Thresholds
  static const double FACE_TO_FACE_THRESHOLD = -0.866; // cos(150°)
  static const double FACE_TO_FACE_ANGLE_DEG = 180.0;
  static const double FACE_TO_FACE_TOLERANCE_DEG = 30.0;
  static const double ANGULAR_STDDEV_THRESHOLD = 10.0; // degrees
  static const double MAGN_MIN = 20.0; // μT
  static const double MAGN_MAX = 80.0; // μT
  static const double MAGN_STDDEV_MAX = 6.0; // μT
  static const double MIN_STABILITY_DURATION = 1.5; // seconds
  static const double BUFFER_DURATION = 2.0; // seconds
  static const int MIN_SAMPLES = 30; // ~20Hz, so 30 samples ≈ 1.5s

  // Ring buffers
  final List<OrientationVectorSample> _localSamples = [];
  final List<OrientationVectorSample> _remoteSamples = [];

  // State
  bool _isSynced = false;
  double _lastDotProduct = 0.0;
  double _lastAngleDegrees = 0.0;
  DateTime? _syncStartTime;

  // Streams
  final StreamController<FaceToFaceEvent> _eventController =
      StreamController<FaceToFaceEvent>.broadcast();
  Stream<FaceToFaceEvent> get events => _eventController.stream;

  RobustFaceToFaceDetector() {
    dev.log('[F2F] 🎯 RobustFaceToFaceDetector initialized');
  }

  /// Add local device sample
  void addLocalSample(OrientationVectorSample sample) {
    _addSample(_localSamples, sample, 'LOCAL');
    _evaluate();
  }

  /// Add remote device sample
  void addRemoteSample(OrientationVectorSample sample) {
    _addSample(_remoteSamples, sample, 'REMOTE');
    _evaluate();
  }

  /// Add sample to buffer with 2-second rolling window
  void _addSample(List<OrientationVectorSample> buffer,
      OrientationVectorSample sample, String label) {
    buffer.add(sample);

    // Keep only last 2 seconds of samples (~40 samples at 20Hz)
    final cutoffTime = DateTime.now().millisecondsSinceEpoch - 2000;
    buffer.retainWhere((s) => s.timestamp >= cutoffTime);

    if (buffer.length % 20 == 0) {
      dev.log('[F2F] 📥 $label: ${buffer.length} samples in buffer');
    }
  }

  /// Main evaluation logic
  void _evaluate() {
    // Need minimum samples from both devices
    if (_localSamples.length < MIN_SAMPLES || _remoteSamples.length < MIN_SAMPLES) {
      if (!_isSynced) return; // Still collecting
      // Already synced, but lost samples - fall back
      _setSynced(false, 'Insufficient samples');
      return;
    }

    // Validate and compute metrics for each device
    final localMetrics = _computeMetrics(_localSamples, 'LOCAL');
    final remoteMetrics = _computeMetrics(_remoteSamples, 'REMOTE');

    if (localMetrics == null || remoteMetrics == null) {
      if (_isSynced) {
        _setSynced(false, 'Metrics validation failed');
      }
      return;
    }

    // Compute face-to-face dot product
    final dot = _dotProduct(
      localMetrics.medianHorizontal,
      remoteMetrics.medianHorizontal,
    );
    final angleDeg = math.acos(dot.clamp(-1.0, 1.0)) * 180 / math.pi;

    _lastDotProduct = dot;
    _lastAngleDegrees = angleDeg;

    dev.log('[F2F] 🔍 Evaluation:');
    dev.log('[F2F]   Local: stable=${localMetrics.isStable}, magHealth=${localMetrics.magnetometerHealthy}');
    dev.log('[F2F]   Remote: stable=${remoteMetrics.isStable}, magHealth=${remoteMetrics.magnetometerHealthy}');
    dev.log('[F2F]   Dot: ${dot.toStringAsFixed(3)}, Angle: ${angleDeg.toStringAsFixed(1)}°');

    // Face-to-face condition: dot <= -0.866 (angle >= 150°) + stability
    final isFaceToFace = dot <= FACE_TO_FACE_THRESHOLD &&
        localMetrics.isStable &&
        remoteMetrics.isStable &&
        localMetrics.magnetometerHealthy &&
        remoteMetrics.magnetometerHealthy;

    if (isFaceToFace) {
      if (!_isSynced) {
        _syncStartTime = DateTime.now();
        dev.log('[F2F] ✅ Face-to-face condition detected, waiting for stability...');
      } else {
        // Check if sustained for minimum duration
        final duration = DateTime.now().difference(_syncStartTime!).inMilliseconds / 1000.0;
        if (duration >= MIN_STABILITY_DURATION) {
          _setSynced(true, 'Face-to-face validated (${duration.toStringAsFixed(1)}s)');
        } else {
          dev.log('[F2F] ⏱️  Holding sync (${duration.toStringAsFixed(1)}s/${MIN_STABILITY_DURATION}s)');
        }
      }
    } else {
      if (_isSynced) {
        _setSynced(false, 'Face-to-face condition lost');
      }
      _syncStartTime = null;
    }
  }

  /// Compute stability metrics for a sample buffer
  DeviceMetrics? _computeMetrics(
    List<OrientationVectorSample> samples,
    String label,
  ) {
    if (samples.isEmpty) return null;

    // Normalize all samples
    final normalized = samples.map((s) => s.normalized()).toList();

    // Project to horizontal and compute median direction
    final horizontalVectors = normalized.map((s) => s.horizontalProjection()).toList();

    if (horizontalVectors.isEmpty) return null;

    // Compute median direction via unit vector averaging
    var sumX = 0.0;
    var sumY = 0.0;
    for (final v in horizontalVectors) {
      sumX += v[0];
      sumY += v[1];
    }
    final medianMag = math.sqrt(sumX * sumX + sumY * sumY);
    if (medianMag < 0.01) return null; // No consensus

    final medianH = [sumX / medianMag, sumY / medianMag];

    // Compute angular standard deviation
    final angles = <double>[];
    for (final v in horizontalVectors) {
      final dot = v[0] * medianH[0] + v[1] * medianH[1];
      final angle = math.acos(dot.clamp(-1.0, 1.0)) * 180 / math.pi;
      angles.add(angle);
    }

    final meanAngle = angles.reduce((a, b) => a + b) / angles.length;
    final variance = angles.map((a) => (a - meanAngle) * (a - meanAngle)).reduce((a, b) => a + b) /
        angles.length;
    final stdDev = math.sqrt(variance);

    // Magnetometer health
    final magValues = samples
        .where((s) => s.magnetometerMagnitude != null)
        .map((s) => s.magnetometerMagnitude!)
        .toList();

    bool magnetometerHealthy = true;
    if (magValues.isNotEmpty) {
      final magMean = magValues.reduce((a, b) => a + b) / magValues.length;
      final magVar = magValues.map((m) => (m - magMean) * (m - magMean)).reduce((a, b) => a + b) /
          magValues.length;
      final magStd = math.sqrt(magVar);

      magnetometerHealthy = magMean >= MAGN_MIN &&
          magMean <= MAGN_MAX &&
          magStd <= MAGN_STDDEV_MAX;

      if (!magnetometerHealthy) {
        dev.log('[F2F]   $label Mag: mean=${magMean.toStringAsFixed(1)}, std=${magStd.toStringAsFixed(1)}');
      }
    }

    final isStable = stdDev <= ANGULAR_STDDEV_THRESHOLD;

    if (!isStable) {
      dev.log('[F2F]   $label Angular StdDev: ${stdDev.toStringAsFixed(1)}° (threshold: $ANGULAR_STDDEV_THRESHOLD°)');
    }

    return DeviceMetrics(
      medianHorizontal: medianH,
      angularStdDev: stdDev,
      isStable: isStable,
      magnetometerHealthy: magnetometerHealthy,
    );
  }

  /// Compute dot product of two horizontal unit vectors
  double _dotProduct(List<double> a, List<double> b) {
    return a[0] * b[0] + a[1] * b[1];
  }

  /// Update sync state
  void _setSynced(bool value, String reason) {
    if (_isSynced == value) return;

    _isSynced = value;
    dev.log('[F2F] ${value ? '✅' : '❌'} Sync: $reason');

    _eventController.add(FaceToFaceEvent(
      isSynced: value,
      dotProduct: _lastDotProduct,
      angleDegrees: _lastAngleDegrees,
      reason: reason,
    ));
  }

  bool get isSynced => _isSynced;

  void reset() {
    _localSamples.clear();
    _remoteSamples.clear();
    _isSynced = false;
    _syncStartTime = null;
    dev.log('[F2F] 🔄 Reset');
  }

  void dispose() {
    _eventController.close();
  }
}

/// Metrics for a single device
class DeviceMetrics {
  final List<double> medianHorizontal; // [x, y] normalized
  final double angularStdDev; // degrees
  final bool isStable;
  final bool magnetometerHealthy;

  DeviceMetrics({
    required this.medianHorizontal,
    required this.angularStdDev,
    required this.isStable,
    required this.magnetometerHealthy,
  });
}

/// Event emitted when sync state changes
class FaceToFaceEvent {
  final bool isSynced;
  final double dotProduct;
  final double angleDegrees;
  final String reason;

  FaceToFaceEvent({
    required this.isSynced,
    required this.dotProduct,
    required this.angleDegrees,
    required this.reason,
  });

  @override
  String toString() =>
      'F2FEvent(synced=$isSynced, angle=${angleDegrees.toStringAsFixed(1)}°, reason=$reason)';
}
