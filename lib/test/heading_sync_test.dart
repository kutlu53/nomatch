import 'package:flutter_test/flutter_test.dart';
import '../models/heading_models.dart';
import '../services/heading_normalizer.dart';
import '../services/phone_orientation_validator.dart';
import '../services/hybrid_phone_validator.dart';
import '../services/heading_sync_calibration.dart';

void main() {
  group('HeadingNormalizer Tests', () {
    test('normalizeHeading: 370 → 10', () {
      expect(HeadingNormalizer.normalizeHeading(370), 10.0);
    });

    test('normalizeHeading: -90 → 270', () {
      expect(HeadingNormalizer.normalizeHeading(-90), 270.0);
    });

    test('getAngularDifference: 10 to 350 = 20', () {
      expect(HeadingNormalizer.getAngularDifference(10, 350), 20.0);
    });

    test('getAngularDifference: 350 to 10 = -20', () {
      expect(HeadingNormalizer.getAngularDifference(350, 10), -20.0);
    });

    test('isHeading180Degrees: 45 vs 225 = true', () {
      expect(
        HeadingNormalizer.isHeading180Degrees(
          45,
          225,
          tolerance: 30.0,
        ),
        true,
      );
    });

    test('isHeading180Degrees: 45 vs 135 = false', () {
      expect(
        HeadingNormalizer.isHeading180Degrees(
          45,
          135,
          tolerance: 30.0,
        ),
        false,
      );
    });
  });

  group('PhoneOrientationValidator Tests', () {
    test('detectHeadOrientation: (0.2, 0.1, 9.7) = HEAD_UP', () {
      final result = PhoneOrientationValidator.detectHeadOrientation(0.2, 0.1, 9.7);
      expect(result.orientation, HeadOrientation.HEAD_UP);
      expect(result.isLevel, true);
    });

    test('detectHeadOrientation: (0.2, 0.1, -9.8) = HEAD_DOWN', () {
      final result = PhoneOrientationValidator.detectHeadOrientation(0.2, 0.1, -9.8);
      expect(result.orientation, HeadOrientation.HEAD_DOWN);
      expect(result.isLevel, true);
    });

    test('detectHeadOrientation: (4.5, 0.1, 8.0) = TILTED', () {
      final result = PhoneOrientationValidator.detectHeadOrientation(4.5, 0.1, 8.0);
      expect(result.orientation, HeadOrientation.TILTED);
      expect(result.isLevel, false);
    });

    test('isHeadOrientationOpposite: HEAD_UP vs HEAD_DOWN = true', () {
      expect(
        PhoneOrientationValidator.isHeadOrientationOpposite(
          HeadOrientation.HEAD_UP,
          HeadOrientation.HEAD_DOWN,
        ),
        true,
      );
    });

    test('isHeadOrientationOpposite: HEAD_UP vs HEAD_UP = false', () {
      expect(
        PhoneOrientationValidator.isHeadOrientationOpposite(
          HeadOrientation.HEAD_UP,
          HeadOrientation.HEAD_UP,
        ),
        false,
      );
    });

    test('areZAxisOpposite: 9.7 vs -9.8 = true', () {
      expect(
        PhoneOrientationValidator.areZAxisOpposite(
          9.7,
          -9.8,
          tolerance: 3.0,
        ),
        true,
      );
    });

    test('areZAxisOpposite: 9.7 vs 9.8 = false', () {
      expect(
        PhoneOrientationValidator.areZAxisOpposite(
          9.7,
          9.8,
          tolerance: 3.0,
        ),
        false,
      );
    });

    test('areBothLevel: true', () {
      final accel1 = AccelerometerReading(x: 0.2, y: 0.1, z: 9.7);
      final accel2 = AccelerometerReading(x: -0.1, y: 0.3, z: -9.8);
      expect(PhoneOrientationValidator.areBothLevel(accel1, accel2), true);
    });

    test('areBothLevel: false (accel1 tilted)', () {
      final accel1 = AccelerometerReading(x: 4.5, y: 0.1, z: 9.7);
      final accel2 = AccelerometerReading(x: -0.1, y: 0.3, z: -9.8);
      expect(PhoneOrientationValidator.areBothLevel(accel1, accel2), false);
    });
  });

  group('HeadingSyncCalibration Tests', () {
    test('Calibration success: 180°', () {
      final calib = HeadingSyncCalibration();
      
      // 5 okuma ekle
      final h1Values = [45.0, 45.1, 45.0, 44.9, 45.1];
      final h2Values = [225.0, 225.1, 225.0, 224.9, 225.1];
      
      for (int i = 0; i < h1Values.length; i++) {
        calib.recordCalibrationReading(h1Values[i], h2Values[i]);
      }
      
      // Analiz et
      final success = calib.analyzeCalibration(180.0);
      expect(success, true);
      expect(calib.isCalibrated, true);
      expect(calib.getCalibrationOffset()!, closeTo(180.0, 1.0));
    });

    test('Calibration fail: 90° (not 180°)', () {
      final calib = HeadingSyncCalibration();
      
      // Yanlış fark
      final h1Values = [45.0, 45.1, 45.0, 44.9, 45.1];
      final h2Values = [135.0, 135.1, 135.0, 134.9, 135.1]; // 90° fark!
      
      for (int i = 0; i < h1Values.length; i++) {
        calib.recordCalibrationReading(h1Values[i], h2Values[i]);
      }
      
      final success = calib.analyzeCalibration(180.0);
      expect(success, false);
      expect(calib.isCalibrated, false);
    });
  });

  group('HybridPhoneValidator Tests', () {
    test('Test 1: ✅ Perfect Alignment', () {
      final validator = HybridPhoneValidator();
      
      final accel1 = AccelerometerReading(x: 0.2, y: 0.1, z: 9.7);
      final accel2 = AccelerometerReading(x: -0.1, y: 0.3, z: -9.8);
      
      final result = validator.validatePhoneOrientation(
        heading1: 45.0,
        heading2: 225.0,
        accel1: accel1,
        accel2: accel2,
      );
      
      expect(result.isSynced, true);
      expect(result.scorePoints, 4);
      expect(result.confidence, closeTo(1.0, 0.01));
    });

    test('Test 2: ❌ Wrong Heading (90°)', () {
      final validator = HybridPhoneValidator();
      
      final accel1 = AccelerometerReading(x: 0.2, y: 0.1, z: 9.7);
      final accel2 = AccelerometerReading(x: -0.1, y: 0.3, z: -9.8);
      
      final result = validator.validatePhoneOrientation(
        heading1: 45.0,
        heading2: 135.0,  // 90° fark, not 180°
        accel1: accel1,
        accel2: accel2,
      );
      
      expect(result.isSynced, false);
      expect(result.scorePoints, 3);  // Only orientation + z-axis + level
    });

    test('Test 3: ❌ Z-Axis Same Sign', () {
      final validator = HybridPhoneValidator();
      
      final accel1 = AccelerometerReading(x: 0.2, y: 0.1, z: 9.7);
      final accel2 = AccelerometerReading(x: -0.1, y: 0.3, z: 9.8); // Same sign!
      
      final result = validator.validatePhoneOrientation(
        heading1: 45.0,
        heading2: 225.0,
        accel1: accel1,
        accel2: accel2,
      );
      
      expect(result.isSynced, false);
      expect(result.scorePoints, 3);  // heading + level + ?, but no z-axis
    });

    test('Test 4: ❌ Tilted', () {
      final validator = HybridPhoneValidator();
      
      final accel1 = AccelerometerReading(x: 4.5, y: 0.1, z: 8.0);  // Tilted!
      final accel2 = AccelerometerReading(x: -0.1, y: 0.3, z: -9.8);
      
      final result = validator.validatePhoneOrientation(
        heading1: 45.0,
        heading2: 225.0,
        accel1: accel1,
        accel2: accel2,
      );
      
      expect(result.isSynced, false);
      expect(result.scorePoints, 3);  // No level check
    });

    test('Test 5: ✅ Failure Recovery', () {
      final validator = HybridPhoneValidator();
      final accel1 = AccelerometerReading(x: 0.2, y: 0.1, z: 9.7);
      final accel2 = AccelerometerReading(x: -0.1, y: 0.3, z: -9.8);
      
      // 2 başarısız
      for (int i = 0; i < 2; i++) {
        validator.validatePhoneOrientation(
          heading1: 45.0,
          heading2: 135.0,  // Wrong
          accel1: accel1,
          accel2: accel2,
        );
      }
      
      expect(validator.failureCount, 2);
      expect(validator.failuresBeforeDisconnect, 1);
      
      // 1 başarılı (sıfırla)
      final result = validator.validatePhoneOrientation(
        heading1: 45.0,
        heading2: 225.0,
        accel1: accel1,
        accel2: accel2,
      );
      
      expect(result.isSynced, true);
      expect(validator.failureCount, 0);
    });
  });
}
