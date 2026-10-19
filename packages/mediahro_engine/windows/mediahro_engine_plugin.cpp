// Engine plugin, Windows: render bridge channel (ADR-011, docs/05 §4.3).
//
// Licence: AGPL-3.0-or-later or the Mediahro commercial licence.
#include "mediahro_engine_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <VersionHelpers.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <wrl/client.h>

#include <memory>
#include <sstream>
#include <string>

namespace mediahro_engine {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

const EncodableValue* Arg(const EncodableMap& args, const char* key) {
  auto it = args.find(EncodableValue(key));
  return it == args.end() ? nullptr : &it->second;
}

int64_t ArgInt(const EncodableMap& args, const char* key) {
  const EncodableValue* v = Arg(args, key);
  if (v == nullptr) return 0;
  if (auto i = std::get_if<int32_t>(v)) return *i;
  if (auto l = std::get_if<int64_t>(v)) return *l;
  return 0;
}

std::wstring Widen(const std::string& s) {
  if (s.empty()) return std::wstring();
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                              nullptr, 0);
  std::wstring w(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), w.data(), n);
  return w;
}

}  // namespace

// static
void MediahroEnginePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      registrar->messenger(), "com.mediahro.engine/bridge",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<MediahroEnginePlugin>(registrar);

  channel->SetMethodCallHandler([plugin_pointer = plugin.get()](const auto& call,
                                                                auto result) {
    plugin_pointer->HandleMethodCall(call, std::move(result));
  });

  registrar->AddPlugin(std::move(plugin));
}

MediahroEnginePlugin::MediahroEnginePlugin(flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {}

MediahroEnginePlugin::~MediahroEnginePlugin() {
  for (auto& entry : surfaces_) Release(std::move(entry.second));
  surfaces_.clear();
}

void MediahroEnginePlugin::Release(std::unique_ptr<VideoSurfaceD3D11> surface) {
  if (!surface) return;
  surface->Shutdown();
  const int64_t id = surface->texture_id();
  // Flutter may still hold the texture; free it once unregistration is done.
  VideoSurfaceD3D11* raw = surface.release();
  registrar_->texture_registrar()->UnregisterTexture(id, [raw]() { delete raw; });
}

void MediahroEnginePlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = method_call.method_name();
  const auto* args = std::get_if<EncodableMap>(method_call.arguments());
  if (method == "bridgeInfo") {
    std::ostringstream version;
    version << "Windows " << (IsWindows10OrGreater() ? "10+" : "older");
    result->Success(EncodableValue(version.str()));
    return;
  }
  if (method == "create" && args != nullptr) {
    const auto* path = std::get_if<std::string>(Arg(*args, "libmpv"));
    void* handle = reinterpret_cast<void*>(ArgInt(*args, "handle"));
    LibmpvRender mpv;
    if (path == nullptr || handle == nullptr || !mpv.Load(Widen(*path))) {
      result->Error("libmpv", "render API not available");
      return;
    }
    Microsoft::WRL::ComPtr<IDXGIAdapter> adapter;
    registrar_->GetGraphicsAdapter(&adapter);
    std::string error;
    auto surface = VideoSurfaceD3D11::Create(registrar_->texture_registrar(),
                                             adapter.Get(), mpv, handle, &error);
    if (!surface) {
      result->Error("surface", error);
      return;
    }
    const int64_t id = surface->texture_id();
    EncodableMap reply{
        {EncodableValue("textureId"), EncodableValue(id)},
        {EncodableValue("backend"), EncodableValue(surface->backend())},
    };
    surfaces_[id] = std::move(surface);
    result->Success(EncodableValue(reply));
    return;
  }
  if (method == "resize" && args != nullptr) {
    auto it = surfaces_.find(ArgInt(*args, "textureId"));
    if (it != surfaces_.end()) {
      it->second->Resize(static_cast<int>(ArgInt(*args, "width")),
                         static_cast<int>(ArgInt(*args, "height")));
    }
    result->Success();
    return;
  }
  if (method == "stats" && args != nullptr) {
    auto it = surfaces_.find(ArgInt(*args, "textureId"));
    if (it == surfaces_.end()) {
      result->Success();
      return;
    }
    result->Success(EncodableValue(EncodableMap{
        {EncodableValue("frames"), EncodableValue(it->second->frames_rendered())},
        {EncodableValue("backend"), EncodableValue(it->second->backend())},
    }));
    return;
  }
  if (method == "dispose" && args != nullptr) {
    auto it = surfaces_.find(ArgInt(*args, "textureId"));
    if (it != surfaces_.end()) {
      Release(std::move(it->second));
      surfaces_.erase(it);
    }
    result->Success();
    return;
  }
  result->NotImplemented();
}

}  // namespace mediahro_engine
