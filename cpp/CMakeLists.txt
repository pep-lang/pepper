cmake_minimum_required(VERSION 3.24)
project(Pepper VERSION 0.1.0)

option(BUILD_DEPS "Build dependencies, should only need to be done once" OFF)

set(CMAKE_CXX_STANDARD 20)
set(GLOBAL PROPERTY USE_FOLDERS ON)

enable_testing()

if(MSVC)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /EHsc /wd4624")
else()
    
endif()

add_subdirectory(deps)

if (MSVC)
    set(ANTLR4_LIBRARIES antlr4_shared)
    install(CODE [[
        file(GET_RUNTIME_DEPENDENCIES
            LIBRARIES antlr4_shared
        )
    ]])
else()
    set(ANTLR4_LIBRARIES antlr4_static)
endif()

find_package(LLVM REQUIRED CONFIG)
separate_arguments(LLVM_DEFINITIONS_LIST NATIVE_COMMAND ${LLVM_DEFINITIONS})
explicit_map_components_to_libraries(LLVM_LIBRARIES bitstreamreader binaryformat remarks orcjit option support core)

add_subdirectory(grammar)

add_library(PepperCore STATIC
    source/AST/Nodes.h
    source/Core/RTTI.h
    source/Core/Common.h
    source/Compiler/Codegen.h
    source/Compiler/Codegen.cpp
    source/Compiler/Compiler.h
    source/Compiler/Compiler.cpp
    source/Compiler/Constant.h
    source/Compiler/Constant.cpp
    source/Compiler/Context.h
    source/Compiler/Context.cpp
    source/Compiler/Executor.h
    source/Compiler/Executor.cpp
    source/Compiler/Function.h
    source/Compiler/Function.cpp
    source/Compiler/Options.h
    source/Compiler/Options.cpp
    source/Compiler/Parser.h
    source/Compiler/Parser.cpp
    source/Compiler/Scope.h
    source/Compiler/Scope.cpp
    source/Compiler/Type.h
    source/Compiler/Type.cpp
    source/Compiler/Value.h
    source/Compiler/Value.cpp "source/AST/AST.h" "source/AST/AST.cpp" "source/AST/Nodes.cpp"
)
add_dependencies(PepperCore PepperParser)
target_compile_definitions(PepperCore
    PRIVATE ${LLVM_DEFINITIONS_LIST})
target_include_directories(PepperCore 
    PUBLIC source ${PARSER_INCLUDE_DIRS} ${ANTLR4_INCLUDE_DIRS} ${LLVM_INCLUDE_DIRS}
)

source_group(
    TREE ${CMAKE_CURRENT_SOURCE_DIR}
    FILES ${COMPILER_SRC})

add_executable(Pepper
    source/main.cpp)
add_dependencies(Pepper PepperParser PepperCore)
target_link_libraries(Pepper
    PepperCore PepperParser ${LLVM_LIBRARIES} ${ANTLR_LIBRARIES})
target_compile_definitions(Pepper
    PRIVATE ${LLVM_DEFINITIONS_LIST})

set(PEPPER_INCLUDE_DIRS source ${PARSER_INCLUDE_DIRS} ${ANTLR4_INCLUDE_DIRS} ${LLVM_INCLUDE_DIRS})
set(PEPPER_LIBRARIES PepperCore PepperParser ${LLVM_LIBRARIES} ${ANTLR_LIBRARIES})

add_subdirectory(tests)
