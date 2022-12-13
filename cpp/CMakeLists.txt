cmake_minimum_required(VERSION 3.21)
project(Pepper VERSION 0.1.0)

option(BUILD_DEPS "Build dependencies, should only need to be done once" OFF)

set(CMAKE_CXX_STANDARD 20)
set(GLOBAL PROPERTY USE_FOLDERS ON)

include(CTest)
enable_testing()

if(MSVC)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /EHsc")
endif()

add_subdirectory(deps)
include_directories(${LLVM_INCLUDE_DIRS})
link_directories(${LLVM_LIBRARY_DIRS})
link_libraries(${LLVM_LIBRARIES})

add_subdirectory(grammar)
include_directories(${PARSER_INCLUDE_DIRS} ${ANTLR4_INCLUDE_DIRS})
link_libraries(PepperParser)

set(COMPILER_SRC
    source/main.cpp
    source/Core/RTTI.h
    source/Compiler/Codegen.h
    source/Compiler/Codegen.cpp
    source/Compiler/Compiler.h
    source/Compiler/Compiler.cpp
    source/Compiler/Context.h
    source/Compiler/Context.cpp
    source/Compiler/Function.h
    source/Compiler/Function.cpp
    source/Compiler/Parser.h
    source/Compiler/Parser.cpp
    source/Compiler/Scope.h
    source/Compiler/Scope.cpp
    source/Compiler/Type.h
    source/Compiler/Type.cpp
    source/Compiler/Value.h
    source/Compiler/Value.cpp)

source_group(
    TREE ${CMAKE_CURRENT_SOURCE_DIR}
    FILES ${COMPILER_SRC})

add_executable(Pepper
    ${COMPILER_SRC}
    source/main.cpp)
add_dependencies(Pepper PepperParser)
target_include_directories(Pepper PUBLIC source)

set(CPACK_PROJECT_NAME ${PROJECT_NAME})
set(CPACK_PROJECT_VERSION ${PROJECT_VERSION})
include(CPack)
