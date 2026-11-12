cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "umbrella_native")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "umbrella_native_plugin")

add_library(${PLUGIN_NAME} SHARED
  "umbrella_native_plugin.cpp"
  "system_ops.cpp"
  "tray_icon.cpp"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON
)

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)
if(MSVC)
  # /WX- keeps third party style warnings from failing an otherwise good build.
  target_compile_options(${PLUGIN_NAME} PRIVATE /utf-8 /W3 /WX-)
endif()

target_link_libraries(${PLUGIN_NAME} PRIVATE iphlpapi ws2_32 wininet shell32 advapi32 ole32 user32 gdi32)

set_target_properties(${PLUGIN_NAME} PROPERTIES
  PREFIX ""
  OUTPUT_NAME "umbrella_native_plugin"
)

list(APPEND PLUGIN_BUNDLED_LIBRARIES $<TARGET_FILE:${PLUGIN_NAME}>)
