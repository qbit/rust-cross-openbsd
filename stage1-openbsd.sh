#!/bin/sh

if [ `uname -s` != "OpenBSD" ]; then
  echo "You have to run this on OpenBSD!"
  exit 1
fi

mkdir -p stage1-openbsd
cd stage1-openbsd

TOP=`pwd`

AUTOMAKE_VERSION=1.12

TARGET_SUB=libs
TARGET=${TOP}/${TARGET_SUB}

CC=cc
CXX="g++"
LLVM_TARGET="/usr/local/"

mkdir -p ${TARGET}

echo "-- TOP: ${TOP}"
echo "-- TARGET: ${TARGET}"
echo "-- LLVM_TARGET: ${LLVM_TARGET}"

git clone https://github.com/rust-lang/rust.git
cd rust
git submodule init
git submodule update
cd src/llvm
patch -p1 < ${TOP}/../patch-llvm
cd ..
mkdir llvm-build
cd llvm-build
../llvm/configure --prefix=${LLVM_TARGET} #--disable-compiler-version-checks
gmake ENABLE_OPTIMIZED=1
gmake ENABLE_OPTIMIZED=1 install

mkdir -p ${TARGET}/llvm
cp `${LLVM_TARGET}/bin/llvm-config --libfiles` ${TARGET}/llvm

cd ${TOP}/rust/src/rustllvm
${CXX} -c `${LLVM_TARGET}/bin/llvm-config --cxxflags` PassWrapper.cpp
${CXX} -c `${LLVM_TARGET}/bin/llvm-config --cxxflags` RustWrapper.cpp
ar rcs librustllvm.a PassWrapper.o RustWrapper.o	
cp librustllvm.a ${TARGET}

# build libcompiler-rt.a
cd ${TOP}/rust/src/compiler-rt
cmake -DLLVM_CONFIG_PATH=${LLVM_TARGET}/bin/llvm-config
gmake
cp ./lib/openbsd/libclang_rt.x86_64.a ${TARGET}/libcompiler-rt.a


cd ${TOP}/rust/src
ln -s libbacktrace include
cd libbacktrace
./configure
gmake
cp .libs/libbacktrace.a ${TARGET}
cd ..
unlink include

# Or use "pkg ins libuv"
cd ${TOP}/rust/src/libuv
sh autogen.sh
./configure
gmake
cp .libs/libuv.a ${TARGET}

cd ${TOP}/rust/src/rt
${LLVM_TARGET}/bin/llc rust_try.ll
${CC} -c -o rust_try.o rust_try.s
${CC} -c -o record_sp.o arch/x86_64/record_sp.S
ar rcs ${TARGET}/librustrt_native.a rust_try.o record_sp.o

cd ${TOP}/rust/src/rt
${CC} -c -o context.o arch/x86_64/_context.S
ar rcs ${TARGET}/libcontext_switch.a context.o

cd ${TOP}/rust/src/rt
${CC} -c -o rust_builtin.o rust_builtin.c
ar rcs ${TARGET}/librust_builtin.a rust_builtin.o 

cd ${TOP}/rust/src/rt
${CC} -c -o morestack.o arch/x86_64/morestack.S
ar rcs ${TARGET}/libmorestack.a morestack.o

cd ${TOP}/rust/src/rt
${CC} -c -o miniz.o miniz.c
ar rcs ${TARGET}/libminiz.a miniz.o 

cd ${TOP}/rust/src/rt
${CC} -c -I../libuv/include -o rust_uv.o rust_uv.c
ar rcs ${TARGET}/libuv_support.a rust_uv.o 

cd ${TOP}/rust/src/rt/hoedown
gmake libhoedown.a 
cp libhoedown.a ${TARGET}

# Copy Openbsd system libraries

mkdir -p ${TARGET}/lib
mkdir -p ${TARGET}/usr/lib
cp -r /lib ${TARGET}/lib
cp -r /usr/lib ${TARGET}/usr/lib

# 
cd ${TOP}/..
python ${TOP}/rust/src/etc/mklldeps.py stage1-openbsd/llvmdeps.rs "x86 arm mips ipo bitreader bitwriter linker asmparser jit mcjit interpreter instrumentation" true "${LLVM_TARGET}/bin/llvm-config"

cd ${TOP}/..
tar cvzf stage1-openbsd.tgz stage1-openbsd/${TARGET_SUB} stage1-openbsd/llvmdeps.rs



echo "Please copy stage1-openbsd.tgz onto your Linux machine and extract it"
