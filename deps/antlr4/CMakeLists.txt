cmake_minimum_required(VERSION 3.24)

include(FetchContent)

if (NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE RelWithDebInfo)
endif ()

if (NOT DEFINED ANTLR4_WITH_STATIC_CRT)
    set(ANTLR4_WITH_STATIC_CRT OFF)
endif ()

set(ANTLR4_SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/antlr4)
set(ANTLR4_RUNTIME_SOURCE_DIR ${ANTLR4_SOURCE_DIR}/runtime/Cpp)
set(ANTLR4_BUILD_DIR ${CMAKE_CURRENT_SOURCE_DIR}/build)
set(ANTLR4_INSTALL_DIR ${CMAKE_CURRENT_SOURCE_DIR}/install)
set(ANTLR4_GIT_REPOSITORY https://github.com/antlr/antlr4.git)

if (NOT DEFINED ANTLR4_TAG)
    # Set to branch name to keep library updated at the cost of needing to rebuild after 'clean'
    # Set to commit hash to keep the build stable and does not need to rebuild after 'clean'
    set(ANTLR4_TAG master)
endif ()

# Ensure that the include dir already exists at configure time (to avoid cmake erroring
# on non-existent include dirs)
# file(MAKE_DIRECTORY "${ANTLR4_INCLUDE_DIRS}")
if (MSVC)
    set(ANTLR4_STATIC_LIBRARIES
            ${ANTLR4_INSTALL_DIR}/lib/antlr4-runtime-static.lib)
    set(ANTLR4_SHARED_LIBRARIES
            ${ANTLR4_INSTALL_DIR}/lib/antlr4-runtime.lib)
    set(ANTLR4_RUNTIME_LIBRARIES
            ${ANTLR4_INSTALL_DIR}/bin/antlr4-runtime.dll)
else ()
    set(ANTLR4_STATIC_LIBRARIES
            ${ANTLR4_INSTALL_DIR}/lib/libantlr4-runtime.a)

    if (MINGW)
        set(ANTLR4_SHARED_LIBRARIES
                ${ANTLR4_INSTALL_DIR}/lib/libantlr4-runtime.dll.a)
        set(ANTLR4_RUNTIME_LIBRARIES
                ${ANTLR4_INSTALL_DIR}/lib/libantlr4-runtime.dll)
    elseif (CYGWIN)
        set(ANTLR4_SHARED_LIBRARIES
                ${ANTLR4_INSTALL_DIR}/lib/libantlr4-runtime.dll.a)
        set(ANTLR4_RUNTIME_LIBRARIES
                ${ANTLR4_INSTALL_DIR}/lib/cygantlr4-runtime-4.11.1.dll)
    elseif (APPLE)
        set(ANTLR4_RUNTIME_LIBRARIES
                ${ANTLR4_INSTALL_DIR}/lib/libantlr4-runtime.dylib)
    else ()
        set(ANTLR4_RUNTIME_LIBRARIES
                ${ANTLR4_INSTALL_DIR}/lib/libantlr4-runtime.so)
    endif ()
endif ()

if ((MSVC AND NOT EXISTS ANTLR4_RUNTIME_LIBRARIES) OR (NOT MSVC AND NOT EXISTS ANTLR4_STATIC_LIBRARIES))
    message(STATUS "Syncing ANTLR4 sources...")
    FetchContent_Declare(
            antlr4_source
            GIT_REPOSITORY ${ANTLR4_GIT_REPOSITORY}
            GIT_TAG ${ANTLR4_TAG}
            SOURCE_DIR ${ANTLR4_SOURCE_DIR}
    )
    FetchContent_MakeAvailable(antlr4_source)
    message(STATUS "Configuring ANTLR4 Runtime...")

    if (CMAKE_GENERATOR_TOOLSET)
        set(ANTLR4_GENERATOR_TOOLSET "-Thost=${CMAKE_GENERATOR_TOOLSET}")
    endif ()

    if (CMAKE_GENERATOR_PLATFORM)
        set(ANTLR4_GENERATOR_PLATFORM "-A ${CMAKE_GENERATOR_PLATFORM}")
    endif ()

    file(MAKE_DIRECTORY ${ANTLR4_BUILD_DIR})
    execute_process(
            WORKING_DIRECTORY ${ANTLR4_BUILD_DIR}
            COMMAND_ECHO STDOUT
            COMMAND ${CMAKE_COMMAND}
            -G ${CMAKE_GENERATOR}
            ${ANTLR4_GENERATOR_TOOLSET}
            ${ANTLR4_GENERATOR_PLATFORM}
            -Wno-dev
            -Wno-deprecated
            -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
            -DCMAKE_CXX_STANDARD=${CMAKE_CXX_STANDARD}
            -DWITH_STATIC_CRT=${ANTLR4_WITH_STATIC_CRT}
            -DCMAKE_INSTALL_PREFIX=${ANTLR4_INSTALL_DIR}
            ${ANTLR4_RUNTIME_SOURCE_DIR}
            COMMAND_ERROR_IS_FATAL ANY
    )

    message(STATUS "Building ANTLR4 Runtime...")
    execute_process(
            WORKING_DIRECTORY ${ANTLR4_BUILD_DIR}
            COMMAND_ECHO STDOUT
            COMMAND ${CMAKE_COMMAND} --build . --config ${CMAKE_BUILD_TYPE} --target install
            COMMAND_ERROR_IS_FATAL ANY
    )
endif ()

set(ANTLR4_INCLUDE_DIRS ${ANTLR4_INSTALL_DIR}/include/antlr4-runtime)

add_library(antlr4_shared SHARED IMPORTED GLOBAL)
set_target_properties(antlr4_shared PROPERTIES
        IMPORTED_LOCATION ${ANTLR4_RUNTIME_LIBRARIES}
        LINKER_LANGUAGE CXX)
target_include_directories(antlr4_shared
        INTERFACE
        ${ANTLR4_INCLUDE_DIRS}
        )

if (ANTLR4_SHARED_LIBRARIES)
    set_target_properties(antlr4_shared PROPERTIES
            IMPORTED_IMPLIB ${ANTLR4_SHARED_LIBRARIES})
endif ()

add_library(antlr4_static STATIC IMPORTED GLOBAL)
set_target_properties(antlr4_static PROPERTIES
        IMPORTED_LOCATION ${ANTLR4_STATIC_LIBRARIES})
target_include_directories(antlr4_static
        INTERFACE
        ${ANTLR4_INCLUDE_DIRS}
        )

set(ANTLR4_INCLUDE_DIRS ${ANTLR4_INCLUDE_DIRS} CACHE STRING "ANTLR4 include dirs")
set(ANTLR4_SHARED_LIBRARIES ${ANTLR4_SHARED_LIBRARIES} CACHE STRING "ANTLR4 shared library")
set(ANTLR4_STATIC_LIBRARIES ${ANTLR4_STATIC_LIBRARIES} CACHE STRING "ANTLR4 static library")
set(ANTLR4_RUNTIME_LIBRARIES ${ANTLR4_RUNTIME_LIBRARIES} CACHE STRING "ANTLR4 DLL/.so")

message(STATUS "ANTLR4 Include dirs: ${ANTLR4_INCLUDE_DIRS}")
message(STATUS "ANTLR4 Shared libs:  ${ANTLR4_SHARED_LIBRARIES}")
message(STATUS "ANTLR4 Runtime libs: ${ANTLR4_RUNTIME_LIBRARIES}")
message(STATUS "ANTLR4 Static libs:  ${ANTLR4_STATIC_LIBRARIES}")
