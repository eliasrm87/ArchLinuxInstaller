#! /bin/bash

ping google.com -c 3 2> /dev/null
if [ "$?" != "0" ]; then
    wifi-menu
fi

wget https://raw.githubusercontent.com/IgekoSC/ArchLinuxInstaller/master/utils.sh

source $( cd "$( dirname "$0" )" && pwd )/utils.sh


function mountFormatPartition {
    backtitle="Particiones - Puntos de motaje y formato ($uefi)"

    yesno=0
    cryptPartition=1
    partitionPath=""
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
            partitionPath="/dev/$partition"
            map="cryptroot${1/\//}"
            yesno=$(yesnoBox "Formatear" "¿Desea formatear $partition ($1)?")
            if [ "$yesno" == "0" ]; then
                format=""
                if [ "$uefi" == "uefi" ] && [ "$1" == "/boot" ]; then
                    format="fat -F32"
                else
                    if [ "$1" != "/boot" ]; then
                        cryptPartition=$(yesnoBox "Cifrar" "¿Desea cifrar $partition ($1)?")
                        if [ "$cryptPartition" == "0" ]; then
                            if [ "$1" == "/" ]; then
                                cryptsetup -y -v luksFormat "$partitionPath"
                                cryptsetup open $partitionPath $map
                            else
                                dd bs=512 count=4 if=/dev/urandom of=$map.keyfile iflag=fullblock
                                cryptsetup -y -v luksFormat "$partitionPath" "$map.keyfile"
                                cryptsetup --key-file "$map.keyfile" open $partitionPath $map
                            fi
                            partitionPath="/dev/mapper/$map"
                        fi
                    fi
                    format=$(menuBoxN "Seleccione el sistema de archivos para formatear $partition" "$(ls /bin/mkfs.* | cut -d "." -f2)" 15 50)
                fi
                if [ -n "$format" ]; then
                    yesno=$(yesnoBox "¡ATENCIÓN!" "¿Está seguro de que desea formatear $partition ($1) en $format?\n¡SE PERDERÁN TODOS LOS DATOS!")
                    if [ "$yesno" == "0" ]; then
                        reset
                        mkfs.$format $partitionPath
                    fi
                fi
            else
                if [ "$(blkid $partitionPath | grep -c "crypto_LUKS")" != "0" ]; then
                    reset
                    if [ "$1" == "/" ]; then
                        cryptsetup open $partitionPath $map
                    else
                        cryptsetup --key-file "/mnt/etc/keyfiles/$map.keyfile" open $partitionPath $map
                    fi
                    partitionPath="/dev/mapper/$map"
                fi
            fi
            
            mkdir -p /mnt$1
            mount $partitionPath /mnt$1
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
    #Check if there are encrypted partitions
    cryptedroot=$(mount | grep -c "cryptroot")
    if [ "$cryptedroot" != "0" ]; then
        #Add "encrypt" hook if root partition is encrypted
        n=$(cat /mnt/etc/mkinitcpio.conf | grep -n "^HOOKS=" | cut -d ":" -f1)
        sed -i "${n}s/filesystems/encrypt filesystems/g" /mnt/etc/mkinitcpio.conf
        #Add grub parameters for root partition and add extra entries to crypttab
        partition=""
        map=""
        for line in $(lsblk -l | grep -B 1 "cryptroot" | awk '{print $1}'); do
            if [ -z "$partition" ]; then
                partition=$line
            else
                map=$line
                if [ "$map" == "cryptroot" ]; then
                    uuid=$(lsblk -lf | grep $partition | awk '{print $3}')
                    sed -i "s/^GRUB_CMDLINE_LINUX=\"/GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$uuid:cryptroot root=\/dev\/mapper\/cryptroot/g" /mnt/etc/default/grub
                else
                    mkdir -p /mnt/etc/keyfiles
                    cp $map.keyfile /mnt/etc/keyfiles/$map.keyfile
                    chmod 0400 /mnt/etc/keyfiles/$map.keyfile
                    echo "$map    /dev/$partition      /etc/keyfiles/$map.keyfile luks" >> /mnt/etc/crypttab
                fi
                partition=""
            fi
        done
    fi
fi

mkdir -p /mnt/opt/ArchLinuxInstaller
cp ./utils.sh /mnt/opt/ArchLinuxInstaller/
wget https://raw.githubusercontent.com/IgekoSC/ArchLinuxInstaller/master/chroot.sh -O /mnt/opt/ArchLinuxInstaller/chroot.sh
chmod +x /mnt/opt/ArchLinuxInstaller/chroot.sh
wget https://raw.githubusercontent.com/IgekoSC/ArchLinuxInstaller/master/postInstall.sh -O /mnt/opt/ArchLinuxInstaller/postInstall.sh
chmod +x /mnt/opt/ArchLinuxInstaller/postInstall.sh
arch-chroot /mnt "/opt/ArchLinuxInstaller/chroot.sh" $uefi
reset
yesno=$(yesnoBox "Instalación finalizada" "La instalación del sistema base ha finalizado. Si todo ha ido bien, tras reiniciar, debería poder iniciar el sistema recién instalado.\n\n¿Desea desmontar unidades y reiniciar?" 10 50)
reset
if [ "$yesno" == "0" ]; then
    umount -R /mnt
    #Close all encrypted partitions
    for partition in $(lsblk -l | grep crypt | awk '{print $1}'); do
        cryptsetup close $partition
    done
    reboot
fi
