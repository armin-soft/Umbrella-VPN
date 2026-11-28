# Project-level configuration for the Umbrella VPN client.
cmake_minimum_required(VERSION 3.14)
project(UmbrellaVPN VERSION "1.0.4" LANGUAGES C CXX)

# The name of the executable created for the application.
set(BINARY_NAME "UmbrellaVPN")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()

# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd4100)
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# ── فایل های اجرایی هسته ────────────────────────────────────────────────────
# موتور هسته یک کتابخانه است (UmbrellaCore.dll در cores\umbrella) و فایل های
# اجرایی لانچرهای نازکی هستند که فقط `parseCli()` را صدا می زنند. اینجا همان
# لانچرها با نام و آیکون آمبرلا ساخته می شوند (native/umbrella_launcher.c).
#
# چرا لانچر خودمان؟ لانچر رسمی موتور، کتابخانه را با پیوند نام صدا می زند و
# نام فایل کتابخانه داخل خود فایل اجرایی نوشته می شود؛ با عوض شدن نام، ویندوز
# فایل اجرایی را با 0xC0000135 (DLL پیدا نشد) می بندد — همان خطای ۱٫۰٫۲. لانچر
# ما کتابخانه را از مسیر بار می کند، پس نام فایل کتابخانه هر چه باشد کار می کند.
# C برای لانچر و RC برای آیکون و متن نسخه فایل های اجرایی.
enable_language(RC)
set(UMBRELLA_LAUNCHER_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/../native/umbrella_launcher.c")
set(UMBRELLA_LAUNCHER_RC "${CMAKE_CURRENT_SOURCE_DIR}/../native/umbrella_launcher.rc")
set(UMBRELLA_FILE_VERSION "${CMAKE_PROJECT_VERSION_MAJOR},${CMAKE_PROJECT_VERSION_MINOR},${CMAKE_PROJECT_VERSION_PATCH},0")

# UmbrellaCli.exe — زیرسیستم کنسول. همین پنجره ای است که هنگام اتصال باز
# می شود و گزارش زنده هسته را نشان می دهد.
add_executable(umbrella_cli "${UMBRELLA_LAUNCHER_SOURCE}" "${UMBRELLA_LAUNCHER_RC}")
target_compile_options(umbrella_cli PRIVATE
  $<$<COMPILE_LANGUAGE:C>:/W3> $<$<COMPILE_LANGUAGE:C>:/utf-8>)
target_compile_definitions(umbrella_cli PRIVATE
  UMBRELLA_FILE_VERSION=${UMBRELLA_FILE_VERSION}
  UMBRELLA_FILE_VERSION_TEXT="${PROJECT_VERSION}.0"
  UMBRELLA_FILE_DESCRIPTION="Umbrella CLI"
  UMBRELLA_INTERNAL_NAME="UmbrellaCli.exe")
target_link_options(umbrella_cli PRIVATE /SUBSYSTEM:CONSOLE /MANIFEST:NO)
set_target_properties(umbrella_cli PROPERTIES OUTPUT_NAME "UmbrellaCli" WIN32_EXECUTABLE OFF)

# UmbrellaAdmin.exe — زیرسیستم گرافیکی با مانیفست requireAdministrator؛ پنجره
# UAC با نام آمبرلا می آید.
add_executable(umbrella_admin "${UMBRELLA_LAUNCHER_SOURCE}" "${UMBRELLA_LAUNCHER_RC}")
target_compile_options(umbrella_admin PRIVATE
  $<$<COMPILE_LANGUAGE:C>:/W3> $<$<COMPILE_LANGUAGE:C>:/utf-8>)
target_compile_definitions(umbrella_admin PRIVATE
  UMBRELLA_LAUNCHER_GUI
  UMBRELLA_FILE_VERSION=${UMBRELLA_FILE_VERSION}
  UMBRELLA_FILE_VERSION_TEXT="${PROJECT_VERSION}.0"
  UMBRELLA_FILE_DESCRIPTION="Umbrella Administrator"
  UMBRELLA_INTERNAL_NAME="UmbrellaAdmin.exe")
# مانیفست دستی ساخته می شود (نه با پیوند)، چون CMake به فایل مانیفست Flutter
# هم یک مانیفست تزریق می کند و دو تا با هم کار نمی کند.
target_link_options(umbrella_admin PRIVATE /SUBSYSTEM:WINDOWS /MANIFEST:NO)
set_target_properties(umbrella_admin PROPERTIES OUTPUT_NAME "UmbrellaAdmin" WIN32_EXECUTABLE ON)

# UmbrellaCoreEngine.exe — زیرسیستم گرافیکی: همان هسته بدون هیچ پنجره کنسولی.
add_executable(umbrella_engine "${UMBRELLA_LAUNCHER_SOURCE}" "${UMBRELLA_LAUNCHER_RC}")
target_compile_options(umbrella_engine PRIVATE
  $<$<COMPILE_LANGUAGE:C>:/W3> $<$<COMPILE_LANGUAGE:C>:/utf-8>)
target_compile_definitions(umbrella_engine PRIVATE
  UMBRELLA_LAUNCHER_GUI
  UMBRELLA_FILE_VERSION=${UMBRELLA_FILE_VERSION}
  UMBRELLA_FILE_VERSION_TEXT="${PROJECT_VERSION}.0"
  UMBRELLA_FILE_DESCRIPTION="Umbrella Core Engine"
  UMBRELLA_INTERNAL_NAME="UmbrellaCoreEngine.exe")
target_link_options(umbrella_engine PRIVATE /SUBSYSTEM:WINDOWS /MANIFEST:NO)
set_target_properties(umbrella_engine PROPERTIES OUTPUT_NAME "UmbrellaCoreEngine" WIN32_EXECUTABLE ON)

# ── مانیفست ────────────────────────────────────────────────────────────────
# UmbrellaAdmin.exe با دسترسی مدیر بالا می آید (همان کاری که لانچر رسمی موتور
# می کند): ویندوز پیش از اجرا پنجره UAC را با نام و آیکون آمبرلا نشان می دهد.
# مانیفست خودمان با mt.exe نشانده می شود، چون CMake مانیفست Flutter را هم به
# فایل های اجرایی تزریق می کند و دو مانیفست با هم نمی سازند.
set(UMBRELLA_MANIFEST "${CMAKE_CURRENT_BINARY_DIR}/umbrella_admin.manifest.xml")
file(WRITE "${UMBRELLA_MANIFEST}" "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>
<assembly xmlns=\"urn:schemas-microsoft-com:asm.v1\" manifestVersion=\"1.0\">
  <trustInfo xmlns=\"urn:schemas-microsoft-com:asm.v3\">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level=\"requireAdministrator\" uiAccess=\"false\"/>
      </requestedPrivileges>
    </security>
  </trustInfo>
  <compatibility xmlns=\"urn:schemas-microsoft-com:compatibility.v1\">
    <application>
      <supportedOS Id=\"{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}\"/>
    </application>
  </compatibility>
</assembly>
")

# mt.exe کنار cl.exe است؛ همان جایی که CMAKE_CXX_COMPILER پیدا شد. نسخه های
# نصب شده هم به عنوان جایگزین جست وجو می شوند.
get_filename_component(UMBRELLA_COMPILER_DIR "${CMAKE_CXX_COMPILER}" DIRECTORY)
find_program(UMBRELLA_MT NAMES mt.exe
  HINTS "${UMBRELLA_COMPILER_DIR}"
  PATHS "C:/Program Files (x86)/Windows Kits/10/bin"
  PATH_SUFFIXES x64)
if(NOT UMBRELLA_MT)
  file(GLOB UMBRELLA_MT_CANDIDATES
    "C:/Program Files (x86)/Windows Kits/10/bin/*/x64/mt.exe")
  if(UMBRELLA_MT_CANDIDATES)
    list(SORT UMBRELLA_MT_CANDIDATES)
    list(GET UMBRELLA_MT_CANDIDATES -1 UMBRELLA_MT)
  endif()
endif()
if(UMBRELLA_MT)
  add_custom_command(TARGET umbrella_admin POST_BUILD
    COMMAND "${UMBRELLA_MT}" -nologo -manifest "${UMBRELLA_MANIFEST}"
            "-outputresource:$<TARGET_FILE:umbrella_admin>;#1"
    COMMENT "Embedding the Umbrella administrator manifest"
    VERBATIM)
else()
  message(WARNING "mt.exe not found: UmbrellaAdmin.exe will not request administrator rights")
endif()

# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} umbrella_cli umbrella_admin umbrella_engine RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the hook/build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
