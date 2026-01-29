import 'dart:async';
import 'dart:developer' as dev;

/// Connection health checker for P2P BLE connections
/// 
/// Monitors connection quality and provides recovery mechanisms
class ConnectionHealthChecker {
  DateTime? _lastHeartbeatTime;
  int _missedHeartbeats = 0;
  DateTime? _lastPingTime;
  bool _waitingForPong = false;
  
  /// Update heartbeat timestamp
  void onHeartbeatReceived() {
    _lastHeartbeatTime = DateTime.now();
    _missedHeartbeats = 0;
    dev.log('[HEALTH] Heartbeat received - connection healthy');
  }
  
  /// Update pong timestamp
  void onPongReceived() {
    if (_waitingForPong && _lastPingTime != null) {
      final rtt = DateTime.now().difference(_lastPingTime!);
      dev.log('[HEALTH] Pong received - RTT: ${rtt.inMilliseconds}ms');
      _waitingForPong = false;
    }
  }
  
  /// Check if connection is healthy based on heartbeat
  bool isHealthy() {
    if (_lastHeartbeatTime == null) {
      dev.log('[HEALTH] No heartbeat received yet');
      return false;
    }
    
    final elapsed = DateTime.now().difference(_lastHeartbeatTime!);
    
    // If no heartbeat for 5 seconds, connection is unhealthy
    if (elapsed > const Duration(seconds: 5)) {
      _missedHeartbeats++;
      dev.log('[HEALTH] Connection unhealthy - no heartbeat for ${elapsed.inSeconds}s (missed: $_missedHeartbeats)');
      return false;
    }
    
    return true;
  }
  
  /// Perform ping-pong test to measure connection quality
  /// Returns true if connection is responsive (RTT < 2s)
  Future<bool> pingTest() async {
    dev.log('[HEALTH] Starting ping test...');
    _lastPingTime = DateTime.now();
    _waitingForPong = true;
    
    // Wait for pong (max 2 seconds)
    await Future.delayed(const Duration(seconds: 2));
    
    if (_waitingForPong) {
      // Pong not received
      dev.log('[HEALTH] ❌ Ping test FAILED - no pong received');
      _waitingForPong = false;
      return false;
    }
    
    // Pong received
    final rtt = DateTime.now().difference(_lastPingTime!);
    final success = rtt < const Duration(seconds: 2);
    
    if (success) {
      dev.log('[HEALTH] ✅ Ping test PASSED - RTT: ${rtt.inMilliseconds}ms');
    } else {
      dev.log('[HEALTH] ❌ Ping test FAILED - RTT too high: ${rtt.inMilliseconds}ms');
    }
    
    return success;
  }
  
  /// Get connection quality score (0-100)
  int getQualityScore() {
    if (_lastHeartbeatTime == null) return 0;
    
    final elapsed = DateTime.now().difference(_lastHeartbeatTime!);
    final seconds = elapsed.inSeconds;
    
    if (seconds == 0) return 100;
    if (seconds == 1) return 90;
    if (seconds == 2) return 70;
    if (seconds == 3) return 50;
    if (seconds == 4) return 30;
    if (seconds >= 5) return 0;
    
    return 0;
  }
  
  /// Get connection status description
  String getStatusDescription() {
    final score = getQualityScore();
    
    if (score >= 90) return 'Excellent';
    if (score >= 70) return 'Good';
    if (score >= 50) return 'Fair';
    if (score >= 30) return 'Poor';
    return 'Disconnected';
  }
  
  /// Check if reconnection is needed
  bool needsReconnection() {
    return _missedHeartbeats >= 3;
  }
  
  /// Reset health checker state
  void reset() {
    _lastHeartbeatTime = null;
    _missedHeartbeats = 0;
    _lastPingTime = null;
    _waitingForPong = false;
    dev.log('[HEALTH] Health checker reset');
  }
}
