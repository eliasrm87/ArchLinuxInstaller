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

function infoBox {
    h=8
    w=50
    
    if [ "$#" -gt "1" ]; then h=$2; fi
    if [ "$#" -gt "2" ]; then w=$3; fi
    
    dialog --backtitle "$backtitle" --infobox "$1" $h $w
}

function inputBox {
    h=8
    w=50
    
    if [ "$#" -gt "1" ]; then h=$2; fi
    if [ "$#" -gt "2" ]; then w=$3; fi

    echo $(dialog --backtitle "$backtitle" --inputbox "$1" $h $w 3>&1 1>&2 2>&3 3>&-)
}

function mountFormatPartition {
    backtitle="Particiones - Puntos de motaje y formato"

    yesno=0
    if [ "$1" != "/" ]; then
        yesno=$(yesnoBox "Montar $1" "Desea especificar un punto de montaje para $1?")
    fi
    if [ "$yesno" == "0" ]; then
        partition=$(menuBox "Seleccione la partición que desea montar en $1" "$(lsblk -l | grep part | awk '{print $1,$4}')" 15 50)
        if [ -n "$partition" ]; then

            yesno=$(yesnoBox "Formatear" "¿Desea formatear $partition ($1)?")
            if [ "$yesno" == "0" ]; then
                format=$(menuBoxN "Seleccione el sistema de archivos para formatear $partition" "ext4 ext3 ext2 fat exfat" 15 50)
                if [ -n "$format" ]; then
                    yesno=$(yesnoBox "¡ATENCIÓN!" "¿Está seguro de que desea formatear $partition ($1) en $format?\n¡SE PERDERÁN TODOS LOS DATOS!")
                    if [ "$yesno" == "0" ]; then
                        mkfs -t $format /dev/$partition
                    fi
                fi
            fi
            
            mkdir -p /mnt$1
            mount /dev/$partition /mnt$1
        fi
    fi
}

if [ "$#" == "0" ]; then
######################################### MAIN #########################################

    # backtitle="Conección a Internet"
    # 
    # yesno=$(yesnoBox "WiFi" "¿Desea conectarse a alguna red WiFi?")
    # if [ "$yesno" == "0" ]; then
    #     wifi-menu
    # fi

    backtitle="Particiones - Creación"

    continue=$(yesnoBox "Particiones" "¿Desea modificar las particiones de algún disco?")
    while [ "$continue" == "0" ]; do
        device=$(menuBox "Seleccione el disco que desea particionar:" "$(lsblk -l | grep disk | awk '{print $1,$4}')" 10 50)
        if [ -n "$device" ]; then
            partitionProgram=$(menuBoxN "Seleccione la herramienta que desa usar para particionar $device:" "cfdisk parted cgdisk" 12 50)
            if [ -n "$partitionProgram" ]; then
                $partitionProgram /dev/$device
            fi
        fi
        
        continue=$(yesnoBox "Particiones" "¿Desea modificar las particiones de otro disco?")
    done

    mountFormatPartition "/"
    mountFormatPartition "/boot"
    mountFormatPartition "/home"

    backtitle="Particiones - SWAP"

    partition=$(menuBox "Seleccione la partición que desea usar como SWAP:" "$(lsblk -l | grep part | awk '{print $1,$4}')" 15 50)
    if [ -n "$partition" ]; then
        yesno=$(yesnoBox "¡ATENCIÓN!" "¿Está seguro de que desea formatear y activar $partition como SWAP?\n¡SE PERDERÁN TODOS LOS DATOS!")
        if [ "$yesno" == "0" ]; then
            mkswap /dev/$partition
            swapon /dev/$partition
        fi
    fi

    backtitle="Instalación del sistema base 1/3 - Sistema base"

    packages="base base-devel grub-bios networkmanager dialog wget vim"
    yesno=$(yesnoBox "Synaptics" "¿Tiene este ordeandor un TouchPad Synaptics?")
    if [ "$yesno" == "0" ]; then
        packages="$packages xf86-input-synaptics"
    fi

    pacstrap /mnt $packages
    genfstab -U -p /mnt >> /mnt/etc/fstab
    cp $0 /mnt/
    arch-chroot /mnt $0 chroot
    umount /mnt/{boot,home,}
    reboot

fi
if [ "$1" == "chroot" ]; then
######################################### CHROOT #########################################

    # Preconfiguration

    export LANG="es_ES.UTF-8"

    backtitle="Instalación del sistema base 2/3 - Configuración del teclado"

    keymap=$(menuBoxN "Seleccione su esquema de teclado:" "$(ls /usr/share/kbd/keymaps/i386/qwerty | cut -d "." -f1)" 20 50)
    if [ -z "$keymap" ]; then exit; fi
    loadkeys $keymap
    echo "KEYMAP=$keymap" > /etc/vconsole.conf

    backtitle="Instalación del sistema base 2/3 - Hostname"

    hostname=$(inputBox "Introduce un nombre para este equipo (hostname)")

    echo $hostname > /etc/hostname

    backtitle="Instalación del sistema base 2/3 - Zona horaria"

    zone=""
    continent=""
    while [ -z "$zone" ]; do
        continent=$(menuBoxN "Seleccione su el continente de su zona horaria" "$(ls -l /usr/share/zoneinfo/ | grep -e "^d.*" | awk '{print $9}')" 15 50)
        zone=$(menuBoxN "Seleccione su su zona horaria" "$(ls -l /usr/share/zoneinfo/$continent | grep -e "^-.*" | awk '{print $9}')" 15 50)
    done
    ln -s /usr/share/zoneinfo/$continent/$zone /etc/localtime

    backtitle="Instalación del sistema base 2/3 - Localización"

    locale=""
    while [ -z "$locale" ]; do
        locale=$(menuBox "Seleccione su localización" "$(cat /etc/locale.gen | grep -e "^#[a-z]\{2,3\}_[A-Z]\{2\}.*" | tr -d "#" | awk '{print $1,$2}')" 15 50)
    done
    echo $localeip

    echo "LANG=$locale" > /etc/locale.conf
    sed -i "s/^#$locale/$locale/g" /etc/locale.gen
    locale-gen

    device=$(menuBox "Seleccione el disco en el que desea instalar el cargador de arranque GRUB:" "$(lsblk -l | grep disk | awk '{print $1,$4}')" 10 50)
    if [ -n "$device" ]; then
        grub-install /dev/$device
        grub-mkconfig -o /boot/grub/grub.cfg
        mkinitcpio -p linux
        passwd
    fi

fi
