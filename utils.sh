#! /bin/bash

version="0.1"

function menuBox {
    h=20
    w=50

    if [ "$1" -gt "0" ]; then h=$1; fi
    if [ "$2" -gt "0" ]; then w=$2; fi

    echo $(dialog --backtitle "$backtitle" --menu "$3" $h $w $((($#-1)/3)) "${@:4}" 3>&1 1>&2 2>&3 3>&-)
}

function menuBoxN {
    h=20
    w=50

    if [ "$1" -gt "0" ]; then h=$1; fi
    if [ "$2" -gt "0" ]; then w=$2; fi

    options=$(echo $4 | wc -w)

    i=1
    for option in $4; do
        options="$options $i $option"
        i=$((i+1))
    done

    n=$(dialog --backtitle "$backtitle" --menu "$3" $h $w $options 3>&1 1>&2 2>&3 3>&-)

    if [ -n "$n" ]; then
        echo $4 | cut -d \  -f $n
    else
        echo ""
    fi
}

function yesnoBox {
    h=8
    w=50

    if [ "$1" -gt "0" ]; then h=$1; fi
    if [ "$2" -gt "0" ]; then w=$2; fi

    dialog --backtitle "$backtitle" --title "$3" --yesno "$4" $h $w 3>&1 1>&2 2>&3 3>&-

    echo $?
}

function msgBox {
    h=8
    w=50

    if [ "$1" -gt "0" ]; then h=$1; fi
    if [ "$2" -gt "0" ]; then w=$2; fi

    dialog --backtitle "$backtitle"  --title "$3" --msgbox "$4" $h $w
}

function inputBox {
    h=8
    w=50

    if [ "$1" -gt "0" ]; then h=$1; fi
    if [ "$2" -gt "0" ]; then w=$2; fi

    echo $(dialog --backtitle "$backtitle" --inputbox "$3" $h $w 3>&1 1>&2 2>&3 3>&-)
}

function checklistBox {
    h=20
    w=50

    if [ "$1" -gt "0" ]; then h=$1; fi
    if [ "$2" -gt "0" ]; then w=$2; fi

    selected=$(dialog --backtitle "$backtitle" --checklist "$3" $h $w $((($#-1)/3)) "${@:4}" 3>&1 1>&2 2>&3 3>&-)

    if [ -n "$selected" ]; then
        echo $selected
    else
        echo ""
    fi
}

function checklistBoxN {
    h=20
    w=50

    if [ "$1" -gt "0" ]; then h=$1; fi
    if [ "$2" -gt "0" ]; then w=$2; fi

    options=$(($(echo $4 | wc -w)/2))

    n=1
    for i in $(seq $options); do
        options="$options $i $(echo $4 | awk {"print \$$n,\$$((n+1))"})"
        n=$((n+2))
    done

    selected=$(dialog --backtitle "$backtitle" --checklist "$3" $h $w $options 3>&1 1>&2 2>&3 3>&-)

    if [ -n "$selected" ]; then
        options=""
        for i in $selected; do
            options="$options $(echo $4 | awk {"print \$$((i*2-1))"})"
        done
        echo $options
    else
        echo ""
    fi
}
