cmake_minimum_required(VERSION 3.10)

set(EPHEMERAL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/ephemeral")

if(NOT EXISTS "${EPHEMERAL_DIR}/.engine_version")
  # Configure build variables
  set(Flutter_DIR "${EPHEMERAL_DIR}")
  include("${Flutter_DIR}/flutter.cmake")
endif()
