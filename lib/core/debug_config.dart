/// Debug configuration for the app
/// ═══════════════════════════════════════════════════════════════════
/// ⚠️ PRODUCTION: Set [kProductionMode] to true before release!
/// ═══════════════════════════════════════════════════════════════════

/// 🚀 PRODUCTION MODE: Set to true for release builds
/// This disables ALL debug logging for maximum performance
const bool kProductionMode = true; // ✅ Set to true before release

class DebugConfig {
  DebugConfig._();
  
  /// Master switch - respects kProductionMode
  static bool get enabled => !kProductionMode;
  
  /// BLE/Connection logs
  static const bool _bleLogging = true;
  static bool get bleLogging => enabled && _bleLogging;
  
  /// Game engine logs
  static const bool _engineLogging = true;
  static bool get engineLogging => enabled && _engineLogging;
  
  /// Pairing manager logs
  static const bool _pairingLogging = true;
  static bool get pairingLogging => enabled && _pairingLogging;
  
  /// Question loading logs
  static const bool _questionsLogging = false;
  static bool get questionsLogging => enabled && _questionsLogging;
  
  /// UI/Screen logs
  static const bool _uiLogging = false; // Usually too verbose
  static bool get uiLogging => enabled && _uiLogging;
  
  /// Performance-critical logs (tick, build, etc.)
  static const bool _performanceLogging = false;
  static bool get performanceLogging => enabled && _performanceLogging;
  
  /// Message send/receive logs
  static const bool _messageLogging = true;
  static bool get messageLogging => enabled && _messageLogging;
  
  /// Heading/sensor fusion logs
  static const bool _headingLogging = false;
  static bool get headingLogging => enabled && _headingLogging;
  
  /// Sensor (accelerometer) logs
  static const bool _sensorLogging = false;
  static bool get sensorLogging => enabled && _sensorLogging;
}

/// Conditional print that respects DebugConfig
void debugPrint(String message, {bool force = false}) {
  if (force || DebugConfig.enabled) {
    print(message);
  }
}

/// Category-specific debug prints
void bleLog(String message) {
  if (DebugConfig.enabled && DebugConfig.bleLogging) {
    print('[BLE] $message');
  }
}

void engineLog(String message) {
  if (DebugConfig.enabled && DebugConfig.engineLogging) {
    print('[ENGINE] $message');
  }
}

void pairingLog(String message) {
  if (DebugConfig.enabled && DebugConfig.pairingLogging) {
    print('[PAIR] $message');
  }
}

void uiLog(String message) {
  if (DebugConfig.enabled && DebugConfig.uiLogging) {
    print('[UI] $message');
  }
}

void msgLog(String message) {
  if (DebugConfig.enabled && DebugConfig.messageLogging) {
    print('[MSG] $message');
  }
}

void perfLog(String message) {
  if (DebugConfig.enabled && DebugConfig.performanceLogging) {
    print('[PERF] $message');
  }
}

void questionsLog(String message) {
  if (DebugConfig.enabled && DebugConfig.questionsLogging) {
    print('[QUESTIONS] $message');
  }
}

void headingLog(String message) {
  if (DebugConfig.enabled && DebugConfig.headingLogging) {
    print('[HEADING] $message');
  }
}

void sensorLog(String message) {
  if (DebugConfig.enabled && DebugConfig.sensorLogging) {
    print('[SENSOR] $message');
  }
}
