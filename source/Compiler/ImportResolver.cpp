//
// Created by justi on 1/17/2023.
//

#include <filesystem>

#include "Compiler/ImportResolver.h"
#include "Core/Exceptions.h"
#include "Core/Query.h"
#include "Core/String.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallString.h"

namespace pepper {

    ImportResolver::ImportResolver(const Vector<std::string>& searchPaths)
        : SearchPaths(searchPaths) {
    }

    void ImportResolver::addImport(const std::string& modulePath, const std::string& importName) {
        Imports[modulePath].emplace_back(importName);
        // Ensure import also has an entry, even if it ends up being empty
        auto it = Imports.find(importName);
        if (it == Imports.end()) {
            Imports.insert({importName, {}});
        }
    }

    std::string ImportResolver::resolve(const std::string& modulePath, const std::string& importName, bool local) {
        Vector<std::string> imports;
        if (local) {
            auto moduleDir = std::filesystem::path(modulePath).parent_path();
            auto importPath = absolute(moduleDir / importName).replace_extension(".pep");
            if (std::filesystem::exists(importPath))
                return importPath.string();
        } else {
            for (const auto& searchPath : SearchPaths) {
                auto path = absolute(std::filesystem::path(searchPath) / importName).replace_extension(".pep");
                if (std::filesystem::exists(path)) {
                    return path.string();
                }
            }
        }

        return {};
    }

    void ImportResolver::scanForImports(const std::string& modulePath, std::istream& stream) {
        assert(stream.good() && "Attempted to scan a bad stream");

        // Ensure module has an entry, even if it ends up being empty
        auto it = Imports.find(modulePath);
        if (it == Imports.end()) {
            Imports.insert({modulePath, {}});
        }

        auto size = stream.tellg();
        stream.seekg(0, std::ios::beg);
        std::string buffer;
        buffer.reserve(size);
        stream.read(buffer.data(), size);

        auto importStart = buffer.find("@import");
        while (importStart != std::string::npos) {
            auto importEnd = buffer.find(';', importStart);
            auto importStmt = buffer.substr(importStart, importEnd - importStart);

            // strip off @import and ; and whitespace
            auto importTarget = trim(importStmt.substr(8, importStmt.size() - 9));

            // determine if the import is local, then strip quotes
            bool isLocal = importTarget.starts_with('"');
            importTarget = trim(importTarget, "\"");

            std::string importPath;
            if (isLocal) {
                auto moduleDir = std::filesystem::path(modulePath).parent_path();
                importPath = (moduleDir / importTarget).string();
            } else {
                for (const auto& searchPath : SearchPaths) {
                    auto path = absolute(std::filesystem::path(searchPath) / importTarget);
                    if (std::filesystem::exists(path)) {
                        importPath = path.string();
                    }
                }
            }
            if (importPath.empty()) {
                throw CompileError("Unable to resolve import {0}", importStmt);
            }

            addImport(modulePath, importPath);

            importStart = buffer.find("@import", importEnd);
        }
    }

    Vector<std::string> ImportResolver::getModuleCompileOrder() const {
        // map modules to the modules that import them
        llvm::StringMap<Vector<std::string>> importers;
        for (const auto& importSet : Imports) {
            const auto& importer = importSet.getKey();
            for (const auto& import : importSet.getValue()) {
                importers[import].emplace_back(importer);
            }
        }

        Vector<std::string> modules;
        for (const auto& importSet : Imports) {
            for (const auto& import : importSet.getValue()) {
                if (!llvm::is_contained(modules, import)) {
                    modules.emplace_back(import);
                }
            }
        }

        // check for cycles
        for (const auto& module : modules) {
            const auto& imports = Imports.lookup(module);
            llvm::DenseSet<llvm::StringRef> moduleDeps;
            for (const auto& import : imports) {
                auto res = moduleDeps.insert(import);
                if (!res.second) {
                    throw CompileError("Import cycle detected in module {0}", module);
                }
            }
        }

        // topological sort, using Kahn's algorithm
        Vector<std::string> resolvedModules; // modules with no outstanding imports
        // compute dependent counts per module
        llvm::StringMap<unsigned> dependentCounts;
        for (const auto& importSet : Imports) {
            auto count = importSet.getValue().size();
            dependentCounts[importSet.getKey()] = count;
            if (count == 0) {
                resolvedModules.emplace_back(importSet.getKey());
            }
        }

        if (resolvedModules.empty()) {
            throw CompileError("No modules are without dependencies");
        }

        Vector<std::string> sortedModules;
        while (!resolvedModules.empty()) {
            auto module = resolvedModules.pop_back_val();
            sortedModules.emplace_back(module);
            auto moduleImporters = importers.lookup(module);
            for (const auto& importer : moduleImporters) {
                auto count = --dependentCounts[importer];
                if (count == 0) {
                    resolvedModules.emplace_back(importer);
                }
            }
        }

        return sortedModules;
    }

} // namespace pepper