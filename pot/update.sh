#! /bin/bash

SCRIPT="$1"
POFILE="$2"

xgettext -L Shell -o "${SCRIPT}.pot" "$SCRIPT"
msgmerge -U "$POFILE" "${SCRIPT}.pot"
rm "${SCRIPT}.pot"
