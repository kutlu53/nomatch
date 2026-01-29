import 'dart:async';
import 'package:flutter/services.dart';
import 'orientation_models.dart';

/// Manages native sensor fusion and provides Dart stream of orientation samples
class OrientationSensorStream {
  static const platform = MethodChannel('com.nomatch/orientation_fusion');
  static const eventChannelName = 'com.nomatch/orientation_samples';
  static late final EventChannel _eventChannel;

  StreamSubscription<OrientationSample>? _subscription;
  Stream<OrientationSample>? _stream;

  OrientationSensorStream() {
    _eventChannel = EventChannel(eventChannelName);
  }

  /// Get stream of orientation samples from native sensor fusion
  /// Handles both iOS (CMMotionManager) and Android (Rotation Vector)
  Stream<OrientationSample> getSampleStream() {
    if (_stream != null) return _stream!;

    _stream = _eventChannel.receiveBroadcastStream().map((dynamic data) {
      if (data is Map) {
        return OrientationSample(
          yawDeg: (data['yawDeg'] as num).toDouble(),
          magStrengthUT: (data['magStrengthUT'] as num).toDouble(),
          accuracy: (data['accuracy'] as num).toInt(),
          timestampMs: (data['timestampMs'] as num).toInt(),
        );
      }
      throw FormatException('Invalid orientation sample: $data');
    }).asBroadcastStream();

    return _stream!;
  }

  /// Start native sensor fusion
  Future<void> start() async {
    try {
      await platform.invokeMethod<void>(
        'startOrientationFusion',
        eventChannelName,
      );
      print('[ORIENT-Dart] ✅ Orientation sensor fusion started');
    } catch (e) {
      print('[ORIENT-Dart] ❌ Error starting orientation fusion: $e');
      rethrow;
    }
  }

  /// Stop native sensor fusion
  Future<void> stop() async {
    try {
      await platform.invokeMethod<void>('stopOrientationFusion');
      print('[ORIENT-Dart] ✅ Orientation sensor fusion stopped');
    } catch (e) {
      print('[ORIENT-Dart] ❌ Error stopping orientation fusion: $e');
    }
  }

  /// Listen to samples (convenience method)
  StreamSubscription<OrientationSample> listen(
    void Function(OrientationSample) onData, {
    void Function(Object, StackTrace)? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return getSampleStream().listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  /// Cleanup
  Future<void> dispose() async {
    await _subscription?.cancel();
    await stop();
  }
}
