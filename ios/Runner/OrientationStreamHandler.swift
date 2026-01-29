import Flutter

/// Handles EventChannel streaming of orientation samples
class OrientationStreamHandler: NSObject, FlutterStreamHandler {
  let fusionManager: OrientationFusionManager
  var eventSink: FlutterEventSink?
  
  init(fusionManager: OrientationFusionManager) {
    self.fusionManager = fusionManager
  }
  
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    
    fusionManager.start { [weak self] sample in
      self?.eventSink?(sample)
    }
    
    return nil
  }
  
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    fusionManager.stop()
    eventSink = nil
    return nil
  }
}
