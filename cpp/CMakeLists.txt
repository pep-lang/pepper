cmake_minimum_required(VERSION 3.21)
project(Pepper VERSION 0.1.0)

set(CMAKE_CXX_STANDARD 17)

include(CTest)
enable_testing()

if(MSVC)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /EHsc")
endif()

# LLVM runtime
find_package(LLVM REQUIRED CONFIG
    PATHS ${PROJECT_SOURCE_DIR}/llvm-project/build/lib/cmake/llvm)
message(STATUS "Found LLVM at ${LLVM_DIR}")
llvm_map_components_to_libnames(llvm_libs Passes MCJIT Core Support)
link_libraries(${llvm_libs})

if("" STREQUAL "${LLVM_LIBRARY_DIRS}")
    set(LLVM_HOME ${LLVM_DIR}/../../..)
    set(LLVM_BUILD ${LLVM_HOME}/build)
    set(LLVM_INCLUDE_DIRS ${LLVM_HOME}/llvm/include)
    set(LLVM_LIBRARY_DIRS ${LLVM_BUILD}/Debug/lib)
    file(REAL_PATH ${LLVM_INCLUDE_DIRS} LLVM_INCLUDE_DIRS)
    file(REAL_PATH ${LLVM_LIBRARY_DIRS} LLVM_LIBRARY_DIRS)
endif()

message(STATUS "LLVM_INCLUDE_DIRS=${LLVM_INCLUDE_DIRS}")
message(STATUS "LLVM_LIBRARY_DIRS=${LLVM_LIBRARY_DIRS}")

include_directories(${LLVM_INCLUDE_DIRS})
link_directories(${LLVM_LIBRARY_DIRS})

# ANTLR4 runtime
include(cmake/ExternalAntlr4Cpp.cmake)
include_directories(${ANTLR4_INCLUDE_DIRS})
link_libraries(antlr4_shared)

# ${CMAKE_BINARY_DIR}/antlr4_runtime/src/antlr4_runtime/runtime/Cpp/runtime/src

# ANTLR4 tool
find_package(Java COMPONENTS Runtime REQUIRED)
set(ANTLR_JAR "${CMAKE_BINARY_DIR}/antlr4.jar")
file(DOWNLOAD "https://www.antlr.org/download/antlr-4.11.1-complete.jar" "${ANTLR_JAR}")

# Generate source files
add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/source/parser/PepperLexer.h ${CMAKE_BINARY_DIR}/source/parser/PepperLexer.cpp
    ${CMAKE_BINARY_DIR}/source/parser/PepperParser.h ${CMAKE_BINARY_DIR}/source/parser/PepperParser.cpp
    ${CMAKE_BINARY_DIR}/source/parser/PepperListener.h ${CMAKE_BINARY_DIR}/source/parser/PepperListener.cpp
    ${CMAKE_BINARY_DIR}/source/parser/PepperBaseListener.h ${CMAKE_BINARY_DIR}/source/parser/PepperBaseListener.cpp
    COMMAND ${CMAKE_COMMAND} -E make_directory source/parser
    COMMAND ${Java_JAVA_EXECUTABLE} -jar ${ANTLR_JAR} -o ${CMAKE_BINARY_DIR}/source/parser -package "Pepper::Parser" -Dlanguage=Cpp Pepper.g4
    MAIN_DEPENDENCY grammar/Pepper.g4
    WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}/grammar")

list(APPEND PARSER_SRC
    ${CMAKE_BINARY_DIR}/source/parser/PepperLexer.h ${CMAKE_BINARY_DIR}/source/parser/PepperLexer.cpp
    ${CMAKE_BINARY_DIR}/source/parser/PepperParser.h ${CMAKE_BINARY_DIR}/source/parser/PepperParser.cpp
    ${CMAKE_BINARY_DIR}/source/parser/PepperListener.h ${CMAKE_BINARY_DIR}/source/parser/PepperListener.cpp
    ${CMAKE_BINARY_DIR}/source/parser/PepperBaseListener.h ${CMAKE_BINARY_DIR}/source/parser/PepperBaseListener.cpp
)
set(PARSER_INCLUDE_DIRS ${CMAKE_BINARY_DIR}/source/parser)
include_directories(${PARSER_INCLUDE_DIRS})

set(COMPILER_SRC
    source/Compiler/Codegen.cpp
    source/Compiler/Compiler.cpp
    source/Compiler/Parser.cpp
    source/Compiler/Value.cpp)

add_executable(Pepper
    ${PARSER_SRC}
    ${COMPILER_SRC}
    source/main.cpp)
add_dependencies(Pepper antlr4_shared)

set(CPACK_PROJECT_NAME ${PROJECT_NAME})
set(CPACK_PROJECT_VERSION ${PROJECT_VERSION})
include(CPack)
