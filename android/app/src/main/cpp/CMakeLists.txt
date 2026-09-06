cmake_minimum_required(VERSION 3.22.1)
project(householder_qwen_vl LANGUAGES C CXX)

include(FetchContent)

# Pinned for reproducible Android builds. Update deliberately after native smoke tests.
set(LLAMA_CPP_GIT_TAG "b8078" CACHE STRING "Pinned llama.cpp revision")
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)

FetchContent_Declare(
    llama_cpp
    GIT_REPOSITORY https://github.com/ggml-org/llama.cpp.git
    GIT_TAG ${LLAMA_CPP_GIT_TAG}
    GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(llama_cpp)

# b8078 predates the top-level LLAMA_BUILD_MTMD switch. Add the mtmd
# subdirectory explicitly, but exclude its CLI/deprecation executables from the
# default build. The mtmd library itself is pulled in below as a dependency.
if (NOT TARGET mtmd)
    add_subdirectory(
        ${llama_cpp_SOURCE_DIR}/tools/mtmd
        ${llama_cpp_BINARY_DIR}/tools/mtmd
        EXCLUDE_FROM_ALL
    )
endif()

add_library(householder_qwen_vl SHARED qwen_vision_jni.cpp)
target_compile_features(householder_qwen_vl PRIVATE cxx_std_17)
target_include_directories(householder_qwen_vl PRIVATE
    ${llama_cpp_SOURCE_DIR}/include
    ${llama_cpp_SOURCE_DIR}/ggml/include
    ${llama_cpp_SOURCE_DIR}/tools/mtmd
)
target_link_libraries(householder_qwen_vl PRIVATE llama mtmd android log jnigraphics)
