cmake_minimum_required(VERSION 3.24)

cmake_policy(SET CMP0091 NEW)

project(Pepper VERSION 0.1.0)

option(BUILD_DEPS "Build dependencies, should only need to be done once" OFF)
option(USE_SANITIZERS "Use ASan and UBSan" OFF)

set(CMAKE_CXX_STANDARD 20)
set(GLOBAL PROPERTY USE_FOLDERS ON)

enable_testing()

if(MSVC)
    # set(CMAKE_MSVC_RUNTIME_LIBRARY MultiThreadedDLL)
    if(USE_SANITIZERS)
        # set(CMAKE_EXE_LINKER_FLAGS "/fsanitize=address")
    endif()
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /EHsc /wd4624 /Zc:__cplusplus")

    if(CMAKE_CXX_COMPILER_ID MATCHES "Clang" AND CMAKE_CXX_SIMULATE_ID MATCHES "MSVC")
    else()
        # Force MSVC to use the new standard preprocessor format
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /Zc:preprocessor")
    endif()
else()
    if(USE_SANITIZERS)
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fvisibility=hidden -fsanitize=undefined -fsanitize=address")
    endif()
endif()


add_subdirectory(deps)

add_library(PepperCore STATIC
    source/CodeGen/CodeGenerator.cpp
    source/CodeGen/CodeGenerator.h
    source/CodeGen/LLVM/Address.h
    source/CodeGen/LLVM/BlockGen.cpp
    source/CodeGen/LLVM/BranchGen.cpp
    source/CodeGen/LLVM/DebugInfo.cpp
    source/CodeGen/LLVM/DebugInfo.h
    source/CodeGen/LLVM/FunctionGen.cpp
    source/CodeGen/LLVM/IntrinsicsGen.cpp
    source/CodeGen/LLVM/LLVMCodeGenerator.cpp
    source/CodeGen/LLVM/LLVMCodeGenerator.h
    source/CodeGen/LLVM/LLVMModuleGenerator.cpp
    source/CodeGen/LLVM/LLVMModuleGenerator.h
    source/CodeGen/LLVM/LoopGen.cpp
    source/CodeGen/LLVM/OperatorGen.cpp
    source/CodeGen/LLVM/StructGen.cpp
    source/Compiler/Compiler.cpp
    source/Compiler/Compiler.h
    source/Compiler/ImportResolver.cpp
    source/Compiler/ImportResolver.h
    source/Compiler/Linker.cpp
    source/Compiler/Linker.h
    source/Compiler/Options.cpp
    source/Compiler/Options.h
    source/Core/Common.h
    source/Core/Exceptions.cpp
    source/Core/Exceptions.h
    source/Core/Ident.h
    source/Core/LLVMUtils.h
    source/Core/Messages.cpp
    source/Core/Messages.h
    source/Core/Query.h
    source/Core/RTTI.h
    source/Core/Ref.h
    source/Core/SourceLocation.cpp
    source/Core/SourceLocation.h
    source/Core/String.h
    source/Core/Tracer.h
    source/Core/TypeSwitch.h
    source/Core/Vector.h
    source/JIT/Executor.cpp
    source/JIT/Executor.h
    source/Parser/BoostParser.cpp
    source/Parser/BoostParser.h
    source/Parser/Lexer.h
    source/Parser/Parser.cpp
    source/Parser/Parser.h
    source/Sema/ApplyExtensions.h
    source/Sema/ConvertIntrinsics.h
    source/Sema/ConvertMemberRefs.h
    source/Sema/ConvertStringLiterals.h
    source/Sema/Function.cpp
    source/Sema/Function.h
    source/Sema/GatherGenerics.h
    source/Sema/Model/BinaryOps.h
    source/Sema/Model/Block.h
    source/Sema/Model/Branches.h
    source/Sema/Model/Builder.cpp
    source/Sema/Model/Builder.h
    source/Sema/Model/Extension.h
    source/Sema/Model/Functions.cpp
    source/Sema/Model/Functions.h
    source/Sema/Model/Intrinsics.h
    source/Sema/Model/Literals.h
    source/Sema/Model/Loops.h
    source/Sema/Model/Method.h
    source/Sema/Model/Module.cpp
    source/Sema/Model/Module.h
    source/Sema/Model/Node.cpp
    source/Sema/Model/Node.h
    source/Sema/Model/Nodes.h
    source/Sema/Model/Param.h
    source/Sema/Model/Parser.cpp
    source/Sema/Model/Parser.h
    source/Sema/Model/Resolvable.h
    source/Sema/Model/Struct.cpp
    source/Sema/Model/Struct.h
    source/Sema/Model/Tracer.h
    source/Sema/Model/Trait.h
    source/Sema/Model/TypeName.cpp
    source/Sema/Model/TypeName.h
    source/Sema/Model/UnaryOps.h
    source/Sema/Model/Variables.h
    source/Sema/Model/Visitor.h
    source/Sema/Operations.cpp
    source/Sema/Operations.h
    source/Sema/Param.h
    source/Sema/ReleaseFieldRefs.h
    source/Sema/ResolveImplicitTypes.h
    source/Sema/ResolveLiterals.h
    source/Sema/ResolveOperators.h
    source/Sema/ResolveResolvables.h
    source/Sema/Scope.cpp
    source/Sema/Scope.h
    source/Sema/SemaContext.cpp
    source/Sema/SemaContext.h
    source/Sema/Specialization.h
    source/Sema/SpecializeFunctions.h
    source/Sema/SpecializeStructs.h
    source/Sema/Struct.cpp
    source/Sema/Struct.h
    source/Sema/TagGenerics.h
    source/Sema/Transform.cpp
    source/Sema/Transform.h
    source/Sema/Types.cpp
    source/Sema/Types.h
    source/main.cpp
        source/Parser/LexyParser.cpp
        source/Parser/LexyParser.h
        source/Sema/ModelBuilder.cpp
        source/Sema/ModelBuilder.h
)

