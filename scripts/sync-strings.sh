#!/bin/bash
# Adds new user-facing strings to the String Catalogs (English source) after a build.
# Building in the Xcode app does this automatically; this script is for command-line builds.
#   xcodebuild … build && scripts/sync-strings.sh
set -euo pipefail
cd "$(dirname "$0")/.."
INTERMEDIATES=~/Library/Developer/Xcode/DerivedData/NotepadS/Build/Intermediates.noindex

sync() {   # sync <catalog> <target build folder>
    local args=()
    while IFS= read -r file; do
        args+=(--stringsdata "$file")
    done < <(find "$INTERMEDIATES/$2" -name "*.stringsdata" \
                 ! -name "ExtractedAppShortcuts*" ! -name "GeneratedStringSymbols*")
    xcrun xcstringstool sync "$1" "${args[@]}"
}

sync NotepadS/Resources/Localizable.xcstrings NotepadS.build
sync Packages/NotepadSCore/Sources/NotepadSCore/Resources/Localizable.xcstrings NotepadSCore.build
echo "String Catalogs updated."
