import 'orientation_models.dart';
import 'orientation_buffer.dart';
import 'circular_math.dart';

/// Detects face-to-face orientation between two devices
/// Based on tilt-compensated yaw with stability validation
class FaceToFaceDetector {
  /// Configuration parameters
  final FaceToFaceConfig config;

  /// Ring buffers for each device
  late final OrientationRingBuffer bufferA;
  late final OrientationRingBuffer bufferB;

  /// Timestamp when current stable face-to-face condition started (ms)
  int? _stableStartTimeMs;

  FaceToFaceDetector({FaceToFaceConfig? config})
      : config = config ?? FaceToFaceConfig() {
    bufferA = OrientationRingBuffer(config.bufferDurationMs);
    bufferB = OrientationRingBuffer(config.bufferDurationMs);
  }

  /// Update buffers and check face-to-face condition
  /// Returns detection result
  FaceToFaceResult updateAndCheck({
    required OrientationSample sampleA,
    required OrientationSample sampleB,
  }) {
    // Add samples to buffers
    bufferA.add(sampleA);
    bufferB.add(sampleB);

    // Get statistics for stability windows
    final statsA = bufferA.getStats(windowMs: config.windowMs);
    final statsB = bufferB.getStats(windowMs: config.windowMs);

    // Check if both windows are valid
    final validA = statsA != null &&
        statsA.isValid(
          maxYawStd: config.maxYawStdDeg,
          minMagStrength: config.minMagStrengthUT,
          maxMagStrength: config.maxMagStrengthUT,
          maxMagStrengthStd: config.maxMagStrengthStd,
          minAccuracy: config.minAccuracy,
        );

    final validB = statsB != null &&
        statsB.isValid(
          maxYawStd: config.maxYawStdDeg,
          minMagStrength: config.minMagStrengthUT,
          maxMagStrength: config.maxMagStrengthUT,
          maxMagStrengthStd: config.maxMagStrengthStd,
          minAccuracy: config.minAccuracy,
        );

    // Calculate yaw difference if both valid
    double yawDiff = 0;
    bool isFaceToFace = false;

    if (validA && validB) {
      yawDiff = CircularMath.shortestDistance(statsA!.medianYaw, statsB!.medianYaw);
      isFaceToFace = CircularMath.areApproxEqual(
        yawDiff,
        180,
        config.toleranceDeg,
      );
    }

    // Track stable duration
    int stableDurationMs = 0;
    if (isFaceToFace && validA && validB) {
      if (_stableStartTimeMs == null) {
        _stableStartTimeMs = sampleA.timestampMs;
      }
      stableDurationMs = sampleA.timestampMs - _stableStartTimeMs!;
    } else {
      _stableStartTimeMs = null;
    }

    return FaceToFaceResult(
      bothValid: validA && validB,
      yawDifference: yawDiff,
      isFaceToFace: isFaceToFace,
      stableDurationMs: stableDurationMs,
      statsA: statsA,
      statsB: statsB,
    );
  }

  /// Check if face-to-face condition is stable and ready for connection
  bool isReadyToConnect(FaceToFaceResult result) {
    return result.isFaceToFace &&
        result.bothValid &&
        result.stableDurationMs >= config.requiredStableDurationMs;
  }

  /// Reset detector state
  void reset() {
    bufferA.clear();
    bufferB.clear();
    _stableStartTimeMs = null;
  }

  /// Get current stability duration (ms)
  int getStableDurationMs() => _stableStartTimeMs != null
      ? DateTime.now().millisecondsSinceEpoch - _stableStartTimeMs!
      : 0;
}

/// Configuration for face-to-face detection
class FaceToFaceConfig {
  /// Maximum buffer duration (ms) - keeps 2+ seconds
  final int bufferDurationMs;

  /// Analysis window duration (ms) - must be < bufferDurationMs
  final int windowMs;

  /// Maximum yaw std dev (degrees) for valid window
  final double maxYawStdDeg;

  /// Magnetic field strength range (µT)
  final double minMagStrengthUT;
  final double maxMagStrengthUT;

  /// Maximum std dev of magnetic strength (µT)
  final double maxMagStrengthStd;

  /// Minimum sensor accuracy (0=low, 1=medium, 2=high)
  final int minAccuracy;

  /// Tolerance for 180° detection (degrees)
  final double toleranceDeg;

  /// Required stable duration before readyToConnect (ms)
  final int requiredStableDurationMs;

  FaceToFaceConfig({
    this.bufferDurationMs = 3000,      // 3 seconds
    this.windowMs = 2000,              // 2 second analysis window
    this.maxYawStdDeg = 8.0,           // ±8° stability
    this.minMagStrengthUT = 20,        // Field too weak
    this.maxMagStrengthUT = 80,        // Field too strong (nearby magnet)
    this.maxMagStrengthStd = 6.0,      // Fluctuation
    this.minAccuracy = 1,              // Medium or better
    this.toleranceDeg = 30.0,          // ±30° around 180°
    this.requiredStableDurationMs = 1500, // 1.5 seconds stable
  });

  /// Relaxed config (more lenient) for noisy environments
  factory FaceToFaceConfig.relaxed() {
    return FaceToFaceConfig(
      maxYawStdDeg: 15.0,
      maxMagStrengthStd: 10.0,
      minAccuracy: 0,
      toleranceDeg: 40.0,
      requiredStableDurationMs: 2000,
    );
  }

  /// Strict config for high-precision environments
  factory FaceToFaceConfig.strict() {
    return FaceToFaceConfig(
      maxYawStdDeg: 5.0,
      maxMagStrengthStd: 4.0,
      minAccuracy: 2,
      toleranceDeg: 20.0,
      requiredStableDurationMs: 1000,
    );
  }

  @override
  String toString() =>
      'FaceToFaceConfig(buffer=${bufferDurationMs}ms, window=${windowMs}ms, yawStd<${maxYawStdDeg}°, mag=[${minMagStrengthUT},${maxMagStrengthUT}]µT, std<${maxMagStrengthStd}µT, acc>=$minAccuracy, tol=±${toleranceDeg}°, stable>=${requiredStableDurationMs}ms)';
}
