// Engine render bridge, Windows (lane B1, docs/05 §4.3).
//
// Licence: AGPL-3.0-or-later or the Mediahro commercial licence.
#include "video_surface_d3d11.h"

#include <d3d10.h>
#include <dxgi1_2.h>

#include <cstdlib>
#include <cstring>

using Microsoft::WRL::ComPtr;

namespace mediahro_engine {

namespace {

constexpr int kDefaultWidth = 1280;
constexpr int kDefaultHeight = 720;
constexpr int kMaxDimension = 16384;

bool ForceCopyPath() {
  char* value = nullptr;
  size_t len = 0;
  bool copy = false;
  if (_dupenv_s(&value, &len, "MEDIAHRO_ENGINE_TEXTURE") == 0 && value) {
    copy = std::strcmp(value, "copy") == 0;
    std::free(value);
  }
  return copy;
}

}  // namespace

std::unique_ptr<VideoSurfaceD3D11> VideoSurfaceD3D11::Create(
    flutter::TextureRegistrar* textures, IDXGIAdapter* adapter,
    const LibmpvRender& mpv, void* core, std::string* error) {
  std::unique_ptr<VideoSurfaceD3D11> surface(new VideoSurfaceD3D11(textures, mpv));
  if (!surface->Init(adapter, core, error)) return nullptr;
  return surface;
}

VideoSurfaceD3D11::VideoSurfaceD3D11(flutter::TextureRegistrar* textures,
                                     const LibmpvRender& mpv)
    : textures_(textures), mpv_(mpv) {}

bool VideoSurfaceD3D11::Init(IDXGIAdapter* adapter, void* core,
                             std::string* error) {
  const D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0,
                                      D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_10_0};
  const D3D_DRIVER_TYPE driver =
      adapter != nullptr ? D3D_DRIVER_TYPE_UNKNOWN : D3D_DRIVER_TYPE_HARDWARE;
  UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT | D3D11_CREATE_DEVICE_VIDEO_SUPPORT;
  HRESULT hr = D3D11CreateDevice(adapter, driver, nullptr, flags, levels,
                                 ARRAYSIZE(levels), D3D11_SDK_VERSION, &device_,
                                 nullptr, &context_);
  if (FAILED(hr)) {
    // Video support is missing on some adapters (WARP); hwdec then uses
    // copy-back or software decode.
    flags &= ~D3D11_CREATE_DEVICE_VIDEO_SUPPORT;
    hr = D3D11CreateDevice(adapter, driver, nullptr, flags, levels, ARRAYSIZE(levels),
                           D3D11_SDK_VERSION, &device_, nullptr, &context_);
  }
  if (FAILED(hr)) {
    *error = "D3D11CreateDevice failed";
    return false;
  }
  ComPtr<ID3D10Multithread> mt;
  if (SUCCEEDED(device_.As(&mt))) mt->SetMultithreadProtected(TRUE);

  mpv_d3d11_init_params init{device_.Get()};
  char api[] = MPV_RENDER_API_TYPE_D3D11;
  mpv_render_param params[] = {
      {MPV_RENDER_PARAM_API_TYPE, api},
      {MPV_RENDER_PARAM_D3D11_INIT_PARAMS, &init},
      {MPV_RENDER_PARAM_INVALID, nullptr},
  };
  int rc = mpv_.create(&render_, static_cast<mpv_handle*>(core), params);
  if (rc < 0) {
    *error = "mpv_render_context_create(d3d11) failed: " + std::to_string(rc);
    return false;
  }

  shared_ = !ForceCopyPath();
  if (!CreateTargets(kDefaultWidth, kDefaultHeight)) {
    *error = "texture creation failed";
    return false;
  }

  if (shared_) {
    variant_ = std::make_unique<flutter::TextureVariant>(flutter::GpuSurfaceTexture(
        kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle,
        [this](size_t w, size_t h) { return ObtainDescriptor(w, h); }));
    texture_id_ = textures_->RegisterTexture(variant_.get());
  }
  if (texture_id_ < 0) {
    shared_ = false;
    CreateTargets(kDefaultWidth, kDefaultHeight);
    variant_ = std::make_unique<flutter::TextureVariant>(flutter::PixelBufferTexture(
        [this](size_t w, size_t h) { return CopyPixelBuffer(w, h); }));
    texture_id_ = textures_->RegisterTexture(variant_.get());
  }
  if (texture_id_ < 0) {
    *error = "texture registration failed";
    return false;
  }

  mpv_.set_update_callback(render_, &VideoSurfaceD3D11::OnMpvUpdate, this);
  thread_ = std::thread([this] { RenderLoop(); });
  return true;
}

bool VideoSurfaceD3D11::CreateTargets(int width, int height) {
  std::lock_guard<std::mutex> lock(mutex_);
  for (auto& t : targets_) {
    t.texture.Reset();
    t.shared = nullptr;
  }
  staging_.Reset();
  D3D11_TEXTURE2D_DESC desc{};
  desc.Width = width;
  desc.Height = height;
  desc.MipLevels = 1;
  desc.ArraySize = 1;
  desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc.SampleDesc.Count = 1;
  desc.Usage = D3D11_USAGE_DEFAULT;
  desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
  desc.MiscFlags = shared_ ? D3D11_RESOURCE_MISC_SHARED : 0;
  for (auto& t : targets_) {
    if (FAILED(device_->CreateTexture2D(&desc, nullptr, &t.texture))) return false;
    if (shared_) {
      ComPtr<IDXGIResource> resource;
      if (FAILED(t.texture.As(&resource)) ||
          FAILED(resource->GetSharedHandle(&t.shared))) {
        return false;
      }
    }
  }
  if (!shared_) {
    D3D11_TEXTURE2D_DESC sd = desc;
    sd.Usage = D3D11_USAGE_STAGING;
    sd.BindFlags = 0;
    sd.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    sd.MiscFlags = 0;
    if (FAILED(device_->CreateTexture2D(&sd, nullptr, &staging_))) return false;
    pixel_data_.reset(new uint8_t[static_cast<size_t>(width) * height * 4]());
    pixels_.buffer = pixel_data_.get();
    pixels_.width = width;
    pixels_.height = height;
  }
  width_ = width;
  height_ = height;
  front_ = 0;
  descriptor_.struct_size = sizeof(FlutterDesktopGpuSurfaceDescriptor);
  descriptor_.handle = targets_[0].shared;
  descriptor_.width = descriptor_.visible_width = width;
  descriptor_.height = descriptor_.visible_height = height;
  descriptor_.format = kFlutterDesktopPixelFormatBGRA8888;
  return true;
}

