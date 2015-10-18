#! /bin/bash

wget https://raw.githubusercontent.com/IgekoSC/ArchLinuxInstaller/master/utils.sh

source $( cd "$( dirname "$0" )" && pwd )/utils.sh


function mountFormatPartition {
    backtitle="Particiones - Puntos de motaje y formato ($uefi)"

    yesno=0
    if [ "$1" != "/" ]; then
        if [ "$1" != "/boot" ] || [ "$uefi" == "legacy" ]; then
            yesno=$(yesnoBox "Montar $1" "Desea especificar un punto de montaje para $1?")
        fi
    fi
    if [ "$yesno" == "0" ]; then
        partition=""
        while [ -z $partition ]; do
            partition=$(menuBox "Seleccione la partición que desea montar en $1" "$(lsblk -l | grep part | awk '{print $1,$4}')" 15 50)
        done
        if [ -n "$partition" ]; then

            yesno=$(yesnoBox "Formatear" "¿Desea formatear $partition ($1)?")
            if [ "$yesno" == "0" ]; then
                format=""
                if [ "$uefi" == "uefi" ] && [ "$1" == "/boot" ]; then
                    format="fat -F32"
                else
                    format=$(menuBoxN "Seleccione el sistema de archivos para formatear $partition" "$(ls /bin/mkfs.* | cut -d "." -f2)" 15 50)
                fi
                if [ -n "$format" ]; then
                    yesno=$(yesnoBox "¡ATENCIÓN!" "¿Está seguro de que desea formatear $partition ($1) en $format?\n¡SE PERDERÁN TODOS LOS DATOS!")
                    if [ "$yesno" == "0" ]; then
                        reset
                        mkfs.$format /dev/$partition
                    fi
                fi
            fi
            
            mkdir -p /mnt$1
            mount /dev/$partition /mnt$1
        fi
    fi
}

uefi="legacy"
if [ -e /sys/firmware/efi ]; then
    uefi="uefi"
fi

backtitle="Script de instalación de ArchLinux Igeko v.0.0.1"

msgBox "Bienvenido" "Este script actúa como guia de apoyo durante el proceso de instalación de ArchLinux. En cualquier momento puede detenerlo presionando Ctrl+C." 10 50

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

yesno=$(yesnoBox "Synaptics" "¿Desea usar una partición como SWAP?")
if [ "$yesno" == "0" ]; then
    partition=$(menuBox "Seleccione la partición que desea usar como SWAP:" "$(lsblk -l | grep part | awk '{print $1,$4}')" 15 50)
    if [ -n "$partition" ]; then
        yesno=$(yesnoBox "¡ATENCIÓN!" "¿Está seguro de que desea formatear y activar $partition como SWAP?\n¡SE PERDERÁN TODOS LOS DATOS!")
        if [ "$yesno" == "0" ]; then
            reset
            mkswap /dev/$partition
            swapon /dev/$partition
        fi
    fi
fi

backtitle="Conección a Internet"

yesno=$(yesnoBox "WiFi" "¿Desea conectarse a alguna red WiFi?")
if [ "$yesno" == "0" ]; then
    wifi-menu
fi

backtitle="Instalación del sistema base"

packages="base base-devel networkmanager os-prober dialog wget vim"
if [ "$uefi" == "uefi" ]; then
    packages="$packages efibootmgr grub"
else
    packages="$packages grub-bios"
fi

yesno=$(yesnoBox "Resumen" "Se van a instalar los siguientes paquetes:\n\n$packages\n\n¿Desea continuar?" 15 50)
reset
if [ "$yesno" == "0" ]; then
    pacstrap /mnt $packages
    genfstab -U -p /mnt >> /mnt/etc/fstab
fi

mkdir /mnt/ArchLinuxInstaller
wget https://raw.githubusercontent.com/IgekoSC/ArchLinuxInstaller/master/chroot.sh -O /mnt/ArchLinuxInstaller/chroot.sh
chmod +x /mnt/ArchLinuxInstaller/chroot.sh
cp ./utils.sh /mnt/ArchLinuxInstaller/
arch-chroot /mnt "/ArchLinuxInstaller/chroot.sh" $uefi
reset
yesno=$(yesnoBox "Instalación finalizada" "La instalación del sistema base ha finalizado. Si todo ha ido bien, tras reiniciar, debería poder iniciar el sistema recién instalado.\n\n¿Desea desmontar unidades y reiniciar?" 10 50)
reset
if [ "$yesno" == "0" ]; then
    umount -R /mnt
    reboot
fi
