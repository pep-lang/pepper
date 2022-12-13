
#include "Context.h"

#include <cassert>

Context* Context::Instance = nullptr;

Context& Context::get() {
    assert(Instance);
    return *Instance;
}

Context::Context(const std::string& moduleName) { 
    assert(Instance == nullptr);
    Instance = this; 
}

Context::~Context() { Instance = nullptr; }
