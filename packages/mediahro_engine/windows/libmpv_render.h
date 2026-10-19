// libmpv render API resolved at runtime from the library the Dart side
// opened (LoadLibrary), so the plugin builds without libmpv and LGPL code is
// only ever linked dynamically (docs/09 §2).
//
// Licence: AGPL-3.0-or-later or the Mediahro commercial licence.
#ifndef MEDIAHRO_ENGINE_LIBMPV_RENDER_H_
#define MEDIAHRO_ENGINE_LIBMPV_RENDER_H_

#include <mpv/render.h>
#include <mpv/render_d3d11.h>
#include <windows.h>

#include <string>

namespace mediahro_engine {

struct LibmpvRender {
  decltype(&mpv_render_context_create) create = nullptr;
  decltype(&mpv_render_context_set_update_callback) set_update_callback = nullptr;
  decltype(&mpv_render_context_update) update = nullptr;
  decltype(&mpv_render_context_render) render = nullptr;
  decltype(&mpv_render_context_report_swap) report_swap = nullptr;
  decltype(&mpv_render_context_free) free = nullptr;

  // Loads (or reuses) [path] and resolves the render API.
  bool Load(const std::wstring& path) {
    HMODULE lib = GetModuleHandleW(path.c_str());
    if (lib == nullptr) lib = LoadLibraryW(path.c_str());
    if (lib == nullptr) return false;
    create = reinterpret_cast<decltype(create)>(
        GetProcAddress(lib, "mpv_render_context_create"));
    set_update_callback = reinterpret_cast<decltype(set_update_callback)>(
        GetProcAddress(lib, "mpv_render_context_set_update_callback"));
    update = reinterpret_cast<decltype(update)>(
        GetProcAddress(lib, "mpv_render_context_update"));
    render = reinterpret_cast<decltype(render)>(
        GetProcAddress(lib, "mpv_render_context_render"));
    report_swap = reinterpret_cast<decltype(report_swap)>(
        GetProcAddress(lib, "mpv_render_context_report_swap"));
    free = reinterpret_cast<decltype(free)>(
        GetProcAddress(lib, "mpv_render_context_free"));
    return create && set_update_callback && update && render && report_swap &&
           free;
  }
};

}  // namespace mediahro_engine

#endif  // MEDIAHRO_ENGINE_LIBMPV_RENDER_H_
