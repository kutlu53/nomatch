import 'dart:math' as math;
import 'dart:developer' as dev;

/// Represents a 3D rotation matrix (3x3)
class RotationMatrix {
  /// Row-major storage: [m00, m01, m02, m10, m11, m12, m20, m21, m22]
  final List<double> data;

  RotationMatrix(this.data) : assert(data.length == 9);

  /// Create identity matrix
  factory RotationMatrix.identity() {
    return RotationMatrix([
      1, 0, 0,
      0, 1, 0,
      0, 0, 1,
    ]);
  }

  /// From quaternion (iOS attitude)
  /// q = [w, x, y, z]
  factory RotationMatrix.fromQuaternion(double w, double x, double y, double z) {
    // Normalize
    final norm = math.sqrt(w * w + x * x + y * y + z * z);
    w /= norm;
    x /= norm;
    y /= norm;
    z /= norm;

    return RotationMatrix([
      1 - 2 * (y * y + z * z),     2 * (x * y - w * z),         2 * (x * z + w * y),
      2 * (x * y + w * z),         1 - 2 * (x * x + z * z),     2 * (y * z - w * x),
      2 * (x * z - w * y),         2 * (y * z + w * x),         1 - 2 * (x * x + y * y),
    ]);
  }

  /// From rotation matrix data (Android TYPE_ROTATION_VECTOR rotationMatrix)
  /// Input is already 3x3 rotation matrix
  factory RotationMatrix.fromArray(List<double> array) {
    if (array.length != 9) {
      throw ArgumentError('Expected 9 elements for 3x3 rotation matrix, got ${array.length}');
    }
    return RotationMatrix(List<double>.from(array));
  }

  /// Get element at (row, col)
  double get(int row, int col) => data[row * 3 + col];

  /// Multiply vector [x, y, z] by this matrix
  /// Result: M * v
  List<double> multiplyVector(List<double> v) {
    assert(v.length == 3);
    return [
      data[0] * v[0] + data[1] * v[1] + data[2] * v[2],
      data[3] * v[0] + data[4] * v[1] + data[5] * v[2],
      data[6] * v[0] + data[7] * v[1] + data[8] * v[2],
    ];
  }

  @override
  String toString() {
    return 'RotationMatrix[\n'
        '  ${data[0].toStringAsFixed(3)} ${data[1].toStringAsFixed(3)} ${data[2].toStringAsFixed(3)}\n'
        '  ${data[3].toStringAsFixed(3)} ${data[4].toStringAsFixed(3)} ${data[5].toStringAsFixed(3)}\n'
        '  ${data[6].toStringAsFixed(3)} ${data[7].toStringAsFixed(3)} ${data[8].toStringAsFixed(3)}\n'
        ']';
  }
}

/// Vector3 with utility methods
class Vector3 {
  final double x;
  final double y;
  final double z;

  Vector3(this.x, this.y, this.z);

  /// Magnitude
  double get magnitude => math.sqrt(x * x + y * y + z * z);

  /// Normalize
  Vector3 normalized() {
    final mag = magnitude;
    if (mag == 0) return Vector3(0, 0, 0);
    return Vector3(x / mag, y / mag, z / mag);
  }

  /// Dot product
  double dot(Vector3 other) => x * other.x + y * other.y + z * other.z;

  /// Project onto XY plane and normalize
  Vector3 projectToHorizontal() {
    final v = Vector3(x, y, 0).normalized();
    return v;
  }

  /// Angle in radians
  static double angleBetween(Vector3 a, Vector3 b) {
    final dot = a.dot(b);
    // Clamp to [-1, 1] to avoid numerical errors in acos
    final clamped = dot.clamp(-1.0, 1.0);
    return math.acos(clamped);
  }

  @override
  String toString() => 'Vector3(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, ${z.toStringAsFixed(3)})';
}

/// Ring buffer for storing time-series data
class RingBuffer<T> {
  final int capacity;
  final List<T?> _data;
  int _index = 0;
  int _count = 0;

