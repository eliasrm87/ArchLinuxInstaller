#! /bin/bash

source $( cd "$( dirname "$0" )" && pwd )/utils.sh


function enableRepo {
    n=$(grep -n -m1 "^#\[$1\]" /etc/pacman.conf | cut -d ":" -f1)
    if [ -n "$n" ]; then
        yesno=$(yesnoBox "$1" "¿Desea activar repositorio $1?")
        if [ "$yesno" == "0" ]; then
            sed -i "${n}s/^#//g" /etc/pacman.conf
            ((n++))
            sed -i "${n}s/^#//g" /etc/pacman.conf
            reset
            pacman -Sy
        fi
    fi
}


backtitle="Script de instalación de ArchLinux Igeko v.0.0.1"

msgBox "Bienvenido de nuevo" "La instalación del sistema base ha finalizado. A continuación se procederá a configurar el sistema e instalar algunos paquetes." 10 50

reset
systemctl start NetworkManager.service
systemctl enable NetworkManager.service

backtitle="Conexión a Internet"

connected=-1
yesno=$(yesnoBox "WiFi" "¿Desea conectarse a alguna red WiFi?")
while [ "$connected" != "0" ]; do
    if [ "$yesno" == "0" ]; then
        ssid=$(menuBoxN "Seleccione la red WiFi a la que desea conectarse" "$(nmcli dev wifi list | grep -v "SSID" | tr "*" " " | awk '{print $1}')" 15 50)
        password=$(inputBox "Introduce la contraseña de para $ssid")
        nmcli dev wifi connect "$ssid" password "$password"
    fi
    ping google.com -c 3 2> /dev/null
    connected=$?
    if [ "$connected" != "0" ]; then
        msgBox "ERROR" "No se ha detectado una conexión a Internet.\n\nConecte el equipo por cable o pulse ENTER para contectarse a una WiFi." 10 50
        yesno="0"
        ping google.com -c 3 2> /dev/null
        connected=$?
    fi
done

reset
pacman -Syu
pacman -S xdg-user-dirs

backtitle="Usuarios"

yesno=$(yesnoBox "Crear usuario" "¿Desea crear un nuevo usuario?")
if [ "$yesno" == "0" ]; then
    username=$(inputBox "Introduce tu nombre de usuario")
    if [ -n "$username" ]; then
        useradd -m -g users -G audio,lp,optical,storage,video,wheel,games,power,scanner -s /bin/bash $username
        reset
        passwd $username
    fi
fi

n=$(grep -n -m1 "^# %wheel ALL=(ALL) ALL" /etc/sudoers | cut -d ":" -f1)
if [ -n "$n" ]; then
    yesno=$(yesnoBox "Habilitar sudo" "¿Desea activar el grupo wheel en sudoers?")
    if [ "$yesno" == "0" ]; then
        sed -i "${n}s/^#//g" /etc/sudoers
    fi
fi


backtitle="Servidor gráfico X11"

yesno=$(yesnoBox "X11" "¿Desea instalar servidor gráfico X11?")
if [ "$yesno" == "0" ]; then
    reset
    pacman -S xorg-server xorg-xinit xorg-utils xorg-server-utils mesa mesa-demos
    
    videoCard=$(menuBoxN "Seleccione el fabricante de su tarjeta gráfica" "nvidia nvidia_legacy nvidia_nouveau ati intel vesa virtualbox" 15 50)
    reset
    
    case "$videoCard" in
    nvidia)
        pacman -S nvidia nvidia-utils
        ;;
    nvidia-304xx)
        pacman -S nvidia-304xx
        ;;
    nvidia_nouveau)
        pacman -S xf86-video-nouveau
        ;;
    ati)
        pacman -S xf86-video-ati
        ;;
    intel)
        pacman -S xf86-video-intel
        ;;
    vesa)
        pacman -S xf86-video-vesa
        ;;
    virtualbox)
        pacman -S virtualbox-guest-utils
        systemctl start vboxservice
        systemctl enable vboxservice
        ;;
    *)
        ;;
    esac
    
    pacman -S xorg-twm xorg-xclock xterm
fi

backtitle="Teclado X11"

#Hay que mejorar esto para que soporte varios idiomas
yesno=$(yesnoBox "Teclado" "¿Desea establecer distribución de teclado para X11 como 'es'?")
if [ "$yesno" == "0" ]; then
    reset
    wget https://raw.githubusercontent.com/IgekoSC/ArchLinuxInstaller/master/10-keyboard.conf -O /etc/X11/xorg.conf.d/10-keyboard.conf
fi


backtitle="Repositorios"

enableRepo "multilib"
enableRepo "community"

if [ $(cat /etc/pacman.conf | grep -c "^\[archlinuxfr\]") == "0" ]; then
    yesno=$(yesnoBox "archlinuxfr" "¿Desea activar repositorio archlinuxfr?")
    if [ "$yesno" == "0" ]; then
        echo '[archlinuxfr]' >> /etc/pacman.conf
        echo 'SigLevel = Never' >> /etc/pacman.conf
        echo 'Server = http://repo.archlinux.fr/$arch' >> /etc/pacman.conf
        reset
        pacman -Sy
        yesno=$(yesnoBox "yaourt" "¿Desea instalar yaourt?")
        if [ "$yesno" == "0" ]; then
            reset
            pacman -S yaourt
            yaourt -Syua
        fi
    fi
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

backtitle="Escritorio"

yesno=$(yesnoBox "Escritorio" "¿Desea instalar un escritorio?")
if [ "$yesno" == "0" ]; then

    desktop=$(menuBoxN "Seleccione su escritorio favorito" "gnome kde lxde xfce lxqt cinnamon openbox" 15 50)
    reset
    
    case "$desktop" in
    gnome)
        pacman -S gnome gnome-extra gnome-tweak-tool
        ;;
    kde)
        lang=$(menuBoxN "Seleccione su idioma" "$(pacman -Ss kde-l10n | grep "/kde-l10n" | cut -d "-" -f3 | cut -d " " -f1)" 15 50)
        pacman -S plasma kde-l10n-$lang
        ;;
    lxde)
        pacman -S lxde
        ;;
    xfce)
        pacman -S xfce4 xfce4-goodies network-manager-applet
        ;;
    lxqt)
        pacman -S lxqt
        ;;
    cinnamon)
        pacman -S cinnamon
        ;;
    openbox)
        pacman -S openbox
        ;;
    *)
        ;;
    esac

    reset
    sessionManager=$(menuBoxN "Seleccione su gestor de inicio de sesión favorito" "sddm gdm" 15 50)
    reset
    
    case "$sessionManager" in
    gdm)
        pacman -S gdm
        systemctl disable sddm
        systemctl enable gdm.service
        ;;
    sddm)
        pacman -S sddm sddm-kcm
        systemctl disable gdm.service
        systemctl enable sddm
        ;;
    *)
        ;;
    esac
fi

reset
