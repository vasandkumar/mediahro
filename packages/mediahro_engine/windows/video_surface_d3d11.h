// Engine render bridge, Windows (lane B1, docs/05 §4.3).
//
// Licence: AGPL-3.0-or-later or the Mediahro commercial licence.
#ifndef MEDIAHRO_ENGINE_VIDEO_SURFACE_D3D11_H_
#define MEDIAHRO_ENGINE_VIDEO_SURFACE_D3D11_H_

#include <d3d11.h>
#include <flutter/texture_registrar.h>
#include <windows.h>
#include <wrl/client.h>

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

#include "libmpv_render.h"

namespace mediahro_engine {

// One video surface: mpv's D3D11 render API (render_d3d11.h) draws into
// double-buffered shared textures on the adapter Flutter renders with; the
// front texture is handed to Flutter as a DXGI shared handle, so frames go
// from the decoder (d3d11va on the same device) to the compositor without a
// CPU copy.
//
// When the adapter cannot share textures with Flutter (some virtual GPUs),
// the surface falls back to a pixel-buffer texture fed by a staging copy, so
// video still shows.
class VideoSurfaceD3D11 {
 public:
  static std::unique_ptr<VideoSurfaceD3D11> Create(
      flutter::TextureRegistrar* textures, IDXGIAdapter* adapter,
      const LibmpvRender& mpv, void* core, std::string* error);

  ~VideoSurfaceD3D11();

  int64_t texture_id() const { return texture_id_; }
  const char* backend() const { return shared_ ? "d3d11" : "d3d11-copy"; }
  int64_t frames_rendered() const { return frames_; }

  // Sets the render size (the video's display size).
  void Resize(int width, int height);

  // Stops rendering and frees the mpv render context. Must run before the
  // mpv core is destroyed; the textures stay valid until destruction.
  void Shutdown();

 private:
  VideoSurfaceD3D11(flutter::TextureRegistrar* textures, const LibmpvRender& mpv);

  bool Init(IDXGIAdapter* adapter, void* core, std::string* error);
  bool CreateTargets(int width, int height);
  void RenderLoop();
  void RenderFrame();
  static void OnMpvUpdate(void* ctx);
  const FlutterDesktopGpuSurfaceDescriptor* ObtainDescriptor(size_t w, size_t h);
  const FlutterDesktopPixelBuffer* CopyPixelBuffer(size_t w, size_t h);

  flutter::TextureRegistrar* textures_;
  LibmpvRender mpv_;
  mpv_render_context* render_ = nullptr;
  Microsoft::WRL::ComPtr<ID3D11Device> device_;
  Microsoft::WRL::ComPtr<ID3D11DeviceContext> context_;

  struct Target {
    Microsoft::WRL::ComPtr<ID3D11Texture2D> texture;
    HANDLE shared = nullptr;
  };
  Target targets_[2];
  Microsoft::WRL::ComPtr<ID3D11Texture2D> staging_;
  int front_ = 0;
  int width_ = 0;
  int height_ = 0;
  bool shared_ = true;

  std::unique_ptr<flutter::TextureVariant> variant_;
  int64_t texture_id_ = -1;
  FlutterDesktopGpuSurfaceDescriptor descriptor_{};
  FlutterDesktopPixelBuffer pixels_{};
  std::unique_ptr<uint8_t[]> pixel_data_;

  std::mutex mutex_;  // guards targets_, front_, size, descriptor_, pixels_
  std::condition_variable wake_;
  bool update_pending_ = false;
  int pending_width_ = 0;
  int pending_height_ = 0;
  bool stop_ = false;
  std::thread thread_;
  std::atomic<int64_t> frames_{0};
};

}  // namespace mediahro_engine

#endif  // MEDIAHRO_ENGINE_VIDEO_SURFACE_D3D11_H_
