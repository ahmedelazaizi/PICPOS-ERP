# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(ural_erp LANGUAGES CXX)

# ── هوية المنتج ────────────────────────────────────────────────────────────
#
# المشروع بيطلّع أكتر من منتج مستقل من نفس الكود (UralCash / PicPos). القيم
# دي بتحدد اسم الملف التنفيذي وبيانات ملف الـ exe، وبتتقري من **متغيرات
# البيئة** اللي سكربت بناء العلامة بيظبطها قبل ما ينادي flutter build.
#
# ليه متغيرات بيئة وليه `--dart-define`؟ لأن `--dart-define` بيوصل لكود Dart
# بس ومبيوصلش لـ CMake خالص، والحاجات دي بتتحدد وقت الترجمة الأصلية.
#
# الافتراضي UralCash عشان أي بناء قديم أو تشغيل من الـ IDE يفضل شغال زي ما هو.
#
# ⚠ الـ CMake cache بيحتفظ بالقيم دي. تبديل العلامة في نفس مجلد البناء بيخلّي
#   ناتج مختلط — عشان كده سكربتات البناء بتمسح مجلد البناء الأول.
if(DEFINED ENV{BRAND_BINARY_NAME})
  set(BINARY_NAME "$ENV{BRAND_BINARY_NAME}")
else()
  set(BINARY_NAME "UralCash")
endif()

if(DEFINED ENV{BRAND_PRODUCT_NAME})
  set(BRAND_PRODUCT_NAME "$ENV{BRAND_PRODUCT_NAME}")
else()
  set(BRAND_PRODUCT_NAME "UralCash ERP")
endif()

# الكيان القانوني الظاهر في «خصائص الملف» وسطر حقوق النشر. لازم يكون الاسم
# المسجَّل للجهة اللي بتوزّع المنتج — منتج بيتباع لعميل تحت كيان مختلف
# مينفعش يحمل اسم كيان تاني.
if(DEFINED ENV{BRAND_COMPANY_NAME})
  set(BRAND_COMPANY_NAME "$ENV{BRAND_COMPANY_NAME}")
else()
  set(BRAND_COMPANY_NAME "Monexia")
endif()

message(STATUS "Brand: BINARY_NAME=${BINARY_NAME} PRODUCT_NAME=${BRAND_PRODUCT_NAME} COMPANY=${BRAND_COMPANY_NAME}")

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

# Spec 135 — toolchain compatibility for newer MSVC v14x toolsets (VS 18 /
# MSVC 14.51+). Those toolsets promote the <experimental/coroutine> deprecation
# (STL1011) to a hard static_assert, which breaks third-party plugins that still
# include it (e.g. audioplayers_windows). Microsoft's own message says to define
# this macro to opt out. Set at directory scope BEFORE the flutter/runner/plugin
# subdirectories are added (below) so it propagates to every plugin target —
# this is the permanent, in-repo replacement for the per-shell
# `CL=/D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` workaround. Harmless
# on older toolsets that don't emit the assertion.
add_definitions(-D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /wd"4100" /utf-8)
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

# Spec 002 Round 7: Suppress benign upstream warnings in SQLCipher's bundled
# SQLite source (sqlite3.vcxproj from sqlcipher_flutter_libs).
#
#   C4267 'size_t'→'int' conversion (lines 108807/108811/108874): legitimate
#         in upstream code where caller-side bounds guarantee no overflow.
#   C4101 unreferenced local variable 'rc' (line 128196): harmless dead
#         assignment in an error-path branch.
#
# These cannot be fixed without patching the third-party plugin (out of
# our control per Constitution Principle I — preserve upstream behavior).
# Wrapping in `if(TARGET ...)` keeps the build robust if a future plugin
# version renames or removes the target.
if(TARGET sqlite3)
  target_compile_options(sqlite3 PRIVATE /wd4267 /wd4101)
endif()


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

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
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

# Copy the native assets provided by the build.dart from all packages.
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

# Bundle AclasSDK for scale communication (Rongta/Aclas label scales).
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/aclas_sdk/AclasSDK.dll"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/aclas_sdk/AclasSDK.ini"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)
