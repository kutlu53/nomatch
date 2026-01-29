import 'dart:developer' as dev;
import 'package:nomatch/services/rotation_vector_processor.dart';

/// Manages face-to-face validation between two devices
class FaceToFaceValidator {
  // Local device data
  Vector3? _localForwardAvg;
  double _localStdDev = 0.0;
  double _localMagnetometerStability = 0.0;
  int _localSampleCount = 0;
  double _localBufferDuration = 0.0;

  // Remote device data (received from peer)
  Vector3? _remoteForwardAvg;
  double _remoteStdDev = 0.0;
  double _remoteMagnetometerStability = 0.0;
  int _remoteSampleCount = 0;
  double _remoteBufferDuration = 0.0;

  bool _hasLocalData = false;
  bool _hasRemoteData = false;

  /// Update local device face-to-face data
  void updateLocalData({
    required Vector3 forwardAverage,
    required double standardDeviation,
    required double magnetometerStability,
    required int sampleCount,
    required double bufferDurationSeconds,
  }) {
    _localForwardAvg = forwardAverage;
    _localStdDev = standardDeviation;
    _localMagnetometerStability = magnetometerStability;
    _localSampleCount = sampleCount;
    _localBufferDuration = bufferDurationSeconds;
    _hasLocalData = true;

    dev.log('[F2F-VAL] 🔵 Local device updated:');
    dev.log('[F2F-VAL]   Forward: $_localForwardAvg');
    dev.log('[F2F-VAL]   StdDev: ${_localStdDev.toStringAsFixed(1)}°');
    dev.log('[F2F-VAL]   Magn Stability: ${_localMagnetometerStability.toStringAsFixed(2)}');
    dev.log('[F2F-VAL]   Samples: $_localSampleCount, Duration: ${_localBufferDuration.toStringAsFixed(2)}s');
  }

  /// Update remote device face-to-face data (from peer via P2P)
  void updateRemoteData({
    required Vector3 forwardAverage,
    required double standardDeviation,
    required double magnetometerStability,
    required int sampleCount,
    required double bufferDurationSeconds,
  }) {
    _remoteForwardAvg = forwardAverage;
    _remoteStdDev = standardDeviation;
    _remoteMagnetometerStability = magnetometerStability;
    _remoteSampleCount = sampleCount;
    _remoteBufferDuration = bufferDurationSeconds;
    _hasRemoteData = true;

    dev.log('[F2F-VAL] 🔴 Remote device updated:');
    dev.log('[F2F-VAL]   Forward: $_remoteForwardAvg');
    dev.log('[F2F-VAL]   StdDev: ${_remoteStdDev.toStringAsFixed(1)}°');
    dev.log('[F2F-VAL]   Magn Stability: ${_remoteMagnetometerStability.toStringAsFixed(2)}');
    dev.log('[F2F-VAL]   Samples: $_remoteSampleCount, Duration: ${_remoteBufferDuration.toStringAsFixed(2)}s');
  }

  /// Validate face-to-face between local and remote
  FaceToFaceResult validate() {
    if (!_hasLocalData || !_hasRemoteData) {
      return FaceToFaceResult(
        isFaceToFace: false,
        dotProduct: 0.0,
        angleRadians: 0.0,
        angleDegrees: 0.0,
        reason: 'Waiting for data: local=$_hasLocalData, remote=$_hasRemoteData',
        samplesCount: 0,
        durationSeconds: 0.0,
        forwardStdDev: 0.0,
        magnetometerStability: 0.0,
      );
    }

    return FaceToFaceDetector.detectBetweenDevices(
      forwardA: _localForwardAvg!,
      forwardB: _remoteForwardAvg!,
      samplesCount: (_localSampleCount + _remoteSampleCount) ~/ 2,
      bufferDurationSeconds:
          (_localBufferDuration + _remoteBufferDuration) / 2,
      stdDevA: _localStdDev,
      stdDevB: _remoteStdDev,
      magnetometerStabilityA: _localMagnetometerStability,
      magnetometerStabilityB: _remoteMagnetometerStability,
    );
  }

  void reset() {
    _hasLocalData = false;
    _hasRemoteData = false;
    dev.log('[F2F-VAL] 🔄 Face-to-face validator reset');
  }

  bool get isReady => _hasLocalData && _hasRemoteData;
}
