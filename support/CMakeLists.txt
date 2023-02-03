
add_library(Support STATIC Support.cpp)
set_target_properties(Support PROPERTIES ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/../runtime)
