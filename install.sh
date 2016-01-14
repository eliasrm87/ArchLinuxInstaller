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
            yesno=$(yesnoBox 0 0 "Montar $1" "Desea especificar un punto de montaje para $1?")
        fi
    fi
    if [ "$yesno" == "0" ]; then
        partition=""
        while [ -z $partition ]; do
            partition=$(menuBox 15 50 "Seleccione la partición que desea montar en $1" $(lsblk -l | grep part | awk '{print $1,$4}'))
        done
        if [ -n "$partition" ]; then
            partitionPath="/dev/$partition"
            map="cryptroot${1/\//}"
            yesno=$(yesnoBox 0 0 "Formatear" "¿Desea formatear $partition ($1)?")
            if [ "$yesno" == "0" ]; then
                format=""
                if [ "$uefi" == "uefi" ] && [ "$1" == "/boot" ]; then
                    format="fat -F32"
                else
                    if [ "$1" != "/boot" ]; then
                        cryptPartition=$(yesnoBox 0 0 "Cifrar" "¿Desea cifrar $partition ($1)?")
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
                    format=$(menuBoxN 15 50 "Seleccione el sistema de archivos para formatear $partition" "$(ls /bin/mkfs.* | cut -d "." -f2)")
                fi
                if [ -n "$format" ]; then
                    yesno=$(yesnoBox 0 0 "¡ATENCIÓN!" "¿Está seguro de que desea formatear $partition ($1) en $format?\n¡SE PERDERÁN TODOS LOS DATOS!")
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

msgBox 10 50 "Bienvenido" "Este script actúa como guia de apoyo durante el proceso de instalación de ArchLinux. En cualquier momento puede detenerlo presionando Ctrl+C."

backtitle="Particiones - Creación"

continue=$(yesnoBox 0 0 "Particiones" "¿Desea modificar las particiones de algún disco?")
while [ "$continue" == "0" ]; do
    device=$(menuBox 10 50 "Seleccione el disco que desea particionar:" $(lsblk -l | grep disk | awk '{print $1,$4}'))
    if [ -n "$device" ]; then
        partitionProgram=$(menuBoxN 12 50 "Seleccione la herramienta que desa usar para particionar $device:" "cfdisk parted cgdisk")
        if [ -n "$partitionProgram" ]; then
            reset
            $partitionProgram /dev/$device
        fi
    fi
    
    continue=$(yesnoBox 0 0 "Particiones" "¿Desea modificar las particiones de otro disco?")
done

mountFormatPartition "/"
mountFormatPartition "/boot"
mountFormatPartition "/home"

backtitle="Particiones - SWAP"

yesno=$(yesnoBox 0 0 "Synaptics" "¿Desea usar una partición como SWAP?")
if [ "$yesno" == "0" ]; then
    partition=$(menuBox 15 50 "Seleccione la partición que desea usar como SWAP:" $(lsblk -l | grep part | awk '{print $1,$4}'))
    if [ -n "$partition" ]; then
        yesno=$(yesnoBox 0 0 "¡ATENCIÓN!" "¿Está seguro de que desea formatear y activar $partition como SWAP?\n¡SE PERDERÁN TODOS LOS DATOS!")
        if [ "$yesno" == "0" ]; then
            reset
            mkswap /dev/$partition
            swapon /dev/$partition
        fi
    fi
fi

backtitle="Instalación del sistema base"

packages="base grub dialog"

if [ "$uefi" == "uefi" ]; then
    packages="$packages efibootmgr"
fi

extraPkgs=$(checklistBoxN 0 0 "Seleccione los paquetes de desea instalar:" "base-devel on networkmanager on os-prober on curl off wget off vim off")
userPkgs=$(inputBox 0 0 "Indique otros paquetes que desee instalar (opcional):")
packages="$packages $extraPkgs $userPkgs"

yesno=$(yesnoBox 15 50 "Resumen" "Se van a instalar los siguientes paquetes:\n\n$packages\n\n¿Desea continuar?")
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

backtitle="Configuración del sistema base - Configuración del teclado"

