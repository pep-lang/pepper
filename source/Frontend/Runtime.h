//
// Created by Justin Boswell on 12/21/22.
//

#pragma once

#include <utility>

#include "Core/Common.h"
#include "Core/Ident.h"
#include "Core/Vector.h"
#include "Frontend/Scope.h"

namespace pepper {

    class Runtime : public Scope {
      public:
        struct FunctionProto {
            Ident Name;
            Ident Return;
            Vector<std::pair<Ident, Ident>> Params;
            bool Vararg = false;
        };

        static Vector<FunctionProto>& Imports();

      public:
        Runtime();

        static void Import(const Ident& returnType,
                           const Ident& name,
                           const Vector<std::pair<Ident, Ident>>& params,
                           bool vararg = false);
    };
} // namespace pepper
