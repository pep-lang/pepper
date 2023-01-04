cmake_minimum_required(VERSION 3.24)
project(Pepper VERSION 0.1.0)

option(BUILD_DEPS "Build dependencies, should only need to be done once" OFF)

set(CMAKE_CXX_STANDARD 20)
set(GLOBAL PROPERTY USE_FOLDERS ON)

enable_testing()

if (MSVC)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /EHsc /wd4624 /Zc:preprocessor")
else ()
    #set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fsanitize=address -fsanitize-recover=address")
endif ()

add_subdirectory(deps)

if (MSVC)
    set(ANTLR4_LIBRARIES antlr4_shared)
else ()
    set(ANTLR4_LIBRARIES antlr4_static)
endif ()

find_package(LLVM REQUIRED CONFIG)
separate_arguments(LLVM_DEFINITIONS_LIST NATIVE_COMMAND ${LLVM_DEFINITIONS})
explicit_map_components_to_libraries(LLVM_LIBRARIES bitstreamreader binaryformat native remarks orcjit option support core)

add_subdirectory(grammar)

file(GLOB_RECURSE PEPPER_CORE_SOURCE LIST_DIRECTORIES false source/**)
add_library(PepperCore STATIC ${PEPPER_CORE_SOURCE})

add_dependencies(PepperCore PepperParser)
target_compile_definitions(PepperCore
        PRIVATE ${LLVM_DEFINITIONS_LIST})
target_include_directories(PepperCore
        PUBLIC source ${PARSER_INCLUDE_DIRS} ${ANTLR4_INCLUDE_DIRS} ${LLVM_INCLUDE_DIRS} ${LLD_INCLUDE_DIRS}
        )

source_group(
        TREE ${CMAKE_CURRENT_SOURCE_DIR}
        FILES ${COMPILER_SRC})

set(PEPPER_LIBRARIES ${LLD_LIBRARIES} ${LLVM_LIBRARIES} ${ANTLR_LIBRARIES} PepperParser PepperCore)
set(PEPPER_LIBRARY_DIRS ${LLVM_LIBRARY_DIRS})

add_executable(pepper source/main.cpp)
add_dependencies(pepper PepperParser PepperCore)
target_link_directories(pepper PRIVATE ${PEPPER_LIBRARY_DIRS})
target_link_libraries(pepper ${PEPPER_LIBRARIES})
target_compile_definitions(pepper PRIVATE ${LLVM_DEFINITIONS_LIST})

if (MSVC)
    add_custom_command(TARGET pepper POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different ${ANTLR4_RUNTIME_LIBRARIES} $<TARGET_FILE_DIR:pepper>)
endif ()

set(PEPPER_INCLUDE_DIRS source ${PARSER_INCLUDE_DIRS} ${ANTLR4_INCLUDE_DIRS} ${LLVM_INCLUDE_DIRS})
set(PEPPER_LIBRARIES PepperParser PepperCore ${LLVM_LIBRARIES} ${ANTLR_LIBRARIES})

add_subdirectory(tests)