keymap=$(menuBoxN 20 50 "Seleccione su esquema de teclado:" "$(ls /mnt/usr/share/kbd/keymaps/i386/qwerty | cut -d "." -f1)")
if [ -n "$keymap" ]; then
    echo "KEYMAP=$keymap" > /mnt/etc/vconsole.conf
fi

backtitle="Configuración del sistema base - Hostname"

hostname=$(inputBox 0 0 "Introduce un nombre para este equipo (hostname)")

echo $hostname > /mnt/etc/hostname

backtitle="Configuración del sistema base - Zona horaria"

zone=""
continent=""
while [ -z "$zone" ]; do
    continent=$(menuBoxN 15 50 "Seleccione su el continente de su zona horaria" "$(ls -l /mnt/usr/share/zoneinfo/ | grep -e "^d.*" | awk '{print $9}')")
    zone=$(menuBoxN 15 50 "Seleccione su su zona horaria" "$(ls -l /mnt/usr/share/zoneinfo/$continent | grep -e "^-.*" | awk '{print $9}')")
done
ln -s /mnt/usr/share/zoneinfo/$continent/$zone /mnt/etc/localtime

backtitle="Configuración del sistema base - Localización"

yesno="0"
if [ -f /mnt/etc/locale.conf ]; then
    yesno=$(yesnoBox 0 0 "Localización" "¿Desea cambiar la localización?")
fi
if [ "$yesno" == "0" ]; then
    locale=""
    while [ -z "$locale" ]; do
        locale=$(menuBox 15 50 "Seleccione su localización" $(cat /mnt/etc/locale.gen | grep -e "^#[a-z]\{2,3\}_[A-Z]\{2\}.*" | tr -d "#" | awk '{print $1,$2}'))
    done

    echo "LANG=$locale" > /mnt/etc/locale.conf
    sed -i "s/^#$locale/$locale/g" /mnt/etc/locale.gen
    arch-chroot /mnt locale-gen
fi

backtitle="Cargador de arranque - GRUB ($uefi)"

yesno=$(yesnoBox 0 0 "Localización" "¿Desea instalar cargador de arranque GRUB?")
if [ "$yesno" == "0" ]; then
    if [ "$uefi" == "uefi" ]; then
        reset
        arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=arch_grub --recheck
        arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
        arch-chroot /mnt mkinitcpio -p linux
        #UEFI firmware workaround - https://wiki.archlinux.org/index.php/GRUB#UEFI_firmware_workaround
        mkdir /mnt/boot/EFI/boot
        cp /mnt/boot/EFI/arch_grub/grubx64.efi /mnt/boot/EFI/boot/bootx64.efi
    else
        device=$(menuBox 10 50 "Seleccione el disco en el que desea instalar el cargador de arranque GRUB:" $(lsblk -l | grep disk | awk '{print $1,$4}'))
        if [ -n "$device" ]; then
            reset
            arch-chroot /mnt grub-install /dev/$device
            arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
            arch-chroot /mnt mkinitcpio -p linux
        fi
    fi
fi

backtitle="Seguridad"

msgBox 10 50 "Contraseña para root" "A continuación se le solicitará que introduzca la contraseña de super usuario."

reset

arch-chroot /mnt passwd

mkdir -p /mnt/opt/ArchLinuxInstaller
cp ./utils.sh /mnt/opt/ArchLinuxInstaller/
wget https://raw.githubusercontent.com/IgekoSC/ArchLinuxInstaller/master/postInstall.sh -O /mnt/opt/ArchLinuxInstaller/postInstall.sh
chmod +x /mnt/opt/ArchLinuxInstaller/postInstall.sh
reset

yesno=$(yesnoBox 10 50 "Instalación finalizada" "La instalación del sistema base ha finalizado. Si todo ha ido bien, tras reiniciar, debería poder iniciar el sistema recién instalado.\n\n¿Desea desmontar unidades y reiniciar?")
reset
if [ "$yesno" == "0" ]; then
    umount -R /mnt
    #Close all encrypted partitions
    for partition in $(lsblk -l | grep crypt | awk '{print $1}'); do
        cryptsetup close $partition
    done
    reboot
fi