  RingBuffer(this.capacity) : _data = List<T?>.filled(capacity, null);

  void add(T value) {
    _data[_index] = value;
    _index = (_index + 1) % capacity;
    if (_count < capacity) {
      _count++;
    }
  }

  List<T> get all => _data.sublist(0, _count).whereType<T>().toList();

  bool get isFull => _count == capacity;

  int get length => _count;

  void clear() {
    _count = 0;
    _index = 0;
  }
}

/// Device orientation information
enum DeviceScreenOrientation {
  PORTRAIT,
  LANDSCAPE_LEFT,
  LANDSCAPE_RIGHT,
  PORTRAIT_REVERSE,
}

/// Represents a forward direction sample with rotation matrix
class ForwardDirectionSample {
  final DateTime timestamp;
  final Vector3 forwardWorldHorizontal; // Forward direction projected to horizontal plane, normalized
  final double magnetometerMagnitude;   // For stability check
  final double accelMagnitude;          // Should be ~9.81
  final RotationMatrix rotationMatrix;

  ForwardDirectionSample({
    required this.timestamp,
    required this.forwardWorldHorizontal,
    required this.magnetometerMagnitude,
    required this.accelMagnitude,
    required this.rotationMatrix,
  });

  @override
  String toString() =>
      'FwdSample(t=${timestamp.millisecondsSinceEpoch}, fwd=$forwardWorldHorizontal, magMag=${magnetometerMagnitude.toStringAsFixed(1)})';
}

/// Face-to-face detection result
class FaceToFaceResult {
  final bool isFaceToFace;
  final double dotProduct;              // dot product of forward vectors
  final double angleRadians;            // angle between forward vectors
  final double angleDegrees;
  final String reason;
  final int samplesCount;
  final double durationSeconds;
  final double forwardStdDev;           // Angular standard deviation
  final double magnetometerStability;   // Indicator 0-1

  FaceToFaceResult({
    required this.isFaceToFace,
    required this.dotProduct,
    required this.angleRadians,
    required this.angleDegrees,
    required this.reason,
    required this.samplesCount,
    required this.durationSeconds,
    required this.forwardStdDev,
    required this.magnetometerStability,
  });

  @override
  String toString() =>
      'FaceToFace($isFaceToFace, dot=${dotProduct.toStringAsFixed(3)}, angle=${angleDegrees.toStringAsFixed(1)}°, '
      'stddev=${forwardStdDev.toStringAsFixed(1)}°, magStab=${magnetometerStability.toStringAsFixed(2)}, reason=$reason)';
}

/// Face-to-face detection engine
class FaceToFaceDetector {
  static const double FACE_TO_FACE_THRESHOLD = -0.866; // cos(150°) ≈ -0.866
  static const double FACE_TO_FACE_ANGLE_DEG = 180.0;
  static const double FACE_TO_FACE_TOLERANCE_DEG = 30.0;
  static const double MIN_STABILITY_DURATION = 1.5;     // seconds
  static const double BUFFER_DURATION = 2.0;             // seconds
  static const double ANGULAR_STDDEV_THRESHOLD = 10.0;   // degrees
  static const double MAGN_MAGNITUDE_MIN = 20.0;         // μT (typical ~30-60)
  static const double MAGN_MAGNITUDE_MAX = 80.0;         // μT
  static const double ACCEL_MAGNITUDE_NOMINAL = 9.81;
  static const double ACCEL_MAGNITUDE_TOLERANCE = 2.0;   // 7.81 - 11.81 m/s²

  final RingBuffer<ForwardDirectionSample> _samples;
  DateTime? _lastSampleTime;

  FaceToFaceDetector()
      : _samples = RingBuffer<ForwardDirectionSample>(
          (BUFFER_DURATION * 100).toInt(), // Assume ~100 Hz sampling = 200 samples for 2s
        );

