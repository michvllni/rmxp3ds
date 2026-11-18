# SPDX-License-Identifier: GPL-3.0-or-later
# M1 Ruby test/benchmark app: embeds CRuby built by runtime/3ds/ruby/build.sh.
# Build: runtime/3ds/ruby/build.sh first, then
#   cmake -S tools/bench -B build/bench -G Ninja -DCMAKE_TOOLCHAIN_FILE="$DEVKITPRO/cmake/3DS.cmake"
#   cmake --build build/bench
cmake_minimum_required(VERSION 3.13)
project(rmxp3ds_bench C)

set(RUBY3DS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../runtime/build-3ds/ruby"
    CACHE PATH "Output directory of runtime/3ds/ruby/build.sh")
get_filename_component(RUBY3DS_DIR "${RUBY3DS_DIR}" ABSOLUTE)
foreach(f build/libruby-static.a build/ext/extinit.a build/ext/zlib/zlib.a build/enc/encinit.a
          build/enc/libenc.a build/enc/libtrans.a shim/librb3dsshim.a)
  if(NOT EXISTS "${RUBY3DS_DIR}/${f}")
    message(FATAL_ERROR "${RUBY3DS_DIR}/${f} missing: run runtime/3ds/ruby/build.sh first")
  endif()
endforeach()
find_program(HOST_RUBY ruby REQUIRED)

add_executable(bench main.c)
target_compile_options(bench PRIVATE -Wall -Wextra -Werror -std=gnu17)
target_include_directories(bench SYSTEM PRIVATE
  "${RUBY3DS_DIR}/build/.ext/include/arm-eabi"
  "${RUBY3DS_DIR}/src/include")
# Ruby's static libraries reference each other; a link group resolves any order.
target_link_libraries(bench PRIVATE
  -Wl,--start-group
  "${RUBY3DS_DIR}/build/ext/extinit.a"
  "${RUBY3DS_DIR}/build/ext/zlib/zlib.a"
  "${RUBY3DS_DIR}/build/enc/encinit.a"
  "${RUBY3DS_DIR}/build/enc/libenc.a"
  "${RUBY3DS_DIR}/build/enc/libtrans.a"
  "${RUBY3DS_DIR}/build/libruby-static.a"
  "${RUBY3DS_DIR}/shim/librb3dsshim.a"
  -Wl,--end-group
  z m)

# romfs: test scripts + a synthetic fixture generated with the host Ruby (same version).
set(ROMFS_DIR "${CMAKE_CURRENT_BINARY_DIR}/romfs")
set(ROMFS_FILES "${ROMFS_DIR}/bench.rb" "${ROMFS_DIR}/rgss_stubs.rb" "${ROMFS_DIR}/Map001.rxdata")
add_custom_command(
  OUTPUT ${ROMFS_FILES}
  COMMAND ${CMAKE_COMMAND} -E make_directory "${ROMFS_DIR}"
  COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_CURRENT_SOURCE_DIR}/romfs/bench.rb" "${ROMFS_DIR}/bench.rb"
  COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_CURRENT_SOURCE_DIR}/romfs/rgss_stubs.rb" "${ROMFS_DIR}/rgss_stubs.rb"
  COMMAND "${HOST_RUBY}" "${CMAKE_CURRENT_SOURCE_DIR}/../../tests/fixtures/make-rxdata.rb"
          --out "${ROMFS_DIR}/Map001.rxdata"
  DEPENDS romfs/bench.rb romfs/rgss_stubs.rb ../../tests/fixtures/make-rxdata.rb
  COMMENT "Staging romfs")
add_custom_target(bench_romfs_files DEPENDS ${ROMFS_FILES})
dkp_add_asset_target(bench_romfs "${ROMFS_DIR}")
add_dependencies(bench_romfs bench_romfs_files)
set_property(TARGET bench_romfs APPEND PROPERTY DKP_ASSET_FILES ${ROMFS_FILES})

ctr_generate_smdh(bench.smdh
  NAME "rmxp3ds Ruby bench"
  DESCRIPTION "CRuby test + benchmarks (M1)"
  AUTHOR "rmxp3ds")
ctr_create_3dsx(bench SMDH bench.smdh ROMFS bench_romfs)
