#include "include/mediahro_engine/mediahro_engine_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "mediahro_engine_plugin.h"

void MediahroEnginePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  mediahro_engine::MediahroEnginePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
