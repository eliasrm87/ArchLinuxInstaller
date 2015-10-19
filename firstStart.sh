#! /bin/bash

source $( cd "$( dirname "$0" )" && pwd )/utils.sh


systemctl start NetworkManager.service
systemctl enable NetworkManager.service

backtitle="Usuario"

username=$(inputBox "Introduce tu nombre de usuario")

useradd -m -g users -G audio,lp,optical,storage,video,wheel,games,power,scanner -s /bin/bash $username
reset
passwd $username

yesno=$(yesnoBox "Habilitar sudo" "¿Desea activar el grupo wheel en sudoers?")
if [ "$yesno" == "0" ]; then
    line="%wheel ALL=(ALL) ALL"
    sed -i "s/^#$line/$line/g" /etc/sudoers
fi

backtitle="Conección a Internet"

yesno=$(yesnoBox "WiFi" "¿Desea conectarse a alguna red WiFi?")
if [ "$yesno" == "0" ]; then
    ssid=$(inputBox "Introduce el SSID de la red WiFi")
    password=$(inputBox "Introduce la contraseña de la red WiFi")
    nmcli dev wifi connect "$ssid" password "$password"
fi

reset
pacman -Syu

backtitle="Servidor gráfico X11"

yesno=$(yesnoBox "X11" "¿Desea instalar servidor gráfico X11?")
if [ "$yesno" == "0" ]; then
    reset
    pacman -S xorg-server xorg-xinit xorg-utils xorg-server-utils mesa mesa-demos
    
    videoCard=$(menuBoxN "Seleccione el fabricante de su tarjeta gráfica" "nvidia nvidia_legacy nvidia_nouveau ati intel vesa" 15 50)
    reset
    if [ $videoCard == "nvidia" ]; then
        pacman -S nvidia nvidia-utils
    fi
    if [ $videoCard == "nvidia_legacy" ]; then
        pacman -S nvidia-304xx
    fi
    if [ $videoCard == "nvidia_nouveau" ]; then
        pacman -S xf86-video-nouveau
    fi
    if [ $videoCard == "ati" ]; then
        pacman -S xf86-video-ati
    fi
    if [ $videoCard == "intel" ]; then
        pacman -S xf86-video-intel
    fi
    if [ $videoCard == "vesa" ]; then
        pacman -S xf86-video-vesa
    fi
    
    pacman -S xorg-twm xorg-xclock xterm
fi

backtitle="Teclado X11"

yesno=$(yesnoBox "Teclado" "¿Desea establecer distribución de teclado para X11 como 'es'?")
if [ "$yesno" == "0" ]; then
    reset
    #Hay que mejorar esto para que soporte varios idiomas
    wget https://raw.githubusercontent.com/IgekoSC/ArchLinuxInstaller/master/10-keyboard.conf -O /etc/X11/xorg.conf.d/10-keyboard.conf
fi


backtitle="Repositorios"

yesno=$(yesnoBox "multilib" "¿Desea activar repositorio multilib?")
if [ "$yesno" == "0" ]; then
    echo '[multilib]' > /etc/pacman.conf
    echo 'Include = /etc/pacman.d/mirrorlist' > /etc/pacman.conf
    reset
    pacman -Sy
fi

yesno=$(yesnoBox "archlinuxfr" "¿Desea activar repositorio archlinuxfr?")
if [ "$yesno" == "0" ]; then
    echo '[archlinuxfr]' > /etc/pacman.conf
    echo 'SigLevel = Never' > /etc/pacman.conf
    echo 'Server = http://repo.archlinux.fr/$arch' > /etc/pacman.conf
    reset
    pacman -Sy
fi

yesno=$(yesnoBox "yaourt" "¿Desea instalar yaourt?")
if [ "$yesno" == "0" ]; then
    reset
    pacman -S yaourt
    yaourt -Syua
fi


backtitle="Audio"

yesno=$(yesnoBox "Pulseaudio" "¿Desea instalar Pulseaudio?")
if [ "$yesno" == "0" ]; then
    reset
    pacman -S pulseaudio pulseaudio-alsa
fi


backtitle="Fuentes"

yesno=$(yesnoBox "Fuentes" "¿Desea instalar fuentes recomendadas?")
if [ "$yesno" == "0" ]; then
    reset
    pacman -S ttf-liberation ttf-bitstream-vera ttf-dejavu ttf-droid ttf-freefont artwiz-fonts
fi
