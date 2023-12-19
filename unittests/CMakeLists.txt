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

add_subdirectory(Support)

message(STATUS "TEST_SUPPORT_LIBRARIES: ${TEST_SUPPORT_LIBRARIES}")

add_executable(PepperTests
        TestUtils.cpp
        FloatMath.cpp
        Function.cpp
        IntMath.cpp
        Loops.cpp
        RTTI.cpp
        Structs.cpp
        Branches.cpp
        main.cpp)
target_include_directories(PepperTests PRIVATE ${PEPPER_INCLUDE_DIRS} ${TEST_SUPPORT_INCLUDE_DIRS})
target_link_directories(PepperTests PRIVATE ${PEPPER_LIBRARY_DIRS})
target_link_libraries(PepperTests GTest::gtest ${PEPPER_LIBRARIES} TestSupport)
set_target_properties(PepperTests PROPERTIES LINKER_LANGUAGE CXX)

add_dependencies(PepperTests TestSupport)

set(TESTS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../tests)

if (MSVC)
    set_target_properties(TestSupport PROPERTIES
            RUNTIME_OUTPUT_DIRECTORY $<TARGET_FILE_DIR:PepperTests>)
    add_custom_command(TARGET PepperTests POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different ${ANTLR4_RUNTIME_LIBRARIES} $<TARGET_FILE_DIR:PepperTests>
            MAIN_DEPENDENCY ${ANTLR4_RUNTIME_LIBRARIES}
            COMMAND_EXPAND_LISTS)
endif ()

add_custom_command(TARGET PepperTests POST_BUILD
        MAIN_DEPENDENCY ${CMAKE_CURRENT_SOURCE_DIR}/Support/TestSupport.pep
        BYPRODUCTS ${TESTS_DIR}/TestSupport.pep
        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_CURRENT_SOURCE_DIR}/Support/TestSupport.pep ${TESTS_DIR})

include(GoogleTest)
gtest_discover_tests(PepperTests WORKING_DIRECTORY ${TESTS_DIR})
