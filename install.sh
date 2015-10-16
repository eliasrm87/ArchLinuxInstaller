#! /bin/bash

wget https://raw.githubusercontent.com/IgekoSC/ArchLinuxInstaller/master/utils.sh

source $(pwd -P)/utils.sh

# backtitle="Conección a Internet"
# 
# yesno=$(yesnoBox "WiFi" "¿Desea conectarse a alguna red WiFi?")
# if [ "$yesno" == "0" ]; then
#     wifi-menu
# fi

uefi=$(efivar -l 2>&1 | grep -c "error")
if [ "$uefi" == "0" ]; then
    uefi="uefi"
else
    uefi="legacy"
fi

backtitle="Particiones - Creación"

continue=$(yesnoBox "Particiones" "¿Desea modificar las particiones de algún disco?")
while [ "$continue" == "0" ]; do
    device=$(menuBox "Seleccione el disco que desea particionar:" "$(lsblk -l | grep disk | awk '{print $1,$4}')" 10 50)
    if [ -n "$device" ]; then
        partitionProgram=$(menuBoxN "Seleccione la herramienta que desa usar para particionar $device:" "cfdisk parted cgdisk" 12 50)
        if [ -n "$partitionProgram" ]; then
            reset
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
        reset
        mkswap /dev/$partition
        swapon /dev/$partition
    fi
fi

backtitle="Instalación del sistema base 1/3 - Sistema base"

packages="base base-devel networkmanager dialog wget vim"

uefi=$(efivar -l 2>&1 | grep -c "error")
if [ "$uefi" == "uefi" ]; then
    packages="$packages efibootmgr grub"
else
    packages="$packages grub-bios"
fi

yesno=$(yesnoBox "Synaptics" "¿Tiene este ordeandor un TouchPad Synaptics?")
if [ "$yesno" == "0" ]; then
    packages="$packages xf86-input-synaptics"
fi

yesno=$(yesnoBox "Resumen" "Se van a instalar los siguientes paquetes: $packages/n/n¿Desea continuar?")
reset
if [ "$yesno" == "0" ]; then
    pacstrap /mnt $packages
fi

genfstab -U -p /mnt >> /mnt/etc/fstab
mkdir /mnt/ArchLinuxInstaller
wget https://raw.githubusercontent.com/IgekoSC/ArchLinuxInstaller/master/chroot.sh -O /mnt/ArchLinuxInstaller/chroot.sh
cp ./utils.sh /mnt/ArchLinuxInstaller/
arch-chroot /mnt "/ArchLinuxInstaller/chroot.sh" $uefi
reset
umount /mnt/{boot,home,}
