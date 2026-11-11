cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

set(BINARY_NAME "umbrella_vpn")
set(APPLICATION_ID "ir.umbrella.vpn")

cmake_policy(SET CMP0063 NEW)

add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

apply_standard_settings(${BINARY_NAME})

target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")
target_compile_definitions(${BINARY_NAME} PRIVATE "UNICODE" "_UNICODE")

if(MSVC)
  # Keywords and strings in the sources are UTF-8 (Persian menu labels).
  target_compile_options(${BINARY_NAME} PRIVATE /utf-8)
endif()

target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE user32 gdi32 shell32 ole32 advapi32 wininet iphlpapi ws2_32)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

add_dependencies(${BINARY_NAME} flutter_assemble)

set_target_properties(${BINARY_NAME} PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/runner"
)

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}" COMPONENT Runtime)
