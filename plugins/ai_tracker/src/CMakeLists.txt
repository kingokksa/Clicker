cmake_minimum_required(VERSION 3.18.1)
project(ai_tracker)

set(CMAKE_CXX_STANDARD 17)

add_library(ai_tracker SHARED main.cpp)

target_compile_definitions(ai_tracker PRIVATE PLUGIN_EXPORTS)

find_package(onnxruntime REQUIRED)
target_link_libraries(ai_tracker onnxruntime)
