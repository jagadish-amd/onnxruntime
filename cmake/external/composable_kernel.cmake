set(PATCH_CLANG ${PROJECT_SOURCE_DIR}/patches/composable_kernel/Fix_Clang_Build.patch)

include(FetchContent)
FetchContent_Declare(composable_kernel
  URL ${DEP_URL_composable_kernel}
  URL_HASH SHA1=${DEP_SHA1_composable_kernel}
  PATCH_COMMAND ${Patch_EXECUTABLE} --binary --ignore-whitespace -p1 < ${PATCH_CLANG}
)

FetchContent_GetProperties(composable_kernel)
if(NOT composable_kernel_POPULATED)
  FetchContent_Populate(composable_kernel)
  include(ExternalProject)

set(composable_kernel_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../build/RelWithDebInfo/_deps/composable_kernel-src")
set(composable_kernel_BINARY_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../build/RelWithDebInfo/_deps/composable_kernel-build")
message("${composable_kernel_SOURCE_DIR} ${composable_kernel_BINARY_DIR}")
ExternalProject_Add(composable_kernel_external
    PREFIX composable_kernel
    SOURCE_DIR ${composable_kernel_SOURCE_DIR}
    BINARY_DIR ${composable_kernel_BINARY_DIR}
    CMAKE_ARGS
        -DCMAKE_INSTALL_PREFIX=${composable_kernel_BINARY_DIR}
        -DGPU_ARCHS=${CMAKE_HIP_ARCHITECTURES}
        -DGPU_TARGETS=""
        -DCMAKE_CXX_COMPILER=/opt/rocm/llvm/bin/clang++
        -DBUILD_DEV=OFF
        #-DTYPES="fp32;fp16;bf16;fp8"
        #-DINSTANCES_ONLY=ON
    INSTALL_COMMAND ""
    UPDATE_COMMAND ""
    TEST_COMMAND ""
)

add_library(onnxruntime_composable_kernel_includes INTERFACE)
target_include_directories(onnxruntime_composable_kernel_includes INTERFACE
    ${composable_kernel_SOURCE_DIR}/include
    ${composable_kernel_BINARY_DIR}/include
    ${composable_kernel_SOURCE_DIR}/library/include)
target_compile_definitions(onnxruntime_composable_kernel_includes INTERFACE __fp32__ __fp16__ __bf16__)

execute_process(
    COMMAND ${Python3_EXECUTABLE} ${composable_kernel_SOURCE_DIR}/example/ck_tile/01_fmha/generate.py
    -r 2 --list_blobs ${composable_kernel_BINARY_DIR}/blob_list.txt
    COMMAND_ERROR_IS_FATAL ANY
)

file(STRINGS ${composable_kernel_BINARY_DIR}/blob_list.txt generated_fmha_srcs)

add_custom_command(
    OUTPUT ${generated_fmha_srcs}
    COMMAND ${Python3_EXECUTABLE} ${composable_kernel_SOURCE_DIR}/example/ck_tile/01_fmha/generate.py -r 2 --output_dir ${composable_kernel_BINARY_DIR}
    DEPENDS ${composable_kernel_SOURCE_DIR}/example/ck_tile/01_fmha/generate.py ${composable_kernel_BINARY_DIR}/blob_list.txt composable_kernel_external
)

set_source_files_properties(${generated_fmha_srcs} PROPERTIES LANGUAGE HIP GENERATED TRUE)
add_custom_target(gen_fmha_srcs DEPENDS ${generated_fmha_srcs}) # dummy target for dependencies

set(fmha_srcs
    ${generated_fmha_srcs}
    ${composable_kernel_SOURCE_DIR}/example/ck_tile/01_fmha/fmha_fwd.cpp
    ${composable_kernel_SOURCE_DIR}/example/ck_tile/01_fmha/fmha_fwd.hpp
    ${composable_kernel_SOURCE_DIR}/example/ck_tile/01_fmha/bias.hpp
    ${composable_kernel_SOURCE_DIR}/example/ck_tile/01_fmha/mask.hpp
)

add_library(onnxruntime_composable_kernel_fmha STATIC EXCLUDE_FROM_ALL ${generated_fmha_srcs})
target_link_libraries(onnxruntime_composable_kernel_fmha PUBLIC onnxruntime_composable_kernel_includes)
target_include_directories(onnxruntime_composable_kernel_fmha PUBLIC ${composable_kernel_SOURCE_DIR}/example/ck_tile/01_fmha)
add_dependencies(onnxruntime_composable_kernel_fmha gen_fmha_srcs)
add_dependencies(onnxruntime_composable_kernel_fmha composable_kernel_external)

# ck tile only supports MI200+ GPUs at the moment
get_target_property(archs onnxruntime_composable_kernel_fmha HIP_ARCHITECTURES)
string(REPLACE "," ";" archs "${archs}")
set(original_archs ${archs})
list(FILTER archs INCLUDE REGEX "(gfx942|gfx90a)")
if (NOT original_archs EQUAL archs)
    message(WARNING "ck tile only supports archs: ${archs} among the originally specified ${original_archs}")
endif()
set_target_properties(onnxruntime_composable_kernel_fmha PROPERTIES HIP_ARCHITECTURES "${archs}")
endif()

