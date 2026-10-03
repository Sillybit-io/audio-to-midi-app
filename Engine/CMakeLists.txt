cmake_minimum_required(VERSION 3.25)
project(sillymidi_engine LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(MUSCRIPTOR_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(MUSCRIPTOR_BUILD_BENCH OFF CACHE BOOL "" FORCE)

add_subdirectory(muscriptor.cpp/cpp muscriptor EXCLUDE_FROM_ALL)

add_executable(sillymidi-engine src/main.cpp)
target_link_libraries(sillymidi-engine PRIVATE muscriptor_ggml)
muscriptor_add_metal_library(sillymidi-engine)
if(MSVC)
    target_compile_options(sillymidi-engine PRIVATE /W4)
else()
    target_compile_options(sillymidi-engine PRIVATE -Wall -Wextra -Wpedantic)
endif()
