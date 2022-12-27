//
// Created by Justin Boswell on 12/26/22.
//

#pragma once

#include <string>

#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/Value.h"
#include "llvm/Support/raw_ostream.h"

namespace pepper {
    std::string toString(llvm::Value* value) {
        std::string str;
        llvm::raw_string_ostream ostr(str);
        value->print(ostr, true);
        return str;
    }

    std::string toString(llvm::Type* type) {
        std::string str;
        llvm::raw_string_ostream ostr(str);
        type->print(ostr, true);
        return str;
    }
} // namespace pepper