find_package(LLVM REQUIRED CONFIG)
separate_arguments(LLVM_DEFINITIONS_LIST NATIVE_COMMAND ${LLVM_DEFINITIONS})
explicit_map_components_to_libraries(LLVM_LIBRARIES bitstreamreader binaryformat native remarks orcjit option support core X86CodeGen)

add_subdirectory(support)

target_compile_definitions(PepperCore
    PRIVATE ${LLVM_DEFINITIONS_LIST})
target_include_directories(PepperCore
        PUBLIC source $<TARGET_PROPERTY:Boost::parser,INTERFACE_INCLUDE_DIRECTORIES> ${LLVM_INCLUDE_DIRS} ${LLD_INCLUDE_DIRS}
)
target_link_directories(PepperCore PUBLIC ${LLVM_LIBRARY_DIRS})
target_link_libraries(PepperCore PUBLIC fmt::fmt ${LLVM_LIBRARIES} PRIVATE foonathan::lexy)

source_group(
    TREE ${CMAKE_CURRENT_SOURCE_DIR}
    FILES ${COMPILER_SRC})

set(PEPPER_LIBRARIES ${LLD_LIBRARIES} ${LLVM_LIBRARIES} foonathan::lexy PepperCore)
set(PEPPER_LIBRARY_DIRS ${LLVM_LIBRARY_DIRS})

add_executable(pepper source/main.cpp)
add_dependencies(pepper Support)
target_link_directories(pepper PRIVATE ${PEPPER_LIBRARY_DIRS})
target_link_libraries(pepper ${PEPPER_LIBRARIES})
target_compile_definitions(pepper PRIVATE ${LLVM_DEFINITIONS_LIST})

set(LLVM_BINARIES
    ${LLVM_BINARIES_DIR}/lli${CMAKE_EXECUTABLE_SUFFIX})

if(MSVC)
    list(APPEND LLVM_BINARIES
        ${LLVM_BINARIES_DIR}/lld-link.exe
        ${LLVM_BINARIES_DIR}/llvm-lib.exe)
else()
    list(APPEND LLVM_BINARIES
        ${LLVM_BINARIES_DIR}/ld.lld
        ${LLVM_BINARIES_DIR}/ld64.lld)
endif()

add_custom_command(TARGET pepper POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${LLVM_BINARIES} $<TARGET_FILE_DIR:pepper>)

set(PEPPER_INCLUDE_DIRS source ${LLVM_INCLUDE_DIRS})

add_subdirectory(unittests)
