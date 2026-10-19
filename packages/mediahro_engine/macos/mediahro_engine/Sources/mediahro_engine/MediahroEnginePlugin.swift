// Engine plugin, Apple: render bridge channel (ADR-011, docs/05 §4.3).
// Shared verbatim by the iOS and macOS plugin folders.
//
// Licence: AGPL-3.0-or-later or the Mediahro commercial licence.

import Foundation

#if os(iOS)
import Flutter
import UIKit
#else
import FlutterMacOS
#endif

public class MediahroEnginePlugin: NSObject, FlutterPlugin {
  private let textures: FlutterTextureRegistry
  private var surfaces: [Int64: VideoSurface] = [:]

  init(textures: FlutterTextureRegistry) {
    self.textures = textures
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
    let messenger = registrar.messenger()
    let textures = registrar.textures()
    #else
    let messenger = registrar.messenger
    let textures = registrar.textures
    #endif
    let channel = FlutterMethodChannel(name: "com.mediahro.engine/bridge", binaryMessenger: messenger)
    let instance = MediahroEnginePlugin(textures: textures)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "bridgeInfo":
      #if os(iOS)
      result("iOS " + UIDevice.current.systemVersion)
      #else
      result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
      #endif
    case "create":
      guard let address = (args["handle"] as? NSNumber)?.intValue,
        let handle = OpaquePointer(bitPattern: address)
      else {
        result(FlutterError(code: "args", message: "missing mpv handle", details: nil))
        return
      }
      guard let surface = VideoSurface(mpvHandle: handle, registry: textures) else {
        result(FlutterError(code: "surface", message: "OpenGL render context failed", details: nil))
        return
      }
      surfaces[surface.textureId] = surface
      result(["textureId": surface.textureId, "backend": VideoSurface.backend])
    case "resize":
      if let id = (args["textureId"] as? NSNumber)?.int64Value,
        let w = (args["width"] as? NSNumber)?.intValue,
        let h = (args["height"] as? NSNumber)?.intValue
      {
        surfaces[id]?.resize(width: w, height: h)
      }
      result(nil)
    case "stats":
      if let id = (args["textureId"] as? NSNumber)?.int64Value, let s = surfaces[id] {
        result(["frames": s.frames, "backend": VideoSurface.backend])
      } else {
        result(nil)
      }
    case "dispose":
      if let id = (args["textureId"] as? NSNumber)?.int64Value {
        surfaces.removeValue(forKey: id)?.dispose()
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
