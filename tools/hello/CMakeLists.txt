# SPDX-License-Identifier: GPL-3.0-or-later
# Build: cmake -S tools/hello -B build/hello -G Ninja \
#          -DCMAKE_TOOLCHAIN_FILE="$DEVKITPRO/cmake/3DS.cmake" && cmake --build build/hello
cmake_minimum_required(VERSION 3.13)
project(rmxp3ds_hello C)

add_executable(hello main.c)
target_compile_options(hello PRIVATE -Wall -Wextra -Werror)

ctr_generate_smdh(hello.smdh
  NAME "rmxp3ds hello"
  DESCRIPTION "rmxp3ds M0 toolchain test"
  AUTHOR "rmxp3ds"
)
ctr_create_3dsx(hello SMDH hello.smdh)
