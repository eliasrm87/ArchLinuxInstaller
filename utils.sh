#! /bin/bash

function menuBox {
    h=20
    w=50
    
    if [ "$#" -gt "2" ]; then h=$3; fi
    if [ "$#" -gt "3" ]; then w=$4; fi

    echo $(dialog --backtitle "$backtitle" --menu "$1" $h $w $(echo $2 | wc -w) $2 3>&1 1>&2 2>&3 3>&-)
}

function menuBoxN {
    h=20
    w=50
    
    if [ "$#" -gt "2" ]; then h=$3; fi
    if [ "$#" -gt "3" ]; then w=$4; fi
    
    options=$(echo $2 | wc -w)

    i=1
    for option in $2; do
        options="$options $i $option"
        let i++
    done

    n=$(dialog --backtitle "$backtitle" --menu "$1" $h $w $options 3>&1 1>&2 2>&3 3>&-)
    
    if [ -n "$n" ]; then
        echo $2 | cut -d \  -f $n
    else
        echo ""
    fi
}

function yesnoBox {
    h=8
    w=50
    
    if [ "$#" -gt "2" ]; then h=$3; fi
    if [ "$#" -gt "3" ]; then w=$4; fi

    dialog --backtitle "$backtitle" --title "$1" --yesno "$2" $h $w 3>&1 1>&2 2>&3 3>&-
    
    echo $?
}

function msgBox {
    h=8
    w=50
    
    if [ "$#" -gt "2" ]; then h=$3; fi
    if [ "$#" -gt "3" ]; then w=$4; fi
    
    dialog --backtitle "$backtitle"  --title "$1" --msgbox "$2" $h $w
}

function inputBox {
    h=8
    w=50
    
    if [ "$#" -gt "1" ]; then h=$2; fi
    if [ "$#" -gt "2" ]; then w=$3; fi

    echo $(dialog --backtitle "$backtitle" --inputbox "$1" $h $w 3>&1 1>&2 2>&3 3>&-)
}
