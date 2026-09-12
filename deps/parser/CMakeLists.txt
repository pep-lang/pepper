include(FetchContent)

FetchContent_Declare(
        parser
        GIT_REPOSITORY https://github.com/boostorg/parser
        GIT_TAG boost-1.91.0)

FetchContent_MakeAvailable(parser)
