cmake_minimum_required(VERSION 3.24)

include(FetchContent)

option(LLVM_DEBUG "Builds LLVM in full debug" OFF)

set(LLVM_GIT_REPO "https://github.com/llvm/llvm-project")
set(LLVM_GIT_TAG "llvmorg-15.0.0")
set(LLVM_SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/llvm-project)
set(LLVM_RUNTIME_SOURCE_DIR ${LLVM_SOURCE_DIR}/llvm)
set(LLVM_LLD_SOURCE_DIR ${LLVM_SOURCE_DIR}/lld)
set(LLVM_BUILD_DIR ${CMAKE_CURRENT_SOURCE_DIR}/build)
set(LLVM_INSTALL_DIR ${CMAKE_CURRENT_SOURCE_DIR}/install)

if (LLVM_DEBUG)
    set(CMAKE_BUILD_TYPE Debug)
else ()
    set(CMAKE_BUILD_TYPE RelWithDebInfo)
endif ()

file(TIMESTAMP ${LLVM_BUILD_DIR}/CMakeCache.txt CACHE_MODTIME)
file(TIMESTAMP ${CMAKE_CURRENT_LIST_FILE} LISTS_MODTIME)
message(STATUS "CMakeLists.txt: ${LISTS_MODTIME} CMakeCache.txt: ${CACHE_MODTIME}")
string(COMPARE LESS "${CACHE_MODTIME}" "${LISTS_MODTIME}" LISTS_NEWER)
message(STATUS "CMakeLists.txt is newer than cache")
find_package(LLVM CONFIG QUIET NO_DEFAULT_PATH HINTS ${LLVM_INSTALL_DIR}/lib/cmake/llvm)

if (LISTS_NEWER OR NOT LLVM_FOUND)
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
            -DLLVM_INCLUDE_TOOLS=OFF
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

    message(STATUS "Configuring LLD...")
    file(MAKE_DIRECTORY ${LLVM_BUILD_DIR}/lld)
    execute_process(
            WORKING_DIRECTORY ${LLVM_BUILD_DIR}/lld
            COMMAND_ECHO STDOUT
            COMMAND ${CMAKE_COMMAND}
            -G ${CMAKE_GENERATOR}
            ${LLVM_GENERATOR_TOOLSET}
            ${LLVM_GENERATOR_PLATFORM}
            -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
            -DCMAKE_CXX_STANDARD=${CMAKE_CXX_STANDARD}
            -DCMAKE_INSTALL_PREFIX=${LLVM_INSTALL_DIR}
            -DLLVM_ENABLE_RTTI=ON
            -DLLVM_ENABLE_ASSERTIONS=ON
            -DLLVM_INCLUDE_TESTS=OFF
            ${LLVM_LLD_SOURCE_DIR}
    )

    message(STATUS "Building LLD...")
    execute_process(
            WORKING_DIRECTORY ${LLVM_BUILD_DIR}/lld
            COMMAND_ECHO STDOUT
            COMMAND ${CMAKE_COMMAND} --build . --config ${CMAKE_BUILD_TYPE} --target install
            COMMAND_ERROR_IS_FATAL ANY
    )

    # re-do the find_package now that it should succeed
    find_package(LLVM REQUIRED CONFIG NO_DEFAULT_PATH
            HINTS ${LLVM_INSTALL_DIR}/lib/cmake/llvm)
endif ()

message(STATUS "Found LLVM at ${LLVM_DIR}")
separate_arguments(LLVM_DEFINITIONS_LIST NATIVE_COMMAND ${LLVM_DEFINITIONS})
add_definitions(${LLVM_DEFINITIONS_LIST})
explicit_map_components_to_libraries(LLVM_LIBRARIES bitstreamreader binaryformat remarks mcjit option support core)

macro(copy_pdbs)
    if (MSVC)
        set(LLVM_BUILD_LIBRARY_DIR ${LLVM_BUILD_DIR}/${CMAKE_BUILD_TYPE}/lib)

        foreach (LLVM_LIB ${LLVM_LIBRARIES})
            set(DEST_PDB ${LLVM_INSTALL_DIR}/lib/${LLVM_LIB}.pdb)

            if (NOT EXISTS DEST_PDB)
                message(STATUS "Installing ${LLVM_BUILD_LIBRARY_DIR}/${LLVM_LIB}.pdb -> ${DEST_PDB}")
                execute_process(
                        COMMAND_ECHO STDOUT
                        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${LLVM_BUILD_LIBRARY_DIR}/${LLVM_LIB}.pdb ${DEST_PDB}
                )
            endif ()
        endforeach ()
    endif ()
endmacro()

set(LLVM_INCLUDE_DIRS ${LLVM_INSTALL_DIR}/include CACHE STRING "LLVM Include Directories")
set(LLVM_LIBRARY_DIRS ${LLVM_INSTALL_DIR}/lib CACHE STRING "LLVM Library Directories")
set(LLVM_LIBRARIES ${LLVM_LIBRARIES} CACHE STRING "LLVM libraries selected for linking")

message(STATUS "LLVM includes: ${LLVM_INCLUDE_DIRS}")
message(STATUS "LLVM libraries: ${LLVM_LIBRARIES}")
