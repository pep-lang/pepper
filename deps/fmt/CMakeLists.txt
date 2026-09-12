include(FetchContent)

FetchContent_Declare(
  fmt
  GIT_REPOSITORY https://github.com/fmtlib/fmt
  GIT_TAG main)

set(FMT_MODULE OFF)

FetchContent_MakeAvailable(fmt)
