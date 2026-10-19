#ifndef FLUTTER_PLUGIN_MEDIAHRO_ENGINE_PLUGIN_H_
#define FLUTTER_PLUGIN_MEDIAHRO_ENGINE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <map>
#include <memory>

#include "video_surface_d3d11.h"

namespace mediahro_engine {

class MediahroEnginePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit MediahroEnginePlugin(flutter::PluginRegistrarWindows* registrar);

  virtual ~MediahroEnginePlugin();

  // Disallow copy and assign.
  MediahroEnginePlugin(const MediahroEnginePlugin&) = delete;
  MediahroEnginePlugin& operator=(const MediahroEnginePlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  void Release(std::unique_ptr<VideoSurfaceD3D11> surface);

  flutter::PluginRegistrarWindows* registrar_;
  std::map<int64_t, std::unique_ptr<VideoSurfaceD3D11>> surfaces_;
};

}  // namespace mediahro_engine

#endif  // FLUTTER_PLUGIN_MEDIAHRO_ENGINE_PLUGIN_H_
