# CMakeLists.txt (application root)
# Registers our custom SoC/board/devicetree-binding directories with
# Zephyr's build system BEFORE find_package(Zephyr) runs, since that's
# when Zephyr scans these root variables.

cmake_minimum_required(VERSION 3.20.0)

list(APPEND BOARD_ROOT ${CMAKE_CURRENT_SOURCE_DIR})
list(APPEND SOC_ROOT ${CMAKE_CURRENT_SOURCE_DIR})
list(APPEND DTS_ROOT ${CMAKE_CURRENT_SOURCE_DIR})

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(picorv32_zephyr_app)

target_sources(app PRIVATE src/main.c)
