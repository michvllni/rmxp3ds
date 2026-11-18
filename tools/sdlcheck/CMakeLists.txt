# SPDX-License-Identifier: GPL-3.0-or-later
# M3 check of the 3DS SDL2 utility libraries built by runtime/3ds/deps/build.sh.
# Build: runtime/3ds/deps/build.sh first, then
#   cmake -S tools/sdlcheck -B build/sdlcheck -G Ninja -DCMAKE_TOOLCHAIN_FILE="$DEVKITPRO/cmake/3DS.cmake"
#   cmake --build build/sdlcheck
cmake_minimum_required(VERSION 3.18) # find_program(... REQUIRED)
project(rmxp3ds_sdlcheck C)

set(DEPS3DS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../runtime/build-3ds/deps/prefix"
    CACHE PATH "Install prefix of runtime/3ds/deps/build.sh")
get_filename_component(DEPS3DS_DIR "${DEPS3DS_DIR}" ABSOLUTE)
foreach(f lib/libSDL2.a lib/libSDL2_image.a lib/libSDL2_ttf.a include/SDL2/SDL.h)
  if(NOT EXISTS "${DEPS3DS_DIR}/${f}")
    message(FATAL_ERROR "${DEPS3DS_DIR}/${f} missing: run runtime/3ds/deps/build.sh first")
  endif()
endforeach()
find_program(HOST_RUBY ruby REQUIRED)
# libpng and libjpeg (SDL2_image) and FreeType (SDL2_ttf) from devkitPro's 3DS portlibs, FreeType
# with its static dependencies from its pkg-config file.
find_package(PkgConfig REQUIRED)
pkg_check_modules(FREETYPE REQUIRED freetype2)

add_executable(sdlcheck main.c)
target_compile_options(sdlcheck PRIVATE -Wall -Wextra -Werror -std=gnu17)
target_include_directories(sdlcheck SYSTEM PRIVATE "${DEPS3DS_DIR}/include/SDL2")
target_link_libraries(sdlcheck PRIVATE
  "${DEPS3DS_DIR}/lib/libSDL2_ttf.a"
  "${DEPS3DS_DIR}/lib/libSDL2_image.a"
  "${DEPS3DS_DIR}/lib/libSDL2.a"
  png16 jpeg ${FREETYPE_STATIC_LDFLAGS} m)

# romfs: the generated test image and the runtime's bundled font (Liberation Sans, SIL OFL 1.1,
# runtime/assets; copied at build time, not stored here).
set(ROMFS_DIR "${CMAKE_CURRENT_BINARY_DIR}/romfs")
set(FONT "${CMAKE_CURRENT_SOURCE_DIR}/../../runtime/assets/liberation.ttf")
set(ROMFS_FILES "${ROMFS_DIR}/check.png" "${ROMFS_DIR}/liberation.ttf")
add_custom_command(
  OUTPUT ${ROMFS_FILES}
  COMMAND ${CMAKE_COMMAND} -E make_directory "${ROMFS_DIR}"
  COMMAND "${HOST_RUBY}" "${CMAKE_CURRENT_SOURCE_DIR}/make-png.rb" --out "${ROMFS_DIR}/check.png"
  COMMAND ${CMAKE_COMMAND} -E copy "${FONT}" "${ROMFS_DIR}/liberation.ttf"
  DEPENDS make-png.rb "${FONT}"
  COMMENT "Staging romfs")
add_custom_target(sdlcheck_romfs_files DEPENDS ${ROMFS_FILES})
dkp_add_asset_target(sdlcheck_romfs "${ROMFS_DIR}")
add_dependencies(sdlcheck_romfs sdlcheck_romfs_files)
set_property(TARGET sdlcheck_romfs APPEND PROPERTY DKP_ASSET_FILES ${ROMFS_FILES})

ctr_generate_smdh(sdlcheck.smdh
  NAME "rmxp3ds SDL check"
  DESCRIPTION "SDL2 utility libraries test (M3)"
  AUTHOR "rmxp3ds")
ctr_create_3dsx(sdlcheck SMDH sdlcheck.smdh ROMFS sdlcheck_romfs)
