import 'package:flutter_test/flutter_test.dart';
import 'package:nomatch/services/rotation_vector_processor.dart';

void main() {
  group('Face-to-Face Detection System', () {
    late FaceToFaceDetector detector;

    setUp(() {
      detector = FaceToFaceDetector();
    });

    test('Vector3: magnitude calculation', () {
      final v = Vector3(3, 4, 0);
      expect(v.magnitude, closeTo(5.0, 0.001));
    });

    test('Vector3: normalization', () {
      final v = Vector3(2, 0, 0).normalized();
      expect(v.x, closeTo(1.0, 0.001));
      expect(v.y, closeTo(0.0, 0.001));
      expect(v.z, closeTo(0.0, 0.001));
    });

    test('Vector3: dot product', () {
      final a = Vector3(1, 0, 0);
      final b = Vector3(0, 1, 0);
      expect(a.dot(b), closeTo(0.0, 0.001));

      final c = Vector3(1, 0, 0);
      final d = Vector3(1, 0, 0);
      expect(c.dot(d), closeTo(1.0, 0.001));
    });

    test('Vector3: angle between vectors (0°)', () {
      final a = Vector3(1, 0, 0);
      final b = Vector3(1, 0, 0);
      final angleRad = Vector3.angleBetween(a, b);
      final angleDeg = angleRad * 180 / 3.14159265359;
      expect(angleDeg, closeTo(0.0, 1.0));
    });

    test('Vector3: angle between vectors (90°)', () {
      final a = Vector3(1, 0, 0);
      final b = Vector3(0, 1, 0);
      final angleRad = Vector3.angleBetween(a, b);
      final angleDeg = angleRad * 180 / 3.14159265359;
      expect(angleDeg, closeTo(90.0, 1.0));
    });

    test('Vector3: angle between vectors (180°)', () {
      final a = Vector3(1, 0, 0);
      final b = Vector3(-1, 0, 0);
      final angleRad = Vector3.angleBetween(a, b);
      final angleDeg = angleRad * 180 / 3.14159265359;
      expect(angleDeg, closeTo(180.0, 1.0));
    });

    test('Vector3: horizontal projection', () {
      final v = Vector3(1, 2, 5).projectToHorizontal();
      expect(v.z, closeTo(0.0, 0.001));
      expect(v.magnitude, closeTo(1.0, 0.001)); // Should be normalized
    });

    test('RotationMatrix: quaternion to matrix conversion', () {
      // Identity quaternion (1, 0, 0, 0) should give identity matrix
      final m = RotationMatrix.fromQuaternion(1, 0, 0, 0);
      expect(m.data[0], closeTo(1.0, 0.01)); // m00
      expect(m.data[4], closeTo(1.0, 0.01)); // m11
      expect(m.data[8], closeTo(1.0, 0.01)); // m22
    });

    test('RotationMatrix: vector multiplication', () {
      // Identity matrix multiplied by vector should return same vector
      final m = RotationMatrix.identity();
      final v = [1.0, 2.0, 3.0];
      final result = m.multiplyVector(v);
      expect(result[0], closeTo(1.0, 0.001));
      expect(result[1], closeTo(2.0, 0.001));
      expect(result[2], closeTo(3.0, 0.001));
    });

    test('RingBuffer: basic operations', () {
      final buffer = RingBuffer<int>(3);
      buffer.add(1);
      buffer.add(2);
      buffer.add(3);
      
      expect(buffer.length, equals(3));
      expect(buffer.isFull, isTrue);
      expect(buffer.all, equals([1, 2, 3]));
    });

    test('RingBuffer: overflow behavior', () {
      final buffer = RingBuffer<int>(3);
      buffer.add(1);
      buffer.add(2);
      buffer.add(3);
      buffer.add(4); // Overwrites 1
      buffer.add(5); // Overwrites 2
      
      expect(buffer.length, equals(3));
      expect(buffer.all, equals([3, 4, 5]));
    });

    test('FaceToFaceDetector: detect between devices (face-to-face 180°)', () {
      // Device A looking east, Device B looking west (opposite)
      final forwardA = Vector3(1, 0, 0);
      final forwardB = Vector3(-1, 0, 0);
      
      final result = FaceToFaceDetector.detectBetweenDevices(
        forwardA: forwardA,
        forwardB: forwardB,
        samplesCount: 200,
        bufferDurationSeconds: 2.0,
        stdDevA: 5.0,
        stdDevB: 5.0,
        magnetometerStabilityA: 0.8,
        magnetometerStabilityB: 0.8,
      );
      
      expect(result.isFaceToFace, isTrue);
      expect(result.angleDegrees, closeTo(180.0, 1.0));
      expect(result.dotProduct, closeTo(-1.0, 0.01));
    });

    test('FaceToFaceDetector: detect between devices (not face-to-face, wrong angle)', () {
      // Device A looking east, Device B looking north (90° angle)
      final forwardA = Vector3(1, 0, 0);
      final forwardB = Vector3(0, 1, 0);
      
      final result = FaceToFaceDetector.detectBetweenDevices(
        forwardA: forwardA,
        forwardB: forwardB,
        samplesCount: 200,
        bufferDurationSeconds: 2.0,
        stdDevA: 5.0,
        stdDevB: 5.0,
        magnetometerStabilityA: 0.8,
        magnetometerStabilityB: 0.8,
      );
      
      expect(result.isFaceToFace, isFalse);
      expect(result.angleDegrees, closeTo(90.0, 1.0));
    });

    test('FaceToFaceDetector: reject unstable forward direction', () {
      final forwardA = Vector3(1, 0, 0);
      final forwardB = Vector3(-1, 0, 0);
      
      final result = FaceToFaceDetector.detectBetweenDevices(
        forwardA: forwardA,
        forwardB: forwardB,
        samplesCount: 200,
        bufferDurationSeconds: 2.0,
        stdDevA: 15.0, // Too high!
        stdDevB: 5.0,
        magnetometerStabilityA: 0.8,
        magnetometerStabilityB: 0.8,
      );
      
      expect(result.isFaceToFace, isFalse);
      expect(result.reason, contains('stddev too high'));
    });

    test('FaceToFaceDetector: reject unstable magnetometer', () {
      final forwardA = Vector3(1, 0, 0);
      final forwardB = Vector3(-1, 0, 0);
      
      final result = FaceToFaceDetector.detectBetweenDevices(
        forwardA: forwardA,
        forwardB: forwardB,
        samplesCount: 200,
        bufferDurationSeconds: 2.0,
        stdDevA: 5.0,
        stdDevB: 5.0,
        magnetometerStabilityA: 0.4, // Too low!
        magnetometerStabilityB: 0.8,
      );
      
      expect(result.isFaceToFace, isFalse);
      expect(result.reason, contains('magnetometer unstable'));
    });

    test('FaceToFaceDetector: reject short duration', () {
      final forwardA = Vector3(1, 0, 0);
      final forwardB = Vector3(-1, 0, 0);
      
      final result = FaceToFaceDetector.detectBetweenDevices(
        forwardA: forwardA,
        forwardB: forwardB,
        samplesCount: 200,
        bufferDurationSeconds: 1.0, // Too short (< 1.5s)
        stdDevA: 5.0,
        stdDevB: 5.0,
        magnetometerStabilityA: 0.8,
        magnetometerStabilityB: 0.8,
      );
      
      expect(result.isFaceToFace, isFalse);
      expect(result.reason, contains('duration'));
    });

    test('FaceToFaceDetector: tolerance range (150-180°)', () {
      // 165° should be accepted (within ±30° of 180°)
      final forwardA = Vector3(1, 0, 0);
      // 165° angle = slightly less than 180°
      final angle165 = 165.0 * 3.14159265359 / 180.0;
      final forwardB = Vector3(
        (1.0 * angle165.cos() - 0.0 * angle165.sin()).toDouble(),
        (1.0 * angle165.sin() + 0.0 * angle165.cos()).toDouble(),
        0,
      ).normalized();
      
      final result = FaceToFaceDetector.detectBetweenDevices(
        forwardA: forwardA,
        forwardB: forwardB,
        samplesCount: 200,
        bufferDurationSeconds: 2.0,
        stdDevA: 5.0,
        stdDevB: 5.0,
        magnetometerStabilityA: 0.8,
        magnetometerStabilityB: 0.8,
      );
      
      expect(result.isFaceToFace, isTrue);
      expect(result.angleDegrees, closeTo(165.0, 2.0));
    });

    test('FaceToFaceDetector: reject if angle > 180-30 (outside tolerance)', () {
      // 140° should be rejected (> 150° is outside tolerance)
      final forwardA = Vector3(1, 0, 0);
      final angle140 = 140.0 * 3.14159265359 / 180.0;
      final forwardB = Vector3(
        (1.0 * angle140.cos() - 0.0 * angle140.sin()).toDouble(),
        (1.0 * angle140.sin() + 0.0 * angle140.cos()).toDouble(),
        0,
      ).normalized();
      
      final result = FaceToFaceDetector.detectBetweenDevices(
        forwardA: forwardA,
        forwardB: forwardB,
        samplesCount: 200,
        bufferDurationSeconds: 2.0,
        stdDevA: 5.0,
        stdDevB: 5.0,
        magnetometerStabilityA: 0.8,
        magnetometerStabilityB: 0.8,
      );
      
      expect(result.isFaceToFace, isFalse);
    });
  });
}
