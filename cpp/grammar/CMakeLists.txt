cmake_minimum_required(VERSION 3.21)

add_subdirectory(../deps/antlr4 ${CMAKE_BINARY_DIR}/antlr4_runtime)

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
    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_BINARY_DIR}/source/parser
    COMMAND ${Java_JAVA_EXECUTABLE} -jar ${ANTLR_JAR} -o ${CMAKE_BINARY_DIR}/source/parser -package "Pepper::Parser" -Dlanguage=Cpp Pepper.g4
    MAIN_DEPENDENCY Pepper.g4
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})

list(APPEND PARSER_SRC
    ${CMAKE_BINARY_DIR}/source/parser/PepperLexer.h ${CMAKE_BINARY_DIR}/source/parser/PepperLexer.cpp
    ${CMAKE_BINARY_DIR}/source/parser/PepperParser.h ${CMAKE_BINARY_DIR}/source/parser/PepperParser.cpp
    ${CMAKE_BINARY_DIR}/source/parser/PepperListener.h ${CMAKE_BINARY_DIR}/source/parser/PepperListener.cpp
    ${CMAKE_BINARY_DIR}/source/parser/PepperBaseListener.h ${CMAKE_BINARY_DIR}/source/parser/PepperBaseListener.cpp
)
add_library(PepperParser STATIC ${PARSER_SRC})
add_dependencies(PepperParser antlr4_shared)

message(STATUS "PepperParser will use ANTLR4 includes at ${ANTLR4_INCLUDE_DIRS}")
target_include_directories(PepperParser PUBLIC ${ANTLR4_INCLUDE_DIRS})
target_link_libraries(PepperParser PUBLIC antlr4_shared)
set(PARSER_INCLUDE_DIRS ${CMAKE_BINARY_DIR}/source/parser PARENT_SCOPE)