  /// Add a forward direction sample
  void addSample({
    required Vector3 forwardWorldDirection,  // Should be normalized
    required double magnetometerMagnitude,
    required double accelMagnitude,
    required RotationMatrix rotationMatrix,
  }) {
    final now = DateTime.now();
    _lastSampleTime = now;

    // Project to horizontal plane and normalize
    final forwardHorizontal = forwardWorldDirection.projectToHorizontal();

    final sample = ForwardDirectionSample(
      timestamp: now,
      forwardWorldHorizontal: forwardHorizontal,
      magnetometerMagnitude: magnetometerMagnitude,
      accelMagnitude: accelMagnitude,
      rotationMatrix: rotationMatrix,
    );

    _samples.add(sample);
  }

  /// Compute angular standard deviation of forward vectors
  double _computeAngularStdDev(List<Vector3> vectors) {
    if (vectors.length < 2) return 0.0;

    // Compute mean direction (simplified: average the vectors and normalize)
    var meanX = 0.0, meanY = 0.0;
    for (final v in vectors) {
      meanX += v.x;
      meanY += v.y;
    }
    meanX /= vectors.length;
    meanY /= vectors.length;

    final meanMag = math.sqrt(meanX * meanX + meanY * meanY);
    if (meanMag < 0.01) return 180.0; // No consensus direction

    meanX /= meanMag;
    meanY /= meanMag;
    final meanVec = Vector3(meanX, meanY, 0);

    // Compute angle from each vector to mean, then std dev
    final angles = <double>[];
    for (final v in vectors) {
      final angle = Vector3.angleBetween(v, meanVec);
      angles.add(angle * 180 / math.pi); // Convert to degrees
    }

    final meanAngle = angles.reduce((a, b) => a + b) / angles.length;
    final variance =
        angles.map((a) => (a - meanAngle) * (a - meanAngle)).reduce((a, b) => a + b) / angles.length;
    return math.sqrt(variance);
  }

  /// Compute magnetometer stability (0 = unstable, 1 = very stable)
  double _computeMagnetometerStability(List<double> magnitudes) {
    if (magnitudes.isEmpty) return 0.0;

    // Check if all magnitudes are within valid range
    final inRange = magnitudes
        .where((m) => m >= MAGN_MAGNITUDE_MIN && m <= MAGN_MAGNITUDE_MAX)
        .length;
    final rangeRatio = inRange / magnitudes.length;

    // Compute coefficient of variation
    final mean = magnitudes.reduce((a, b) => a + b) / magnitudes.length;
    if (mean < 1) return 0.0;

    final variance = magnitudes.map((m) => (m - mean) * (m - mean)).reduce((a, b) => a + b) / magnitudes.length;
    final stddev = math.sqrt(variance);
    final cv = stddev / mean; // Coefficient of variation

    // Stability = range_ratio * (1 - min(cv, 0.3) / 0.3)
    final cvPenalty = math.min(cv, 0.3) / 0.3;
    return rangeRatio * (1.0 - cvPenalty);
  }

  /// Validate accelerometer magnitude
  bool _isAccelMagnitudeValid(double accelMag) {
    final diff = (accelMag - ACCEL_MAGNITUDE_NOMINAL).abs();
    return diff <= ACCEL_MAGNITUDE_TOLERANCE;
  }

