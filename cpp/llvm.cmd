
git clone --single-branch --branch llvmorg-15.0.0 https://github.com/llvm/llvm-project
cd llvm-project
mkdir build
cd build
cmake -DCMAKE_INSTALL_PREFIX=../install -G "Visual Studio 17 2022" -A x64 -Thost=x86 ../llvm
cmake --build . --target install --config Debug -j
