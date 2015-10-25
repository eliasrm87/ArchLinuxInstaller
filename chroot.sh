#! /bin/bash

source $( cd "$( dirname "$0" )" && pwd )/utils.sh


uefi=$1

export LANG="es_ES.UTF-8"

backtitle="Configuración del sistema base - Configuración del teclado"

keymap=$(menuBoxN "Seleccione su esquema de teclado:" "$(ls /usr/share/kbd/keymaps/i386/qwerty | cut -d "." -f1)" 20 50)
if [ -z "$keymap" ]; then exit; fi
loadkeys $keymap
echo "KEYMAP=$keymap" > /etc/vconsole.conf

backtitle="Configuración del sistema base - Hostname"

hostname=$(inputBox "Introduce un nombre para este equipo (hostname)")

echo $hostname > /etc/hostname

backtitle="Configuración del sistema base - Zona horaria"

zone=""
continent=""
while [ -z "$zone" ]; do
    continent=$(menuBoxN "Seleccione su el continente de su zona horaria" "$(ls -l /usr/share/zoneinfo/ | grep -e "^d.*" | awk '{print $9}')" 15 50)
    zone=$(menuBoxN "Seleccione su su zona horaria" "$(ls -l /usr/share/zoneinfo/$continent | grep -e "^-.*" | awk '{print $9}')" 15 50)
done
ln -s /usr/share/zoneinfo/$continent/$zone /etc/localtime

backtitle="Configuración del sistema base - Localización"

yesno="0"
if [ -f /etc/locale.conf ]; then
    yesno=$(yesnoBox "Localización" "¿Desea cambiar la localización?")
fi
if [ "$yesno" == "0" ]; then
    locale=""
    while [ -z "$locale" ]; do
        locale=$(menuBox "Seleccione su localización" "$(cat /etc/locale.gen | grep -e "^#[a-z]\{2,3\}_[A-Z]\{2\}.*" | tr -d "#" | awk '{print $1,$2}')" 15 50)
    done

    echo "LANG=$locale" > /etc/locale.conf
    sed -i "s/^#$locale/$locale/g" /etc/locale.gen
    locale-gen
fi

backtitle="Cargador de arranque - GRUB ($uefi)"

yesno=$(yesnoBox "Localización" "¿Desea instalar cargador de arranque GRUB?")
if [ "$yesno" == "0" ]; then
    if [ "$uefi" == "uefi" ]; then
        reset
        grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=arch_grub --recheck
        grub-mkconfig -o /boot/grub/grub.cfg
        mkinitcpio -p linux
        #UEFI firmware workaround - https://wiki.archlinux.org/index.php/GRUB#UEFI_firmware_workaround
        mkdir /boot/EFI/boot
        cp /boot/EFI/arch_grub/grubx64.efi /boot/EFI/boot/bootx64.efi
    else
        device=$(menuBox "Seleccione el disco en el que desea instalar el cargador de arranque GRUB:" "$(lsblk -l | grep disk | awk '{print $1,$4}')" 10 50)
        if [ -n "$device" ]; then
            reset
            grub-install /dev/$device
            grub-mkconfig -o /boot/grub/grub.cfg
            mkinitcpio -p linux
        fi
    fi
fi

backtitle="Seguridad"

msgBox "Contraseña para root" "A continuación se le solicitará que introduzca la contraseña de super usuario". 10 50

reset

passwd
