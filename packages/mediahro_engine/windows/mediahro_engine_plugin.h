#ifndef FLUTTER_PLUGIN_MEDIAHRO_ENGINE_PLUGIN_H_
#define FLUTTER_PLUGIN_MEDIAHRO_ENGINE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace mediahro_engine {

class MediahroEnginePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  MediahroEnginePlugin();

  virtual ~MediahroEnginePlugin();

  // Disallow copy and assign.
  MediahroEnginePlugin(const MediahroEnginePlugin&) = delete;
  MediahroEnginePlugin& operator=(const MediahroEnginePlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace mediahro_engine

#endif  // FLUTTER_PLUGIN_MEDIAHRO_ENGINE_PLUGIN_H_
