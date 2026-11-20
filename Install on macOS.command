#!/bin/zsh
set -eu
cd -- "${0:A:h}"

if ! command -v python3 >/dev/null || ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 9))' 2>/dev/null; then
    print -u2 "Install Python 3.9 or later from python.org, then open this installer again."
    exit 1
fi

if (( $# == 0 )) && [[ ! -d "/Applications/Grand Theft Auto Vice City.app/Contents/Resources/GameData" ]]; then
    base=$(/usr/bin/osascript -e 'POSIX path of (choose folder with prompt "Choose the classic Vice City GameData folder")')
    set -- --base "$base"
fi
exec python3 tools/install.py "$@"