void VideoSurfaceD3D11::OnMpvUpdate(void* ctx) {
  auto* self = static_cast<VideoSurfaceD3D11*>(ctx);
  {
    std::lock_guard<std::mutex> lock(self->mutex_);
    self->update_pending_ = true;
  }
  self->wake_.notify_one();
}

void VideoSurfaceD3D11::Resize(int width, int height) {
  if (width <= 0 || height <= 0) return;
  if (width > kMaxDimension) width = kMaxDimension;
  if (height > kMaxDimension) height = kMaxDimension;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    pending_width_ = width;
    pending_height_ = height;
    update_pending_ = true;
  }
  wake_.notify_one();
}

void VideoSurfaceD3D11::RenderLoop() {
  while (true) {
    int resize_w = 0;
    int resize_h = 0;
    {
      std::unique_lock<std::mutex> lock(mutex_);
      wake_.wait(lock, [this] { return stop_ || update_pending_; });
      if (stop_) return;
      update_pending_ = false;
      if (pending_width_ > 0 &&
          (pending_width_ != width_ || pending_height_ != height_)) {
        resize_w = pending_width_;
        resize_h = pending_height_;
      }
      pending_width_ = pending_height_ = 0;
    }
    if (resize_w > 0) CreateTargets(resize_w, resize_h);
    RenderFrame();
  }
}

void VideoSurfaceD3D11::RenderFrame() {
  const uint64_t flags = mpv_.update(render_);
  if ((flags & MPV_RENDER_UPDATE_FRAME) == 0) return;
  ID3D11Texture2D* back = nullptr;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    back = targets_[1 - front_].texture.Get();
  }
  if (back == nullptr) return;
  mpv_d3d11_fbo fbo{back};
  mpv_render_param params[] = {
      {MPV_RENDER_PARAM_D3D11_FBO, &fbo},
      {MPV_RENDER_PARAM_INVALID, nullptr},
  };
  if (mpv_.render(render_, params) < 0) return;

  // Wait for the GPU so Flutter's device never samples a half-rendered
  // frame (shared resources carry no implicit cross-device fence).
  D3D11_QUERY_DESC qd{D3D11_QUERY_EVENT, 0};
  ComPtr<ID3D11Query> done;
  if (SUCCEEDED(device_->CreateQuery(&qd, &done))) {
    context_->End(done.Get());
    BOOL finished = FALSE;
    while (context_->GetData(done.Get(), &finished, sizeof(finished), 0) == S_FALSE) {
      std::this_thread::yield();
    }
  } else {
    context_->Flush();
  }

  if (!shared_) {
    context_->CopyResource(staging_.Get(), back);
    D3D11_MAPPED_SUBRESOURCE map{};
    if (SUCCEEDED(context_->Map(staging_.Get(), 0, D3D11_MAP_READ, 0, &map))) {
      std::lock_guard<std::mutex> lock(mutex_);
      // BGRA → RGBA for the pixel-buffer texture.
      for (int y = 0; y < height_; ++y) {
        const uint8_t* src = static_cast<const uint8_t*>(map.pData) + y * map.RowPitch;
        uint8_t* dst = pixel_data_.get() + static_cast<size_t>(y) * width_ * 4;
        for (int x = 0; x < width_; ++x) {
          dst[x * 4 + 0] = src[x * 4 + 2];
          dst[x * 4 + 1] = src[x * 4 + 1];
          dst[x * 4 + 2] = src[x * 4 + 0];
          dst[x * 4 + 3] = 255;
        }
      }
      context_->Unmap(staging_.Get(), 0);
    }
  }
  {
    std::lock_guard<std::mutex> lock(mutex_);
    front_ = 1 - front_;
    descriptor_.handle = targets_[front_].shared;
  }
  frames_++;
  textures_->MarkTextureFrameAvailable(texture_id_);
  mpv_.report_swap(render_);
}

const FlutterDesktopGpuSurfaceDescriptor* VideoSurfaceD3D11::ObtainDescriptor(
    size_t, size_t) {
  std::lock_guard<std::mutex> lock(mutex_);
  return frames_ > 0 ? &descriptor_ : nullptr;
}

const FlutterDesktopPixelBuffer* VideoSurfaceD3D11::CopyPixelBuffer(size_t, size_t) {
  std::lock_guard<std::mutex> lock(mutex_);
  return frames_ > 0 ? &pixels_ : nullptr;
}

VideoSurfaceD3D11::~VideoSurfaceD3D11() { Shutdown(); }

void VideoSurfaceD3D11::Shutdown() {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    stop_ = true;
  }
  wake_.notify_one();
  if (thread_.joinable()) thread_.join();
  if (render_ != nullptr) {
    mpv_.set_update_callback(render_, nullptr, nullptr);
    mpv_.free(render_);
    render_ = nullptr;
  }
}

}  // namespace mediahro_engine
