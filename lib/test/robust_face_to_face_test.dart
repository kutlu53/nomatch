import 'package:flutter_test/flutter_test.dart';
import 'package:nomatch/models/orientation_vector_sample.dart';
import 'package:nomatch/services/robust_face_to_face_detector.dart';
import 'dart:math' as math;

void main() {
  group('RobustFaceToFaceDetector', () {
    late RobustFaceToFaceDetector detector;

    setUp(() {
      detector = RobustFaceToFaceDetector();
    });

    tearDown(() {
      detector.dispose();
    });

    test('initializes in not-synced state', () {
      expect(detector.isSynced, isFalse);
    });

    test('detects face-to-face at 180° with stable signals', () async {
      final now = DateTime.now().millisecondsSinceEpoch;

      // Simulate 40 samples at 20Hz = 2 seconds
      for (int i = 0; i < 40; i++) {
        final t = now - (40 - i) * 50;

        // Local device: forward = [1, 0, 0] (pointing east)
        detector.addLocalSample(OrientationVectorSample(
          fx: 1.0,
          fy: 0.0,
          fz: 0.0,
          magnetometerMagnitude: 40.0,
          magnetometerAccuracy: 2,
          timestamp: t,
        ));

        // Remote device: forward = [-1, 0, 0] (pointing west, opposite)
        detector.addRemoteSample(OrientationVectorSample(
          fx: -1.0,
          fy: 0.0,
          fz: 0.0,
          magnetometerMagnitude: 40.0,
          magnetometerAccuracy: 2,
          timestamp: t,
        ));
      }

      // Give time for evaluation
      await Future.delayed(Duration(milliseconds: 100));

      // Should be synced: dot = [1,0] · [-1,0] = -1.0 <= -0.866
      expect(detector.isSynced, isTrue);
    });

    test('rejects when angle is not 180°', () async {
      final now = DateTime.now().millisecondsSinceEpoch;

      for (int i = 0; i < 40; i++) {
        final t = now - (40 - i) * 50;

        // Both pointing roughly the same direction (bad)
        detector.addLocalSample(OrientationVectorSample(
          fx: 1.0,
          fy: 0.0,
          fz: 0.0,
          magnetometerMagnitude: 40.0,
          magnetometerAccuracy: 2,
          timestamp: t,
        ));

        detector.addRemoteSample(OrientationVectorSample(
          fx: 0.9, // ~25° apart, not 180°
          fy: 0.4,
          fz: 0.0,
          magnetometerMagnitude: 40.0,
          magnetometerAccuracy: 2,
          timestamp: t,
        ));
      }

      await Future.delayed(Duration(milliseconds: 100));

      // Should not be synced: dot ≈ 0.9 > -0.866
      expect(detector.isSynced, isFalse);
    });

    test('rejects when magnetometer is unstable', () async {
      final now = DateTime.now().millisecondsSinceEpoch;

      for (int i = 0; i < 40; i++) {
        final t = now - (40 - i) * 50;

        detector.addLocalSample(OrientationVectorSample(
          fx: 1.0,
          fy: 0.0,
          fz: 0.0,
          magnetometerMagnitude: 40.0,
          magnetometerAccuracy: 2,
          timestamp: t,
        ));

        // Magnetometer out of range or unstable
        detector.addRemoteSample(OrientationVectorSample(
          fx: -1.0,
          fy: 0.0,
          fz: 0.0,
          magnetometerMagnitude: 5.0, // Too low!
          magnetometerAccuracy: 0, // Low accuracy
          timestamp: t,
        ));
      }

      await Future.delayed(Duration(milliseconds: 100));

      expect(detector.isSynced, isFalse);
    });

    test('rejects when signal is noisy (high angular stddev)', () async {
      final now = DateTime.now().millisecondsSinceEpoch;

      for (int i = 0; i < 40; i++) {
        final t = now - (40 - i) * 50;

        // Add large jitter to local device
        final jitterX = math.sin(i * 0.5);
        final jitterY = math.cos(i * 0.3) * 0.5;

        detector.addLocalSample(OrientationVectorSample(
          fx: 1.0 + jitterX * 0.3,
          fy: jitterY * 0.3,
          fz: 0.0,
          magnetometerMagnitude: 40.0,
          magnetometerAccuracy: 2,
          timestamp: t,
        ));

        // Opposite but also noisy
        detector.addRemoteSample(OrientationVectorSample(
          fx: -1.0 - jitterX * 0.3,
          fy: -jitterY * 0.3,
          fz: 0.0,
          magnetometerMagnitude: 40.0,
          magnetometerAccuracy: 2,
          timestamp: t,
        ));
      }

      await Future.delayed(Duration(milliseconds: 100));

      // Should not sync due to high noise
      expect(detector.isSynced, isFalse);
    });

    test('requires sustained 1.5s of valid condition', () async {
      final now = DateTime.now().millisecondsSinceEpoch;

      // First 20 samples (1 second) - valid
      for (int i = 0; i < 20; i++) {
        final t = now - (20 - i) * 50;

        detector.addLocalSample(OrientationVectorSample(
          fx: 1.0,
          fy: 0.0,
          fz: 0.0,
          magnetometerMagnitude: 40.0,
          magnetometerAccuracy: 2,
          timestamp: t,
        ));

        detector.addRemoteSample(OrientationVectorSample(
          fx: -1.0,
          fy: 0.0,
          fz: 0.0,
          magnetometerMagnitude: 40.0,
          magnetometerAccuracy: 2,
          timestamp: t,
        ));
      }

      await Future.delayed(Duration(milliseconds: 100));

      // Should not be synced yet (< 1.5s)
      expect(detector.isSynced, isFalse);

      // Next 10 samples (0.5s more) → total 1.5s
      for (int i = 20; i < 30; i++) {
        final t = now - (30 - i) * 50;

        detector.addLocalSample(OrientationVectorSample(
          fx: 1.0,
          fy: 0.0,
          fz: 0.0,
          magnetometerMagnitude: 40.0,
          magnetometerAccuracy: 2,
          timestamp: t,
        ));

        detector.addRemoteSample(OrientationVectorSample(
          fx: -1.0,
          fy: 0.0,
          fz: 0.0,
          magnetometerMagnitude: 40.0,
          magnetometerAccuracy: 2,
          timestamp: t,
        ));
      }

      await Future.delayed(Duration(milliseconds: 100));

      // Should now be synced
      expect(detector.isSynced, isTrue);
    });

    test('loses sync when condition breaks', () async {
      final now = DateTime.now().millisecondsSinceEpoch;

      // Establish sync first (40 samples = 2s)
      for (int i = 0; i < 40; i++) {
        final t = now - (40 - i) * 50;

        detector.addLocalSample(OrientationVectorSample(
          fx: 1.0,
          fy: 0.0,
          fz: 0.0,
          magnetometerMagnitude: 40.0,
          magnetometerAccuracy: 2,
          timestamp: t,
        ));

        detector.addRemoteSample(OrientationVectorSample(
          fx: -1.0,
          fy: 0.0,
          fz: 0.0,
          magnetometerMagnitude: 40.0,
          magnetometerAccuracy: 2,
          timestamp: t,
        ));
      }

      await Future.delayed(Duration(milliseconds: 100));
      expect(detector.isSynced, isTrue);

      // Now break the condition: device rotates away
      for (int i = 0; i < 30; i++) {
        final t = now + (i * 50);

        detector.addLocalSample(OrientationVectorSample(
          fx: 0.707, // 45° rotation
          fy: 0.707,
          fz: 0.0,
          magnetometerMagnitude: 40.0,
          magnetometerAccuracy: 2,
          timestamp: t,
        ));

        detector.addRemoteSample(OrientationVectorSample(
          fx: -1.0, // Still opposite
          fy: 0.0,
          fz: 0.0,
          magnetometerMagnitude: 40.0,
          magnetometerAccuracy: 2,
          timestamp: t,
        ));
      }

      await Future.delayed(Duration(milliseconds: 100));

      // Should have lost sync
      expect(detector.isSynced, isFalse);
    });

    test('handles 180° ± 30° tolerance correctly', () async {
      final now = DateTime.now().millisecondsSinceEpoch;

      // Test at 150° (edge of tolerance)
      final angle150Rad = 150 * math.pi / 180;
      final fx2 = math.cos(angle150Rad);
      final fy2 = math.sin(angle150Rad);

      for (int i = 0; i < 40; i++) {
        final t = now - (40 - i) * 50;

        detector.addLocalSample(OrientationVectorSample(
          fx: 1.0,
          fy: 0.0,
          fz: 0.0,
          magnetometerMagnitude: 40.0,
          magnetometerAccuracy: 2,
          timestamp: t,
        ));

        detector.addRemoteSample(OrientationVectorSample(
          fx: fx2,
          fy: fy2,
          fz: 0.0,
          magnetometerMagnitude: 40.0,
          magnetometerAccuracy: 2,
          timestamp: t,
        ));
      }

      await Future.delayed(Duration(milliseconds: 100));

      // dot = 1*cos(150°) + 0*sin(150°) = cos(150°) ≈ -0.866
      // Should be at threshold, might sync
      // (depends on stability, but 150° is accepted)
      expect(detector.isSynced, isTrue);
    });
  });

  group('OrientationVectorSample', () {
    test('normalizes forward vector', () {
      final sample = OrientationVectorSample(
        fx: 3.0,
        fy: 4.0,
        fz: 0.0,
        timestamp: 0,
      );

      final norm = sample.normalized();
      expect(norm.fx, closeTo(0.6, 0.01));
      expect(norm.fy, closeTo(0.8, 0.01));
      expect(norm.fz, closeTo(0.0, 0.01));
    });

    test('projects to horizontal plane', () {
      final sample = OrientationVectorSample(
        fx: 1.0,
        fy: 1.0,
        fz: 10.0, // Large Z component
        timestamp: 0,
      );

      final proj = sample.horizontalProjection();
      expect(proj.length, equals(2));
      expect(proj[0], closeTo(0.707, 0.01)); // 1/√2
      expect(proj[1], closeTo(0.707, 0.01)); // 1/√2
    });
  });
}
