// Engine plugin, Apple: render bridge channel (ADR-011, docs/05 §4.3).
// Shared verbatim by the iOS and macOS plugin folders.
//
// Licence: AGPL-3.0-or-later or the Mediahro commercial licence.

import Foundation

#if os(iOS)
import AVFoundation
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
    let audio = FlutterMethodChannel(name: "com.mediahro.engine/audio", binaryMessenger: messenger)
    audio.setMethodCallHandler { call, result in
      guard call.method == "prefer" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(Self.preferOutput(call.arguments as? [String: Any] ?? [:]))
    }
  }

  /// AUD-041: iOS gets the best available path — the session's preferred
  /// sample rate follows the source. macOS bit-perfect output is mpv's
  /// CoreAudio hog mode with rate switching (`audio-exclusive`).
  static func preferOutput(_ args: [String: Any]) -> [String: Any] {
    #if os(iOS)
    let session = AVAudioSession.sharedInstance()
    let rate = (args["sampleRate"] as? NSNumber)?.doubleValue
    let bitPerfect = (args["bitPerfect"] as? Bool) ?? false
    do {
      try session.setCategory(.playback, mode: .default)
      try session.setPreferredSampleRate(bitPerfect ? (rate ?? 0) : 0)
      try session.setActive(true)
    } catch {
      return ["applied": false, "reason": "\(error)"]
    }
    let actual = Int(session.sampleRate)
    return [
      "applied": true,
      "sampleRate": actual,
      "bitPerfect": bitPerfect && rate != nil && Double(actual) == rate,
      "device": session.currentRoute.outputs.first?.portName ?? "",
    ]
    #else
    return ["applied": false, "reason": "CoreAudio hog mode via audio-exclusive"]
    #endif
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
        result(FlutterError(code: "surface", message: VideoSurface.lastFailure, details: nil))
        return
      }
      surfaces[surface.textureId] = surface
      result(["textureId": surface.textureId, "backend": surface.backend])
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
        result(["frames": s.frames, "backend": s.backend])
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