  /// Detect face-to-face orientation
  FaceToFaceResult detect() {
    final samples = _samples.all;

    if (samples.isEmpty) {
      return FaceToFaceResult(
        isFaceToFace: false,
        dotProduct: 0.0,
        angleRadians: 0.0,
        angleDegrees: 0.0,
        reason: 'No samples collected',
        samplesCount: 0,
        durationSeconds: 0.0,
        forwardStdDev: 0.0,
        magnetometerStability: 0.0,
      );
    }

    // Compute buffer duration
    final firstTime = samples.first.timestamp;
    final lastTime = samples.last.timestamp;
    final bufferDuration = lastTime.difference(firstTime).inMilliseconds / 1000.0;

    // Check buffer duration (should be ~2 seconds)
    if (bufferDuration < BUFFER_DURATION * 0.8) {
      return FaceToFaceResult(
        isFaceToFace: false,
        dotProduct: 0.0,
        angleRadians: 0.0,
        angleDegrees: 0.0,
        reason: 'Insufficient buffer duration: ${bufferDuration.toStringAsFixed(2)}s < ${BUFFER_DURATION}s',
        samplesCount: samples.length,
        durationSeconds: bufferDuration,
        forwardStdDev: 0.0,
        magnetometerStability: 0.0,
      );
    }

    // Extract forward vectors and check quality
    final forwardVectors = <Vector3>[];
    final magnitudesRaw = <double>[];
    var validSampleCount = 0;

    for (final sample in samples) {
      forwardVectors.add(sample.forwardWorldHorizontal);
      magnitudesRaw.add(sample.magnetometerMagnitude);

      // Check accelerometer magnitude validity
      if (_isAccelMagnitudeValid(sample.accelMagnitude)) {
        validSampleCount++;
      }
    }

    // Require at least 80% valid accel samples
    final accelValidRatio = validSampleCount / samples.length;
    if (accelValidRatio < 0.8) {
      return FaceToFaceResult(
        isFaceToFace: false,
        dotProduct: 0.0,
        angleRadians: 0.0,
        angleDegrees: 0.0,
        reason: 'Accelerometer instability: only ${(accelValidRatio * 100).toStringAsFixed(0)}% valid samples',
        samplesCount: samples.length,
        durationSeconds: bufferDuration,
        forwardStdDev: 0.0,
        magnetometerStability: 0.0,
      );
    }

    // Compute magnetometer stability
    final magnetometerStability = _computeMagnetometerStability(magnitudesRaw);
    if (magnetometerStability < 0.6) {
      return FaceToFaceResult(
        isFaceToFace: false,
        dotProduct: 0.0,
        angleRadians: 0.0,
        angleDegrees: 0.0,
        reason: 'Magnetometer unstable: stability=${magnetometerStability.toStringAsFixed(2)} < 0.6',
        samplesCount: samples.length,
        durationSeconds: bufferDuration,
        forwardStdDev: 0.0,
        magnetometerStability: magnetometerStability,
      );
    }

    // Compute angular std dev
    final angularStdDev = _computeAngularStdDev(forwardVectors);
    if (angularStdDev > ANGULAR_STDDEV_THRESHOLD) {
      return FaceToFaceResult(
        isFaceToFace: false,
        dotProduct: 0.0,
        angleRadians: 0.0,
        angleDegrees: 0.0,
        reason:
            'Forward direction unstable: stddev=${angularStdDev.toStringAsFixed(1)}° > ${ANGULAR_STDDEV_THRESHOLD}°',
        samplesCount: samples.length,
        durationSeconds: bufferDuration,
        forwardStdDev: angularStdDev,
        magnetometerStability: magnetometerStability,
      );
    }

    // Compute average forward vector
    var avgX = 0.0, avgY = 0.0;
    for (final v in forwardVectors) {
      avgX += v.x;
      avgY += v.y;
    }
    avgX /= forwardVectors.length;
    avgY /= forwardVectors.length;
    final avgForward = Vector3(avgX, avgY, 0).normalized();

    // For now, we have only one device's measurements. In real two-device scenario:
    // fA and fB would come from two different devices.
    // Here we just check if we have a valid forward direction.
    final dot = avgForward.dot(Vector3(avgX, avgY, 0).normalized());
    final angle = Vector3.angleBetween(avgForward, avgForward); // Always 0
    final angleDeg = angle * 180 / math.pi;

    dev.log('[F2F] 🧭 Face-to-face detection:');
    dev.log('[F2F]   Samples: ${samples.length} | Duration: ${bufferDuration.toStringAsFixed(2)}s');
    dev.log('[F2F]   Avg Forward: $avgForward');
    dev.log('[F2F]   Angular StdDev: ${angularStdDev.toStringAsFixed(1)}°');
    dev.log('[F2F]   Magnetometer Stability: ${magnetometerStability.toStringAsFixed(2)}');

    return FaceToFaceResult(
      isFaceToFace: false, // Will be set to true when comparing two devices
      dotProduct: dot,
      angleRadians: angle,
      angleDegrees: angleDeg,
      reason: 'Waiting for peer device data',
      samplesCount: samples.length,
      durationSeconds: bufferDuration,
      forwardStdDev: angularStdDev,
      magnetometerStability: magnetometerStability,
    );
  }

