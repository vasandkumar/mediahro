// Engine render bridge, Apple (lane B1, docs/05 §4.3). Shared verbatim by
// the iOS and macOS plugin folders; keep both copies identical.
//
// mpv's render API exposes OpenGL and software backends only (no Metal or
// Vulkan), so frames are rendered with OpenGL (ES on iOS) into
// IOSurface-backed CVPixelBuffers that Flutter (Impeller/Metal) samples as
// external textures without a CPU copy. Recorded as an ADR request in
// STATUS.md §6.
//
// Licence: AGPL-3.0-or-later or the Mediahro commercial licence.

import CoreVideo
import Foundation

#if os(iOS)
import Flutter
import OpenGLES
#else
import FlutterMacOS
import OpenGL.GL3
#endif

/// libmpv render API, resolved with dlsym from the library Dart loaded.
private enum Mpv {
  typealias CreateFn = @convention(c) (
    UnsafeMutablePointer<OpaquePointer?>, OpaquePointer, UnsafeMutableRawPointer
  ) -> Int32
  typealias UpdateCallback = @convention(c) (UnsafeMutableRawPointer?) -> Void
  typealias SetUpdateCallbackFn = @convention(c) (
    OpaquePointer, UpdateCallback?, UnsafeMutableRawPointer?
  ) -> Void
  typealias UpdateFn = @convention(c) (OpaquePointer) -> UInt64
  typealias RenderFn = @convention(c) (OpaquePointer, UnsafeMutableRawPointer) -> Int32
  typealias ReportSwapFn = @convention(c) (OpaquePointer) -> Void
  typealias FreeFn = @convention(c) (OpaquePointer) -> Void

  static let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT

  static func sym<T>(_ name: String, _: T.Type) -> T? {
    guard let p = dlsym(defaultHandle, name) else { return nil }
    return unsafeBitCast(p, to: T.self)
  }

  static let create = sym("mpv_render_context_create", CreateFn.self)
  static let setUpdateCallback = sym(
    "mpv_render_context_set_update_callback", SetUpdateCallbackFn.self)
  static let update = sym("mpv_render_context_update", UpdateFn.self)
  static let render = sym("mpv_render_context_render", RenderFn.self)
  static let reportSwap = sym("mpv_render_context_report_swap", ReportSwapFn.self)
  static let free = sym("mpv_render_context_free", FreeFn.self)

  static var available: Bool {
    create != nil && setUpdateCallback != nil && update != nil && render != nil
      && reportSwap != nil && free != nil
  }

  // render.h constants
  static let paramInvalid: Int32 = 0
  static let paramApiType: Int32 = 1
  static let paramOpenGLInitParams: Int32 = 2
  static let paramOpenGLFbo: Int32 = 3
  static let paramFlipY: Int32 = 4
  static let updateFrame: UInt64 = 1
}

#if os(iOS)
private let openGLLibrary: UnsafeMutableRawPointer? = dlopen(
  "/System/Library/Frameworks/OpenGLES.framework/OpenGLES", RTLD_LAZY)
#else
private let openGLLibrary: UnsafeMutableRawPointer? = dlopen(
  "/System/Library/Frameworks/OpenGL.framework/OpenGL", RTLD_LAZY)
#endif

private let getProcAddress: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?)
  -> UnsafeMutableRawPointer? = { _, name in
    guard let name else { return nil }
    return dlsym(openGLLibrary, name)
  }

private let onMpvUpdate: Mpv.UpdateCallback = { ctx in
  guard let ctx else { return }
  let surface = Unmanaged<VideoSurface>.fromOpaque(ctx).takeUnretainedValue()
  surface.scheduleRender()
}

private let GL_TEXTURE_2D_: UInt32 = 0x0DE1
private let GL_FRAMEBUFFER_: UInt32 = 0x8D40
private let GL_COLOR_ATTACHMENT0_: UInt32 = 0x8CE0
private let GL_RGBA_: Int32 = 0x1908
private let GL_BGRA_: UInt32 = 0x80E1
private let GL_UNSIGNED_BYTE_: UInt32 = 0x1401

/// One video surface: an mpv render context drawing into double-buffered
/// IOSurface pixel buffers registered as a Flutter texture.
final class VideoSurface: NSObject, FlutterTexture {
  private struct Target {
    let pixelBuffer: CVPixelBuffer
    #if os(iOS)
    let texture: CVOpenGLESTexture
    #else
    let texture: CVOpenGLTexture
    #endif
    var fbo: UInt32
  }

