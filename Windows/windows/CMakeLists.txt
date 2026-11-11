cmake_minimum_required(VERSION 3.14)
project(umbrella_vpn VERSION "1.0.0" LANGUAGES CXX)

set(BINARY_NAME "umbrella_vpn")
set(APPLICATION_ID "ir.umbrella.vpn")

cmake_policy(SET CMP0063 NEW)

set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# Configure build options.
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Debug" CACHE STRING "Flutter build mode" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS "Debug" "Profile" "Release")
endif()

function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_options(${TARGET} PRIVATE /utf-8)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")

# Flutter library and tool build rules.
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place.
install(CODE "
  set(BUILD_BUNDLE_DIR \"${CMAKE_BINARY_DIR}\")
  set(INSTALL_BUNDLE_LIB_DIR \"\${CMAKE_INSTALL_PREFIX}\")

  include(\"${FLUTTER_MANAGED_DIR}/cmake_install.cmake\")
")

foreach(BUNDLED_LIBRARY ${PLUGIN_BUNDLED_LIBRARIES})
  if(CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS)
    file(INSTALL "${CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS}" DESTINATION "${CMAKE_INSTALL_PREFIX}")
  endif()
  get_filename_component(BUNDLED_LIBRARY_FULL_PATH "${BUNDLED_LIBRARY}" ABSOLUTE)
  get_filename_component(BUNDLED_LIBRARY_FILE_NAME "${BUNDLED_LIBRARY_FULL_PATH}" NAME)
  install(FILES "${BUNDLED_LIBRARY_FULL_PATH}" DESTINATION "${CMAKE_INSTALL_PREFIX}" COMPONENT Runtime)
endforeach()
