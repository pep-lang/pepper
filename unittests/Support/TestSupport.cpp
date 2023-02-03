
#include "TestSupport.h"

// Include the cpp straight from the support lib so that the functions are tagged properly for export
#include "Support.cpp"

extern "C" {
    extern void _pep_assert(bool condition, const char* message);

    void test_assert(bool condition, const char* message) {
        _pep_assert(condition, message);
    }
}
