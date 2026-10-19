# Engine plugin, Windows (lane B1): render bridge (D3D11 render API into a
# shared texture, docs/05 §4.3) and libmpv bundling.
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "mediahro_engine")
project(${PROJECT_NAME} LANGUAGES CXX)
cmake_policy(VERSION 3.14...3.25)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "mediahro_engine_plugin")

# The plugin is reached through a symlink under the app's ephemeral folder,
# so find the repository (mpv headers, .deps-cache) by walking up from the
# app's own windows/ folder to the directory holding deps.lock.
set(MEDIAHRO_REPO "${CMAKE_SOURCE_DIR}")
while(NOT EXISTS "${MEDIAHRO_REPO}/deps.lock")
  get_filename_component(parent "${MEDIAHRO_REPO}" DIRECTORY)
  if(parent STREQUAL MEDIAHRO_REPO)
    message(FATAL_ERROR "mediahro_engine: deps.lock not found above ${CMAKE_SOURCE_DIR}")
  endif()
  set(MEDIAHRO_REPO "${parent}")
endwhile()
set(MPV_INCLUDE "${MEDIAHRO_REPO}/packages/mediahro_ffi/lib/src/mpv/include")

list(APPEND PLUGIN_SOURCES
  "mediahro_engine_plugin.cpp"
  "mediahro_engine_plugin.h"
  "video_surface_d3d11.cpp"
  "video_surface_d3d11.h"
  "libmpv_render.h"
)

add_library(${PLUGIN_NAME} SHARED
  "include/mediahro_engine/mediahro_engine_plugin_c_api.h"
  "mediahro_engine_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL NOMINMAX)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_include_directories(${PLUGIN_NAME} PRIVATE "${MPV_INCLUDE}")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin d3d11 dxgi)

# libmpv (LGPL, dynamic only, docs/09 §2): the mediahro-deps archive pinned in
# deps.lock, else the ADR-004 bootstrap fetched by tool/fetch_libmpv.py. With
# neither present the app builds and the engine reports libraryMissing.
set(MEDIAHRO_LIBMPV "")
foreach(candidate
    "${MEDIAHRO_REPO}/.deps-cache/windows-x64/lib/mpv.dll"
    "${MEDIAHRO_REPO}/.deps-cache/bootstrap/windows-x64/lib/libmpv-2.dll")
  if(MEDIAHRO_LIBMPV STREQUAL "" AND EXISTS "${candidate}")
    set(MEDIAHRO_LIBMPV "${candidate}")
  endif()
endforeach()
if(NOT MEDIAHRO_LIBMPV STREQUAL "")
  message(STATUS "mediahro_engine: bundling ${MEDIAHRO_LIBMPV}")
endif()

set(mediahro_engine_bundled_libraries
  ${MEDIAHRO_LIBMPV}
  PARENT_SCOPE
)
