#! /bin/bash

TEXTDOMAIN=postInstall

source $( cd "$( dirname "$0" )" && pwd )/utils.sh

function enableRepo {
    n=$(grep -n -m1 "^#\[$1\]" /etc/pacman.conf | cut -d ":" -f1)
    if [ -n "$n" ]; then
        yesno=$(yesnoBox 0 0 "$1" "$(printf $"Do you want to enable %s repository?" "$1")")
        if [ "$yesno" == "0" ]; then
            sed -i "${n}s/^#//g" /etc/pacman.conf
            ((n++))
            sed -i "${n}s/^#//g" /etc/pacman.conf
            reset
            pacman -Sy
        fi
    fi
}


backtitle="$(printf $"ArchLinux instalation script %s" "v$version")"

msgBox 10 50 $"Welcome back" $"Base system installation is finised. Now you can proceed to configure and install some other packages."

reset
systemctl start NetworkManager.service
systemctl enable NetworkManager.service

backtitle=$"Internet connection"

connected=-1
yesno=$(yesnoBox 0 0 "WiFi" $"Do you want to connect to any WiFi network?")
while [ "$connected" != "0" ]; do
    if [ "$yesno" == "0" ]; then
        ssid=$(menuBoxN 15 50 $"Select the WiFi network you want to connect to" "$(nmcli dev wifi list | grep -v "SSID" | tr "*" " " | awk '{print $1}')")
        password=$(inputBox 0 0 "$("Type password for %s" "$ssid")")
        nmcli dev wifi connect "$ssid" password "$password"
    fi
    ping archlinux.org -c 3 2> /dev/null
    connected=$?
    if [ "$connected" != "0" ]; then
        msgBox 10 50 $"ERROR" $"No internet connection found.\n\nPlug in a network cable or press ENTER for trying again to connect to a WiFi network."
        yesno="0"
        ping archlinux.org -c 3 2> /dev/null
        connected=$?
    fi
done

reset
pacman -Syu
pacman -S xdg-user-dirs

backtitle=$"Users"

yesno=$(yesnoBox 0 0 $"New user" $"Do you want to create a new user?")
if [ "$yesno" == "0" ]; then
    username=$(inputBox 0 0 $"Type name for the new user")
    if [ -n "$username" ]; then
        useradd -m -g users -G audio,lp,optical,storage,video,wheel,games,power,scanner -s /bin/bash $username
        reset
        passwd $username
    fi
fi

n=$(grep -n -m1 "^# %wheel ALL=(ALL) ALL" /etc/sudoers | cut -d ":" -f1)
if [ -n "$n" ]; then
    yesno=$(yesnoBox 0 0 $"Enable sudo" $"Do you want to enable wheel group on sudoers?")
    if [ "$yesno" == "0" ]; then
        sed -i "${n}s/^#//g" /etc/sudoers
    fi
fi


backtitle=$"X11 graphical server"

yesno=$(yesnoBox 0 0 "X11" $"Do you want to install X11 graphical server?")
if [ "$yesno" == "0" ]; then
    reset
    pacman -S xorg-server xorg-xinit mesa mesa-demos

    videoCard=$(menuBoxN 15 50 $"Select your graphics card manufacturer" "$(printf "intel nvidia nvidia_nouveau optimus_bumblebee ati vesa virtualbox nvidia-340xx_legacy nvidia-304xx_legacy optimus_bumblebee_340xx_legacy optimus_bumblebee_304xx_legacy %s" $"None")")
    reset

    case "$videoCard" in
    intel)
        pacman -S xf86-video-intel
        ;;
    nvidia)
        pacman -S nvidia nvidia-utils
        ;;
    nvidia_nouveau)
        pacman -S xf86-video-nouveau
        ;;
    optimus_bumblebee)
        pacman -S nvidia nvidia-utils bumblebee primus xf86-video-intel mesa
        systemctl enable bumblebeed.service
        ;;
    ati)
        pacman -S xf86-video-ati
        ;;
    vesa)
        pacman -S xf86-video-vesa
        ;;
    virtualbox)
        pacman -S virtualbox-guest-utils
        systemctl start vboxservice
        systemctl enable vboxservice
        ;;
    nvidia-340xx_legacy)
        pacman -S nvidia-340xx nvidia-340xx-utils
        ;;
    nvidia-304xx_legacy)
        pacman -S nvidia-304xx nvidia-304xx-utils
        ;;
    optimus_bumblebee_340xx_legacy)
        pacman -S nvidia-340xx nvidia-340xx-utils bumblebee primus xf86-video-intel mesa
        systemctl enable bumblebeed.service
        ;;
    optimus_bumblebee_304xx_legacy)
        pacman -S nvidia-304xx nvidia-304xx-utils bumblebee primus xf86-video-intel mesa
        systemctl enable bumblebeed.service
        ;;
    *)
        ;;
    esac

    pacman -S xorg-twm xorg-xclock xterm
fi

backtitle=$"X11 keyboard"

#Hay que mejorar esto para que soporte varios idiomas
yesno=$(yesnoBox 0 0 $"Keyboard" $"Do you want to set keyboard distribution for X11 to 'es'?")
if [ "$yesno" == "0" ]; then
    reset
    wget https://raw.githubusercontent.com/erm2587/ArchLinuxInstaller/master/10-keyboard.conf -O /etc/X11/xorg.conf.d/10-keyboard.conf
fi


backtitle=$"Repositories"

enableRepo "multilib"
enableRepo "community"

if [ $(cat /etc/pacman.conf | grep -c "^\[archlinuxfr\]") == "0" ]; then
    yesno=$(yesnoBox 0 0 "archlinuxfr" $"Do you want to enable archlinuxfr repository?")
    if [ "$yesno" == "0" ]; then
        echo '[archlinuxfr]' >> /etc/pacman.conf
        echo 'SigLevel = Never' >> /etc/pacman.conf
        echo 'Server = http://repo.archlinux.fr/$arch' >> /etc/pacman.conf
        reset
        pacman -Sy
        yesno=$(yesnoBox 0 0 "yaourt" $"Do you want to install yaourt?")
        if [ "$yesno" == "0" ]; then
            reset
            pacman -S yaourt
            yaourt -Syua
        fi
    fi
fi


backtitle=$"Sound"

yesno=$(yesnoBox 0 0 "Pulseaudio" $"Do you want to install Pulseaudio?")
if [ "$yesno" == "0" ]; then
    reset
    pacman -S pulseaudio pulseaudio-alsa
fi


backtitle=$"Fonts"

yesno=$(yesnoBox 0 0 $"Fonts" $"Do you want tu install recomended fonts?")
if [ "$yesno" == "0" ]; then
    reset
    pacman -S ttf-liberation ttf-bitstream-vera ttf-dejavu ttf-droid ttf-freefont artwiz-fonts
fi

backtitle=$"Desktop"

yesno=$(yesnoBox 0 0 $"Desktop" $"Do you want to install a desktop enviroment?")
if [ "$yesno" == "0" ]; then

    desktop=$(menuBoxN 15 50 $"Select your favorite desktop" "gnome kde lxde xfce lxqt cinnamon openbox")
    reset

    case "$desktop" in
    gnome)
        pacman -S gnome gnome-extra gnome-tweak-tool
        ;;
    kde)
        pacman -S plasma
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
    sessionManager=$(menuBoxN 15 50 $"Select your favorite session manager" "sddm gdm")
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
