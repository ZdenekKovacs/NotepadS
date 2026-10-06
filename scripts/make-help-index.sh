#!/bin/bash
# Rebuilds the search index of the Help book after editing its pages.
#   scripts/make-help-index.sh
set -euo pipefail
cd "$(dirname "$0")/.."
LPROJ=NotepadS/Help/NotepadS.help/Contents/Resources/en.lproj
hiutil -I corespotlight -Caf "$LPROJ/NotepadS.cshelpindex" -l en "$LPROJ"
echo "Help index updated: $LPROJ/NotepadS.cshelpindex"