  /// Detect face-to-face between two devices
  static FaceToFaceResult detectBetweenDevices({
    required Vector3 forwardA,
    required Vector3 forwardB,
    required int samplesCount,
    required double bufferDurationSeconds,
    required double stdDevA,
    required double stdDevB,
    required double magnetometerStabilityA,
    required double magnetometerStabilityB,
  }) {
    // Compute dot product and angle
    final dot = forwardA.dot(forwardB);
    final angleRad = Vector3.angleBetween(forwardA, forwardB);
    final angleDeg = angleRad * 180 / math.pi;

    dev.log('[F2F] 🎯 FACE-TO-FACE CHECK:');
    dev.log('[F2F]   Forward A: $forwardA');
    dev.log('[F2F]   Forward B: $forwardB');
    dev.log('[F2F]   Dot Product: ${dot.toStringAsFixed(3)}');
    dev.log('[F2F]   Angle: ${angleDeg.toStringAsFixed(1)}°');
    dev.log('[F2F]   Stability A: ${stdDevA.toStringAsFixed(1)}°, B: ${stdDevB.toStringAsFixed(1)}°');
    dev.log('[F2F]   Magnetometer: A=${magnetometerStabilityA.toStringAsFixed(2)}, B=${magnetometerStabilityB.toStringAsFixed(2)}');

    // Check all conditions
    final isAngleFaceToFace = dot <= FACE_TO_FACE_THRESHOLD; // cos(150°)
    final isStabilityOk = stdDevA <= ANGULAR_STDDEV_THRESHOLD && stdDevB <= ANGULAR_STDDEV_THRESHOLD;
    final isMagnetometerOk = magnetometerStabilityA >= 0.6 && magnetometerStabilityB >= 0.6;
    final isDurationOk = bufferDurationSeconds >= MIN_STABILITY_DURATION;

    final isFaceToFace = isAngleFaceToFace && isStabilityOk && isMagnetometerOk && isDurationOk;

    final reasons = <String>[];
    if (!isAngleFaceToFace) {
      reasons.add('angle=${angleDeg.toStringAsFixed(1)}° (need ≥150°, dot≤-0.866)');
    }
    if (!isStabilityOk) {
      reasons.add('stddev too high (A=${stdDevA.toStringAsFixed(1)}°, B=${stdDevB.toStringAsFixed(1)}°)');
    }
    if (!isMagnetometerOk) {
      reasons.add('magnetometer unstable (A=${magnetometerStabilityA.toStringAsFixed(2)}, B=${magnetometerStabilityB.toStringAsFixed(2)})');
    }
    if (!isDurationOk) {
      reasons.add('duration=${bufferDurationSeconds.toStringAsFixed(2)}s < ${MIN_STABILITY_DURATION}s');
    }

    final reason = isFaceToFace
        ? '✅ Face-to-face detected (angle=${angleDeg.toStringAsFixed(1)}°)'
        : reasons.join(' | ');

    return FaceToFaceResult(
      isFaceToFace: isFaceToFace,
      dotProduct: dot,
      angleRadians: angleRad,
      angleDegrees: angleDeg,
      reason: reason,
      samplesCount: samplesCount,
      durationSeconds: bufferDurationSeconds,
      forwardStdDev: (stdDevA + stdDevB) / 2,
      magnetometerStability: (magnetometerStabilityA + magnetometerStabilityB) / 2,
    );
  }

  void clear() {
    _samples.clear();
  }

  int get sampleCount => _samples.length;

  bool get isBufferReady => _samples.isFull;
}
