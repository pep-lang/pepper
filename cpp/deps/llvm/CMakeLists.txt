cmake_minimum_required(VERSION 3.7)

include(ExternalProject)

set(LLVM_GIT_REPO "https://github.com/llvm/llvm-project")
set(LLVM_GIT_TAG "llvmorg-15.0.0")
set(LLVM_HOME ${CMAKE_CURRENT_SOURCE_DIR}/llvm-project)

if(NOT DEFINED CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Debug)
endif()

if(${CMAKE_GENERATOR} MATCHES ".* Makefiles")
    # This avoids
    # 'warning: jobserver unavailable: using -j1. Add '+' to parent make rule.'
    set(LLVM_BUILD_COMMAND $(MAKE))
elseif(${CMAKE_GENERATOR} MATCHES "Visual Studio.*")
    set(LLVM_BUILD_COMMAND
        ${CMAKE_COMMAND}
        --build .
        --config $(Configuration)
        --target)
elseif(${CMAKE_GENERATOR} MATCHES "Xcode.*")
    set(LLVM_BUILD_COMMAND
        ${CMAKE_COMMAND}
        --build .
        --config $(CONFIGURATION)
        --target)
else()
    set(LLVM_BUILD_COMMAND
        ${CMAKE_COMMAND}
        --build .
        --target)
endif()

if(BUILD_DEPS)
    ExternalProject_Add(
        llvm_runtime
        GIT_REPOSITORY ${LLVM_GIT_REPO}
        GIT_TAG ${LLVM_GIT_TAG}
        DOWNLOAD_DIR ${LLVM_HOME}
        BINARY_DIR ${LLVM_HOME}/build
        BUILD_COMMAND ${CMAKE_COMMAND} --build <BINARY_DIR> --config $<CONFIG>
        SOURCE_DIR ${LLVM_HOME}
        SOURCE_SUBDIR llvm
        CMAKE_CACHE_ARGS
        -DCMAKE_BUILD_TYPE:STRING=${CMAKE_BUILD_TYPE}
        -DCMAKE_CXX_STANDARD:STRING=${CMAKE_CXX_STANDARD}
        INSTALL_COMMAND ""
        EXCLUDE_FROM_ALL 1)
endif()

find_package(LLVM REQUIRED CONFIG
    PATHS ${LLVM_HOME}/install/lib/cmake/llvm)
message(STATUS "Found LLVM at ${LLVM_DIR}")
llvm_map_components_to_libnames(LLVM_LIBARIES passes mcjit core support option demangle x86 codegen)

set(LLVM_INCLUDE_DIRS ${LLVM_HOME}/install/include CACHE STRING "LLVM Include Directories")
set(LLVM_LIBRARY_DIRS ${LLVM_HOME}/install/lib CACHE STRING "LLVM Library Directories")
set(LLVM_LIBRARIES ${LLVM_LIBRARIES} CACHE STRING "LLVM libraries selected for linking")

message(STATUS "LLVM includes: ${LLVM_INCLUDE_DIRS}")
message(STATUS "LLVM lib dirs: ${LLVM_LIBRARY_DIRS}")
