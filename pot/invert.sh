#! /bin/bash

msgid=""
msgstr=""
cat $1 | while read line; do
    if grep -q "msgid" <<< "$line"; then
        msgstr="$(sed "s/msgid/msgstr/" <<< "$line")"
    elif grep -q "msgstr" <<< "$line"; then
        msgid="$(sed "s/msgstr/msgid/" <<< "$line")"
    else
        echo $line
    fi
    if [ -n "$msgstr" ] && [ -n "$msgid" ]; then
        echo "$msgid"
        echo "$msgstr"
        msgid=""
        msgstr=""
    fi
done
