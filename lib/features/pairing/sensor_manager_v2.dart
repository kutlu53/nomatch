import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter/services.dart';
import 'package:nomatch/models/orientation_vector_sample.dart';
import 'package:nomatch/services/robust_face_to_face_detector.dart';

/// V2 Sensor Manager using fused orientation vectors for face-to-face detection
class SensorManagerV2 {
  static const platform = EventChannel('com.nomatch/orientation_vector');

  final RobustFaceToFaceDetector faceToFaceDetector = RobustFaceToFaceDetector();

  StreamSubscription? _orientationVectorSub;
  bool _isActive = false;

  /// Start listening to orientation vector stream
  Future<void> start() async {
    if (_isActive) return;
    _isActive = true;

    _orientationVectorSub = platform.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          _handleOrientationVector(event);
        }
      },
      onError: (error) {
        dev.log('[SENS-V2] ❌ Orientation vector error: $error');
      },
    );

    dev.log('[SENS-V2] ✅ Started listening to orientation vectors');
  }

  /// Handle incoming orientation vector from platform
  void _handleOrientationVector(Map<dynamic, dynamic> data) {
    try {
      final sample = OrientationVectorSample(
        fx: (data['fx'] as num).toDouble(),
        fy: (data['fy'] as num).toDouble(),
        fz: (data['fz'] as num).toDouble(),
        magnetometerMagnitude: data['magMag'] != null ? (data['magMag'] as num).toDouble() : null,
        magnetometerAccuracy: data['magAccuracy'] as int?,
        timestamp: data['timestamp'] as int,
      );

      // Add to local detector
      faceToFaceDetector.addLocalSample(sample);
    } catch (e) {
      dev.log('[SENS-V2] Error parsing orientation vector: $e');
    }
  }

  /// Add a remote sample (received from peer via P2P)
  void addRemoteSample(OrientationVectorSample sample) {
    faceToFaceDetector.addRemoteSample(sample);
  }

  /// Get face-to-face sync stream
  Stream<FaceToFaceEvent> get faceToFaceEvents => faceToFaceDetector.events;

  /// Check if currently synced
  bool get isSynced => faceToFaceDetector.isSynced;

  /// Reset detectors
  void reset() {
    faceToFaceDetector.reset();
  }

  /// Stop listening
  void stop() {
    if (!_isActive) return;
    _isActive = false;

    _orientationVectorSub?.cancel();
    _orientationVectorSub = null;

    dev.log('[SENS-V2] ⏹️  Stopped');
  }

  /// Dispose resources
  void dispose() {
    stop();
    faceToFaceDetector.dispose();
  }
}