  private let registry: FlutterTextureRegistry
  private let queue = DispatchQueue(label: "com.mediahro.engine.render")
  private let lock = NSLock()
  private var renderContext: OpaquePointer?
  #if os(iOS)
  private let gl: EAGLContext
  private var cache: CVOpenGLESTextureCache?
  #else
  private let gl: CGLContextObj
  private let pixelFormat: CGLPixelFormatObj
  private var cache: CVOpenGLTextureCache?
  #endif
  private var targets: [Target] = []
  private var front = 0
  private var width = 1280
  private var height = 720
  private var pending = false
  private var stopped = false
  private(set) var frames: Int64 = 0
  private(set) var textureId: Int64 = -1

  static let backend = "opengl-iosurface"

  init?(mpvHandle: OpaquePointer, registry: FlutterTextureRegistry) {
    guard Mpv.available else { return nil }
    self.registry = registry
    #if os(iOS)
    guard let context = EAGLContext(api: .openGLES3) ?? EAGLContext(api: .openGLES2) else {
      return nil
    }
    gl = context
    #else
    var attrs: [CGLPixelFormatAttribute] = [
      kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(rawValue: kCGLOGLPVersion_3_2_Core.rawValue),
      kCGLPFAAccelerated, kCGLPFAAllowOfflineRenderers, CGLPixelFormatAttribute(rawValue: 0),
    ]
    var format: CGLPixelFormatObj?
    var count: GLint = 0
    CGLChoosePixelFormat(&attrs, &format, &count)
    if format == nil {
      // Virtual machines (CI) have no accelerated renderer.
      attrs = [
        kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(rawValue: kCGLOGLPVersion_3_2_Core.rawValue),
        kCGLPFAAllowOfflineRenderers, CGLPixelFormatAttribute(rawValue: 0),
      ]
      CGLChoosePixelFormat(&attrs, &format, &count)
    }
    guard let format else { return nil }
    var context: CGLContextObj?
    CGLCreateContext(format, nil, &context)
    guard let context else { return nil }
    pixelFormat = format
    gl = context
    #endif
    super.init()
    var ok = false
    queue.sync { ok = self.setUp(mpvHandle: mpvHandle) }
    guard ok else { return nil }
    textureId = registry.register(self)
    let me = Unmanaged.passUnretained(self).toOpaque()
    Mpv.setUpdateCallback!(renderContext!, onMpvUpdate, me)
  }

  private func makeCurrent() {
    #if os(iOS)
    EAGLContext.setCurrent(gl)
    #else
    CGLSetCurrentContext(gl)
    #endif
  }

