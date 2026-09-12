cmake_minimum_required(VERSION 3.14)

include(CTest)
enable_testing()

# GoogleTest requires at least C++14
set(CMAKE_CXX_STANDARD 20)

include(FetchContent)
FetchContent_Declare(
        googletest
        URL https://github.com/google/googletest/archive/refs/tags/release-1.12.1.zip
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
# For Windows: Prevent overriding the parent project's compiler/linker settings
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)

FetchContent_MakeAvailable(googletest)

# gtest does implicit casts between char16_t/char32_t, which should not cause build problems
if (CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    target_compile_options(gtest PRIVATE -Wno-character-conversion)
endif()

add_subdirectory(Support)

message(STATUS "TEST_SUPPORT_LIBRARIES: ${TEST_SUPPORT_LIBRARIES}")

set(TESTS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../tests)

add_executable(PepperTests
        TestUtils.cpp
        FloatMath.cpp
        Function.cpp
        IntMath.cpp
        Loops.cpp
        RTTI.cpp
        Structs.cpp
        Branches.cpp
        main.cpp
        Parsing.cpp
        BoostParser.cpp
        LexyParser.cpp)
target_include_directories(PepperTests PRIVATE ${PEPPER_INCLUDE_DIRS} ${TEST_SUPPORT_INCLUDE_DIRS})
target_link_directories(PepperTests PRIVATE ${PEPPER_LIBRARY_DIRS})
target_link_libraries(PepperTests GTest::gtest ${PEPPER_LIBRARIES} TestSupport)
set_target_properties(PepperTests PROPERTIES
        LINKER_LANGUAGE CXX)

add_dependencies(PepperTests TestSupport)

set(TESTS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../tests)

if (MSVC)
    set_target_properties(TestSupport PROPERTIES
            RUNTIME_OUTPUT_DIRECTORY $<TARGET_FILE_DIR:PepperTests>)
endif ()

add_custom_command(TARGET PepperTests POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_CURRENT_SOURCE_DIR}/Support/TestSupport.pep $<TARGET_FILE_DIR:PepperTests>)

file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/.env "PEP_SEARCH_DIR=${TESTS_DIR}")

add_custom_command(TARGET PepperTests POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_CURRENT_BINARY_DIR}/.env $<TARGET_FILE_DIR:PepperTests>)

include(GoogleTest)
gtest_discover_tests(PepperTests
        WORKING_DIRECTORY ${TESTS_DIR})
