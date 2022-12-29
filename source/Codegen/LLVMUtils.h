//
// Created by Justin Boswell on 12/26/22.
//

#pragma once

#include <string>

#include "Core/String.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/Value.h"
#include "llvm/Support/raw_ostream.h"

namespace pepper {
    inline std::string toString(llvm::Value* value) {
        std::string str;
        if (value) {
            llvm::raw_string_ostream ostr(str);
            value->print(ostr, true);
        } else {
            str = "null";
        }
        return trim(str);
    }

    inline std::string toString(llvm::Type* type) {
        std::string str;
        llvm::raw_string_ostream ostr(str);
        type->print(ostr, true);
        return trim(str);
    }
} // namespace pepper
