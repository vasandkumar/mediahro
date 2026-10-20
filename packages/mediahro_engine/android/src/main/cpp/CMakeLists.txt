cmake_minimum_required(VERSION 3.22)
project(mediahro_engine_jni LANGUAGES CXX)

add_library(mediahro_engine_jni SHARED mediahro_engine_jni.cpp)
target_compile_features(mediahro_engine_jni PRIVATE cxx_std_17)
target_link_libraries(mediahro_engine_jni PRIVATE android log dl)
# 16 KB page alignment (docs/07 §1 rule 4).
target_link_options(mediahro_engine_jni PRIVATE "-Wl,-z,max-page-size=16384")
