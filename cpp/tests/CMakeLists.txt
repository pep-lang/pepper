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

add_executable(PepperTests
  IntMath.cpp
  RTTI.cpp
)
target_include_directories(PepperTests PRIVATE ${PEPPER_INCLUDE_DIRS})
target_link_libraries(PepperTests GTest::gtest_main ${PEPPER_LIBRARIES})
set_target_properties(PepperTests PROPERTIES LINKER_LANGUAGE CXX)

if (MSVC)
    add_custom_command(TARGET PepperTests POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${ANTLR4_RUNTIME_LIBRARIES} $<TARGET_FILE_DIR:PepperTests>
        COMMAND_EXPAND_LISTS)
endif()

include(GoogleTest)
gtest_discover_tests(PepperTests)
