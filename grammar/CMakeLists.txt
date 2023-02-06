cmake_minimum_required(VERSION 3.21)

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
        COMMAND ${Java_JAVA_EXECUTABLE} -jar ${ANTLR_JAR} -o ${CMAKE_BINARY_DIR}/source/parser -package "pepper::parser" -Dlanguage=Cpp Pepper.g4
        MAIN_DEPENDENCY Pepper.g4
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})

list(APPEND PARSER_SRC
        ${CMAKE_BINARY_DIR}/source/parser/PepperLexer.h ${CMAKE_BINARY_DIR}/source/parser/PepperLexer.cpp
        ${CMAKE_BINARY_DIR}/source/parser/PepperParser.h ${CMAKE_BINARY_DIR}/source/parser/PepperParser.cpp
        ${CMAKE_BINARY_DIR}/source/parser/PepperListener.h ${CMAKE_BINARY_DIR}/source/parser/PepperListener.cpp
        ${CMAKE_BINARY_DIR}/source/parser/PepperBaseListener.h ${CMAKE_BINARY_DIR}/source/parser/PepperBaseListener.cpp
        )

if (MSVC)
    set(ANTLR4_LIBRARIES antlr4_shared PARENT_SCOPE)
    install(CODE [[
        file(GET_RUNTIME_DEPENDENCIES
            LIBRARIES antlr4_shared
        )
    ]])
else ()
    set(ANTLR4_LIBRARIES antlr4_static PARENT_SCOPE)
endif ()

add_library(PepperParser STATIC ${PARSER_SRC})
add_dependencies(PepperParser ${ANTLR4_LIBRARIES})

message(STATUS "PepperParser will use ANTLR4 includes at ${ANTLR4_INCLUDE_DIRS}")
target_include_directories(PepperParser PUBLIC ${ANTLR4_INCLUDE_DIRS})
target_link_libraries(PepperParser PUBLIC ${ANTLR4_LIBRARIES})
set(PARSER_INCLUDE_DIRS ${CMAKE_BINARY_DIR}/source/parser PARENT_SCOPE)
