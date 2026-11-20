#!/bin/zsh
set -eu
if (( $# != 6 )); then
    print -u2 "Usage: prepare_runtime.sh ENGINE SDL2 OPENAL MPG123 NOTICES OUTPUT_APP"
    exit 2
fi

tools_dir=${0:A:h}
engine=$1
sdl=$2
openal=$3
mpg=$4
notices=$5
app=$6

if [[ -e "$app" || -L "$app" ]]; then
    print -u2 "Choose a new output app path."
    exit 2
fi

mkdir -p "$app/Contents"/{MacOS,Frameworks,Resources/Notices}
/bin/cp "$tools_dir/Info.plist" "$app/Contents/"
/bin/cp -R "$notices/." "$app/Contents/Resources/Notices/"
/bin/cp "$engine" "$app/Contents/MacOS/reVC"
/bin/cp -L "$openal" "$app/Contents/Frameworks/libopenal.1.dylib"
/bin/cp -L "$mpg" "$app/Contents/Frameworks/libmpg123.0.dylib"

if [[ "$(/usr/bin/lipo -archs "$sdl")" == arm64 ]]; then
    /bin/cp -L "$sdl" "$app/Contents/Frameworks/libSDL2.dylib"
else
    /usr/bin/lipo "$sdl" -thin arm64 -output "$app/Contents/Frameworks/libSDL2.dylib"
fi
chmod u+w "$app/Contents/Frameworks/"*
/usr/bin/install_name_tool -id @rpath/libSDL2.dylib "$app/Contents/Frameworks/libSDL2.dylib"
/usr/bin/install_name_tool -id @rpath/libmpg123.0.dylib "$app/Contents/Frameworks/libmpg123.0.dylib"
/usr/bin/install_name_tool -id @rpath/libopenal.1.dylib "$app/Contents/Frameworks/libopenal.1.dylib"

while IFS= read -r dependency; do
    case "$dependency" in
        *libSDL2*|*/SDL2)
            bundled=libSDL2.dylib ;;
        *libmpg123*)
            bundled=libmpg123.0.dylib ;;
        *libopenal*|*libOpenAL*)
            bundled=libopenal.1.dylib ;;
        *)
            continue ;;
    esac
    /usr/bin/install_name_tool -change "$dependency" "@executable_path/../Frameworks/$bundled" "$app/Contents/MacOS/reVC"
done < <(/usr/bin/otool -L "$app/Contents/MacOS/reVC" | /usr/bin/awk 'NR > 1 {print $1}')

/usr/bin/xcrun clang -arch arm64 -mmacosx-version-min=26.0 -Wall -Wextra -Werror \
    "$tools_dir/launcher.c" -o "$app/Contents/MacOS/launch"
/usr/bin/codesign --force --deep --sign - "$app"
/usr/bin/codesign --verify --deep --strict "$app"
