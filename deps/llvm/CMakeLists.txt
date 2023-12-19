cmake_minimum_required(VERSION 3.24)

include(FetchContent)

set(LLVM_GIT_REPO "https://github.com/llvm/llvm-project")
set(LLVM_GIT_TAG "llvmorg-17.0.6")
set(LLVM_SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/llvm-project)
set(LLVM_RUNTIME_SOURCE_DIR ${LLVM_SOURCE_DIR}/llvm)
set(LLVM_LLD_SOURCE_DIR ${LLVM_SOURCE_DIR}/lld)
set(LLVM_BUILD_DIR ${CMAKE_CURRENT_SOURCE_DIR}/build)
set(LLVM_INSTALL_DIR ${CMAKE_CURRENT_SOURCE_DIR}/install)

find_package(LLVM CONFIG QUIET NO_DEFAULT_PATH HINTS ${LLVM_INSTALL_DIR}/lib/cmake/llvm)

if (NOT LLVM_FOUND)
    message(STATUS "Syncing LLVM source...")
    FetchContent_Declare(
            llvm_source
            GIT_REPOSITORY ${LLVM_GIT_REPO}
            GIT_TAG ${LLVM_GIT_TAG}
            GIT_PROGRESS 1
            GIT_SHALLOW 1
            SOURCE_DIR ${LLVM_SOURCE_DIR}
    )
    FetchContent_MakeAvailable(llvm_source)

    if (CMAKE_GENERATOR_TOOLSET)
        set(LLVM_GENERATOR_TOOLSET "-Thost=${CMAKE_GENERATOR_TOOLSET}")
    endif ()

    if (CMAKE_GENERATOR_PLATFORM)
        set(LLVM_GENERATOR_PLATFORM "-A ${CMAKE_GENERATOR_PLATFORM}")
    endif ()

    file(MAKE_DIRECTORY ${LLVM_BUILD_DIR})
    message(STATUS "Configuring LLVM...")
    execute_process(
            WORKING_DIRECTORY ${LLVM_BUILD_DIR}
            COMMAND_ECHO STDOUT
            COMMAND ${CMAKE_COMMAND}
            -G ${CMAKE_GENERATOR}
            ${LLVM_GENERATOR_TOOLSET}
            ${LLVM_GENERATOR_PLATFORM}
            -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
            -DCMAKE_CXX_STANDARD=${CMAKE_CXX_STANDARD}
            -DCMAKE_INSTALL_PREFIX=${LLVM_INSTALL_DIR}
            -DLLVM_OPTIMIZED_TABLEGEN=ON
            -DLLVM_ENABLE_RTTI=ON
            "-DLLVM_TARGETS_TO_BUILD=X86"
            -DLLVM_ENABLE_PROJECTS=lld
            -DLLVM_ENABLE_LLD=ON
            -DLLVM_ENABLE_ASSERTIONS=ON
            -DLLVM_INCLUDE_TOOLS=ON
            -DLLVM_INCLUDE_TESTS=OFF
            -DLLVM_INCLUDE_EXAMPLES=OFF
            -DLLVM_INCLUDE_BENCHMARKS=OFF
            ${LLVM_RUNTIME_SOURCE_DIR}
    )
    message(STATUS "Building LLVM...")
    execute_process(
            WORKING_DIRECTORY ${LLVM_BUILD_DIR}
            COMMAND_ECHO STDOUT
            COMMAND ${CMAKE_COMMAND} --build . --config ${CMAKE_BUILD_TYPE} --target install
            COMMAND_ERROR_IS_FATAL ANY
    )

    find_package(LLVM REQUIRED CONFIG NO_DEFAULT_PATH
            HINTS ${LLVM_INSTALL_DIR}/lib/cmake/llvm)
endif ()

message(STATUS "Found LLVM at ${LLVM_DIR}")
separate_arguments(LLVM_DEFINITIONS_LIST NATIVE_COMMAND ${LLVM_DEFINITIONS})
add_definitions(${LLVM_DEFINITIONS_LIST})
explicit_map_components_to_libraries(LLVM_LIBRARIES windowsmanifest bitstreamreader binaryformat remarks mcjit option support core)
set(LLVM_INCLUDE_DIRS ${LLVM_INSTALL_DIR}/include CACHE STRING "LLVM Include Directories")
set(LLVM_LIBRARY_DIRS ${LLVM_INSTALL_DIR}/lib CACHE STRING "LLVM Library Directories")
set(LLVM_LIBRARIES ${LLVM_LIBRARIES} CACHE STRING "LLVM libraries selected for linking")
set(LLVM_BINARIES_DIR ${LLVM_INSTALL_DIR}/bin CACHE STRING "LLVM binaries")

message(STATUS "LLVM includes:  ${LLVM_INCLUDE_DIRS}")
message(STATUS "LLVM libraries: ${LLVM_LIBRARIES}")
message(STATUS "LLVM binaries:  ${LLVM_BINARIES_DIR}")
message(STATUS "Found LLD at ${LLD_INSTALL_PREFIX}")