  private func setUp(mpvHandle: OpaquePointer) -> Bool {
    makeCurrent()
    #if os(iOS)
    guard CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, nil, gl, nil, &cache)
      == kCVReturnSuccess
    else { return false }
    #else
    guard CVOpenGLTextureCacheCreate(kCFAllocatorDefault, nil, gl, pixelFormat, nil, &cache)
      == kCVReturnSuccess
    else { return false }
    #endif
    let api = strdup("opengl")!
    defer { free(api) }
    let initParams = UnsafeMutableRawPointer.allocate(byteCount: 16, alignment: 8)
    defer { initParams.deallocate() }
    initParams.storeBytes(
      of: unsafeBitCast(getProcAddress, to: UnsafeMutableRawPointer.self), as: UnsafeMutableRawPointer.self)
    initParams.storeBytes(of: nil, toByteOffset: 8, as: UnsafeMutableRawPointer?.self)
    let params = Self.params([
      (Mpv.paramApiType, UnsafeMutableRawPointer(api)),
      (Mpv.paramOpenGLInitParams, initParams),
    ])
    defer { params.deallocate() }
    var ctx: OpaquePointer?
    guard Mpv.create!(&ctx, mpvHandle, params) >= 0, let ctx else { return false }
    renderContext = ctx
    return createTargets()
  }

  /// `mpv_render_param` array (int type + pointer, 16 bytes each),
  /// terminated by MPV_RENDER_PARAM_INVALID.
  private static func params(_ items: [(Int32, UnsafeMutableRawPointer?)]) -> UnsafeMutableRawPointer {
    let p = UnsafeMutableRawPointer.allocate(byteCount: 16 * (items.count + 1), alignment: 8)
    for (i, item) in (items + [(Mpv.paramInvalid, nil)]).enumerated() {
      p.storeBytes(of: item.0, toByteOffset: i * 16, as: Int32.self)
      p.storeBytes(of: 0, toByteOffset: i * 16 + 4, as: Int32.self)
      p.storeBytes(of: item.1, toByteOffset: i * 16 + 8, as: UnsafeMutableRawPointer?.self)
    }
    return p
  }

  private func createTargets() -> Bool {
    makeCurrent()
    for t in targets {
      var fbo = t.fbo
      glDeleteFramebuffers(1, &fbo)
    }
    targets.removeAll()
    guard let cache else { return false }
    #if os(iOS)
    let glCompat = kCVPixelBufferOpenGLESCompatibilityKey
    #else
    let glCompat = kCVPixelBufferOpenGLCompatibilityKey
    #endif
    let attributes: [CFString: Any] = [
      kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey: width,
      kCVPixelBufferHeightKey: height,
      kCVPixelBufferIOSurfacePropertiesKey: [:] as [CFString: Any],
      kCVPixelBufferMetalCompatibilityKey: true,
      glCompat: true,
    ]
    for _ in 0..<2 {
      var pb: CVPixelBuffer?
      guard CVPixelBufferCreate(
        kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
        attributes as CFDictionary, &pb) == kCVReturnSuccess, let pb
      else { return false }
      #if os(iOS)
      var tex: CVOpenGLESTexture?
      guard CVOpenGLESTextureCacheCreateTextureFromImage(
        kCFAllocatorDefault, cache, pb, nil, GLenum(GL_TEXTURE_2D_), GL_RGBA_,
        GLsizei(width), GLsizei(height), GLenum(GL_BGRA_), GLenum(GL_UNSIGNED_BYTE_), 0, &tex)
        == kCVReturnSuccess, let tex
      else { return false }
      let target = CVOpenGLESTextureGetTarget(tex)
      let name = CVOpenGLESTextureGetName(tex)
      #else
      var tex: CVOpenGLTexture?
      guard CVOpenGLTextureCacheCreateTextureFromImage(
        kCFAllocatorDefault, cache, pb, nil, &tex) == kCVReturnSuccess, let tex
      else { return false }
      let target = CVOpenGLTextureGetTarget(tex)
      let name = CVOpenGLTextureGetName(tex)
      #endif
      var fbo: GLuint = 0
      glGenFramebuffers(1, &fbo)
      glBindFramebuffer(GLenum(GL_FRAMEBUFFER_), fbo)
      glBindTexture(target, name)
      glFramebufferTexture2D(
        GLenum(GL_FRAMEBUFFER_), GLenum(GL_COLOR_ATTACHMENT0_), target, name, 0)
      targets.append(Target(pixelBuffer: pb, texture: tex, fbo: fbo))
    }
    glBindFramebuffer(GLenum(GL_FRAMEBUFFER_), 0)
    front = 0
    return true
  }

  func scheduleRender() {
    lock.lock()
    let already = pending
    pending = true
    lock.unlock()
    if already { return }
    queue.async { [weak self] in self?.render() }
  }

  private func render() {
    lock.lock()
    pending = false
    let stop = stopped
    lock.unlock()
    guard !stop, let ctx = renderContext else { return }
    makeCurrent()
    let flags = Mpv.update!(ctx)
    guard flags & Mpv.updateFrame != 0, targets.count == 2 else { return }
    let back = 1 - front
    let fbo = UnsafeMutableRawPointer.allocate(byteCount: 16, alignment: 8)
    defer { fbo.deallocate() }
    fbo.storeBytes(of: Int32(targets[back].fbo), as: Int32.self)
    fbo.storeBytes(of: Int32(width), toByteOffset: 4, as: Int32.self)
    fbo.storeBytes(of: Int32(height), toByteOffset: 8, as: Int32.self)
    fbo.storeBytes(of: 0, toByteOffset: 12, as: Int32.self)
    let flip = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
    defer { flip.deallocate() }
    flip.pointee = 0
    let params = Self.params([
      (Mpv.paramOpenGLFbo, fbo),
      (Mpv.paramFlipY, UnsafeMutableRawPointer(flip)),
    ])
    defer { params.deallocate() }
    guard Mpv.render!(ctx, params) >= 0 else { return }
    glFinish()
    lock.lock()
    front = back
    frames += 1
    lock.unlock()
    let id = textureId
    DispatchQueue.main.async { [weak self] in
      self?.registry.textureFrameAvailable(id)
    }
    Mpv.reportSwap!(ctx)
  }

  func resize(width w: Int, height h: Int) {
    guard w > 0, h > 0 else { return }
    queue.async { [weak self] in
      guard let self, w != self.width || h != self.height else { return }
      self.lock.lock()
      self.width = min(w, 8192)
      self.height = min(h, 8192)
      self.lock.unlock()
      _ = self.createTargets()
      self.scheduleRender()
    }
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    lock.lock()
    defer { lock.unlock() }
    guard frames > 0, front < targets.count else { return nil }
    return Unmanaged.passRetained(targets[front].pixelBuffer)
  }

  /// Frees the render context; must run before the mpv core is destroyed.
  func dispose() {
    lock.lock()
    stopped = true
    lock.unlock()
    queue.sync {
      if let ctx = renderContext {
        Mpv.setUpdateCallback!(ctx, nil, nil)
        makeCurrent()
        Mpv.free!(ctx)
        renderContext = nil
      }
      for t in targets {
        var fbo = t.fbo
        glDeleteFramebuffers(1, &fbo)
      }
    }
    registry.unregisterTexture(textureId)
  }
}
