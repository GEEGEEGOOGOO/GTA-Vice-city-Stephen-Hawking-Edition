#!/bin/zsh
set -eu

if (( $# != 3 )); then
    print -u2 'Usage: tools/build_windows_engine.sh ENGINE_SOURCE LLVM_MINGW_ROOT BUILD_DIRECTORY'
    exit 2
fi

source=${1:A}
toolchain=${2:A}
build=${3:A}
compiler="$toolchain/bin"
target=x86_64-w64-mingw32
cmake_command=${HAWKING_CMAKE:-cmake}
jobs=${HAWKING_BUILD_JOBS:-4}

mkdir -p "$build/windows-system"
# Use the XInput library that ships with Windows 10 and 11.
cp "$toolchain/$target/lib/libxinput1_4.a" "$build/windows-system/libxinput.a"
cat > "$build/toolchain.cmake" <<EOF
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_C_COMPILER "$compiler/$target-clang")
set(CMAKE_CXX_COMPILER "$compiler/$target-clang++")
set(CMAKE_RC_COMPILER "$compiler/$target-windres")
EOF

"$cmake_command" -S "$source" -B "$build" -DCMAKE_TOOLCHAIN_FILE="$build/toolchain.cmake" \
    -DCMAKE_BUILD_TYPE=Release -DLIBRW_PLATFORM=D3D9 -DLIBRW_PLATFORM_D3D9=ON -DLIBRW_TOOLS=OFF \
    '-DCMAKE_CXX_FLAGS=-include cfloat' \
    "-DCMAKE_EXE_LINKER_FLAGS=-static -L\"$build/windows-system\"" \
    '-DCMAKE_CXX_STANDARD_LIBRARIES=-lkernel32 -luser32 -lgdi32 -lwinspool -lshell32 -lole32 -loleaut32 -luuid -lcomdlg32 -ladvapi32 -lwinmm -lddraw -ldinput8 -ldxguid -lstrmiids' \
    -DOPENAL_INCLUDE_DIR="$source/vendor/openal-soft/include" \
    -DOPENAL_LIBRARY="$source/vendor/openal-soft/libs/Win64/OpenAL32.lib" \
    -Dmpg123_INCLUDE_DIR="$source/vendor/mpg123/include" \
    -Dmpg123_LIBRARIES="$source/vendor/mpg123/lib/Win64/libmpg123-0.lib"
"$cmake_command" --build "$build" --parallel "$jobs"
