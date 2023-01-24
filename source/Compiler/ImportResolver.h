
#pragma once

#include <iostream>

#include "Core/Vector.h"
#include "llvm/ADT/StringMap.h"

namespace pepper {

    class ImportResolver {
        llvm::StringMap<Vector<std::string>> Imports;
        Vector<std::string> SearchPaths;

      public:
        ImportResolver(const Vector<std::string>& searchPaths);

        std::string resolve(const std::string& modulePath, const std::string& importName, bool local = false);

        void addImport(const std::string& moduleName, const std::string& importName);

        // scan a stream looking for @import statements and map them to the module for sorting later
        void scanForImports(const std::string& moduleName, std::istream& stream);

        // topologically sort modules so that imports are satisfied, returns the list in order
        Vector<std::string> getModuleCompileOrder() const;
    };

} // namespace pepper
