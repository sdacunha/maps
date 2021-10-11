import MapboxMaps
import Turf

class PointAnnotationManager : AnnotationInteractionDelegate {
  func annotationManager(_ manager: AnnotationManager, didDetectTappedAnnotations annotations: [Annotation]) {
    print("Tap: \(annotations)")
  }
  
  var manager : MapboxMaps.PointAnnotationManager
  
  init(annotations: AnnotationOrchestrator) {
    manager = annotations.makePointAnnotationManager()
    manager.delegate = self
  }
  
  func remove(_ annotation: PointAnnotation) {
    manager.annotations.removeAll(where: {$0.id == annotation.id})
  }
  
  func add(_ annotation: PointAnnotation) {
    manager.annotations.append(annotation)
    manager.syncSourceAndLayerIfNeeded()
  }
  

}

public func dictionaryFrom(_ from: Turf.Feature?) throws -> [String:Any]? {
  let data = try JSONEncoder().encode(from)
  let value = try JSONSerialization.jsonObject(with: data) as? [String:Any]
  return value
}

@objc class RCTMGLMapView : MapView {
  var reactOnPress : RCTBubblingEventBlock? = nil
  var reactOnMapChange : RCTBubblingEventBlock? = nil
  
  var images : [RCTMGLImages] = []
  
  var layerWaiters : [String:[(String) -> Void]] = [:]
  
  lazy var pointAnnotationManager : PointAnnotationManager = {
    return PointAnnotationManager(annotations: annotations)
  }()
  
  var mapView : MapView {
      get { return self }
  }
    
  // -- react native properties
  
  @objc func setReactStyleURL(_ value: String?) {
      if let value = value {
          if let url = URL(string: value) {
              mapView.mapboxMap.loadStyleURI(StyleURI(rawValue: value)!)
          } else {
              if RCTJSONParse(value, nil) != nil {
                  mapView.mapboxMap.loadStyleJSON(value)
              }
          }
      }
  }

  @objc func setReactOnPress(_ value: @escaping RCTBubblingEventBlock) {
    self.reactOnPress = value

    /*
      let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
      self.addGestureRecognizer(tapGesture)
    */
    mapView.gestures.singleTapGestureRecognizer.addTarget(self, action: #selector(doHandleTap(_:)))
  }

  @objc func setReactOnMapChange(_ value: @escaping RCTBubblingEventBlock) {
      self.reactOnMapChange = value
  
      self.mapView.mapboxMap.onEvery(.cameraChanged, handler: { cameraEvent in
          let event = RCTMGLEvent(type:.regionDidChange, payload: self._makeRegionPayload());
          self.fireEvent(event: event, callback: self.reactOnMapChange!)
      })
  }

    
  func fireEvent(event: RCTMGLEvent, callback: @escaping RCTBubblingEventBlock) {
      callback(event.toJSON())
  }
  
  @objc
  func doHandleTap(_ sender: UITapGestureRecognizer) {
      if let reactOnPress = self.reactOnPress {
          let tapPoint = sender.location(in: self)
          let location = mapboxMap.coordinate(for: tapPoint)
          print("Tap point \(tapPoint) => \(location)")
          
          var geojson = Feature(geometry: .point(Point(location)));
          geojson.properties = [
            "screenPointX": .number(Double(tapPoint.x)),
            "screenPointY": .number(Double(tapPoint.y))
          ];
          let event = try!  RCTMGLEvent(type:.tap, payload: dictionaryFrom(geojson)!);
          self.fireEvent(event: event, callback: reactOnPress)
      }
  }
        
  func _toArray(bounds: CoordinateBounds) -> [[Double]] {
      return [
          [
              Double(bounds.northeast.longitude),
              Double(bounds.northeast.latitude),
          ],
          [
              Double(bounds.southwest.longitude),
              Double(bounds.southwest.latitude)
          ]
      ]
  }
    
  func toJSON(geometry: Turf.Geometry, properties: [String: Any]? = nil) -> [String: Any] {
      let geojson = Feature(geometry: geometry);
    
      var result = try! dictionaryFrom(geojson)!
      if let properties = properties {
          result["properties"] = properties
      }
      return result
  }
    
  func _makeRegionPayload() -> [String:Any] {
      return toJSON(
          geometry: .point(Point(mapView.cameraState.center)),
          properties: [
              "zoomLevel" : Double(mapView.cameraState.zoom),
              "heading": Double(mapView.cameraState.bearing),
              "bearing": Double(mapView.cameraState.bearing),
              "pitch": Double(mapView.cameraState.pitch),
              "visibleBounds": _toArray(bounds: mapView.mapboxMap.cameraBounds.bounds)
          ]
      )
  }
    
  @objc override func insertReactSubview(_ subview: UIView!, at atIndex: Int) {
    if let mapComponent = subview as? RCTMGLMapComponent {
      mapComponent.addToMap(self)
    }
  }
  
  @objc override func removeReactSubview(_ subview:UIView!) {
    removeFromMap(subview)
  }
  
  func removeFromMap(_ subview: UIView!) {
    if let mapComponent = subview as? RCTMGLMapComponent {
      mapComponent.addToMap(self)
    }
  }
    
  required init(frame:CGRect) {
    let resourceOptions = ResourceOptions(accessToken: MGLModule.accessToken!)
    super.init(frame: frame, mapInitOptions: MapInitOptions(resourceOptions: resourceOptions))

    setupEvents()
  }
  
  func setupEvents() {
    self.mapboxMap.onEvery(.styleImageMissing) { (event) in
      if let data = event.data as? [String:Any] {
        if let imageName = data["id"] as? String {

          self.images.forEach {
            if $0.addMissingImageToStyle(style: self.mapboxMap.style, imageName: imageName) {
              return
            }
          }
          
          self.images.forEach {
            $0.sendImageMissingEvent(imageName: imageName, event: event)
          }
        }
      }
    }
    
    self.mapboxMap.onNext(.mapLoaded, handler: { (event) in
      let event = RCTMGLEvent(type:.didFinishLoadingMap, payload: nil);
      self.fireEvent(event: event, callback: self.reactOnMapChange!)
    })
  }
    
  required init (coder: NSCoder) {
      fatalError("not implemented")
  }
  
  func layerAdded (_ layer: Layer) {
      // V10 TODO
  }
  
  func waitForLayerWithID(_ layerId: String, _  callback: @escaping (_ layerId: String) -> Void) {
    let style = mapboxMap.style;
    if style.layerExists(withId: layerId) {
      callback(layerId)
    } else {
      layerWaiters[layerId, default: []].append(callback)
    }
  }
}
