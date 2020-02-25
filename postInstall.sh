#! /bin/bash

set -e

. gettext.sh

TEXTDOMAIN=postInstall

source $( cd "$( dirname "$0" )" && pwd )/utils.sh

function setupNetwork {
    reset
    systemctl start NetworkManager.service
    systemctl enable NetworkManager.service

    backtitle="$(eval_gettext "Internet connection")"

    if [ "$(iw dev | wc -l)" -gt "0" ]; then
        yesno=$(yesnoBox 0 0 "WiFi" "$(eval_gettext "Do you want to connect to a WiFi network?")")
        
        if [ "$yesno" == "0" ]; then
            ssid=$(menuBoxN 15 50 "$(eval_gettext "Select the WiFi network you want to connect to")" "$(nmcli dev wifi list | grep -v "SSID" | tr "*" " " | awk '{print $1}')")
            password=$(inputBox 0 0 "$("Type password for %s" "$ssid")")
            nmcli dev wifi connect "$ssid" password "$password"
        fi
    fi
    
    ping archlinux.org -c 3 2> /dev/null
    connected=$?
    if [ "$connected" != "0" ]; then
        msgBox 10 50 "$(eval_gettext "ERROR")" "$(eval_gettext "No internet connection found.\n\nPlug in a network cable and try this step again")"
        return 1
    fi
}

function installXdgUserDirs {
    reset
    pacman -Syu
    pacman -S xdg-user-dirs
}

function setupUsers {
    backtitle="$(eval_gettext "Users")"

    yesno=$(yesnoBox 0 0 "$(eval_gettext "New user")" "$(eval_gettext "Do you want to create a new user?")")
    if [ "$yesno" == "0" ]; then
        username=$(inputBox 0 0 "$(eval_gettext "Type name for the new user")")
        if [ -n "$username" ]; then
            useradd -m -g users -G audio,lp,optical,storage,video,wheel,games,power,scanner -s /bin/bash $username
            reset
            passwd $username
        fi
    fi

    n=$(grep -n -m1 "^# %wheel ALL=(ALL) ALL" /etc/sudoers | cut -d ":" -f1)
    if [ -n "$n" ]; then
        yesno=$(yesnoBox 0 0 "$(eval_gettext "Enable sudo")" "$(eval_gettext "Do you want to enable wheel group on sudoers?")")
        if [ "$yesno" == "0" ]; then
            sed -i "${n}s/^#//g" /etc/sudoers
        fi
    fi
}

function installX11 {
    backtitle="$(eval_gettext "X11 graphical server")"

    yesno=$(yesnoBox 0 0 "X11" "$(eval_gettext "Do you want to install X11 graphical server?")")
    if [ "$yesno" == "0" ]; then
        reset
        pacman -S xorg-server xorg-xinit mesa mesa-demos

        videoCard=$(menuBoxN 15 50 "$(eval_gettext "Select your graphics card manufacturer")" "$(printf "intel nvidia nvidia_nouveau optimus_bumblebee ati vesa virtualbox nvidia-340xx_legacy nvidia-304xx_legacy optimus_bumblebee_340xx_legacy optimus_bumblebee_304xx_legacy %s" "$(eval_gettext "None")")")
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
}

function setupX11Keyboard {
    backtitle="$(eval_gettext "X11 keyboard")"

    #Hay que mejorar esto para que soporte varios idiomas
    yesno=$(yesnoBox 0 0 "$(eval_gettext "Keyboard")" "$(eval_gettext "Do you want to set keyboard distribution for X11 to 'es'?")")
    if [ "$yesno" == "0" ]; then
        reset
        wget https://raw.githubusercontent.com/erm2587/ArchLinuxInstaller/master/10-keyboard.conf -O /etc/X11/xorg.conf.d/10-keyboard.conf
    fi
}

function enableRepo {
    backtitle="$(eval_gettext "Repositories")"
    
    n=$(grep -n -m1 "^#\[$1\]" /etc/pacman.conf | cut -d ":" -f1)
    if [ -n "$n" ]; then
        yesno=$(yesnoBox 0 0 "$1" "$(printf "$(eval_gettext "Do you want to enable %s repository?")" "$1")")
        if [ "$yesno" == "0" ]; then
            sed -i "${n}s/^#//g" /etc/pacman.conf
            ((n++))
            sed -i "${n}s/^#//g" /etc/pacman.conf
            reset
            pacman -Sy
        fi
    fi
}

function setupRepositories {
    enableRepo "multilib"
    enableRepo "community"

    yesno=$(yesnoBox 0 0 "Pacman" "$(eval_gettext "Do you want to enable pacman colors?")")
    if [ "$yesno" == "0" ]; then
        sed -i '/^#Color/s/^#//' /etc/pacman.conf
    fi
}

function installSound {
    backtitle="$(eval_gettext "Sound")"

    yesno=$(yesnoBox 0 0 "Pulseaudio" "$(eval_gettext "Do you want to install Pulseaudio?")")
    if [ "$yesno" == "0" ]; then
        reset
        pacman -S pulseaudio pulseaudio-alsa
    fi
}

function installFonts {
    backtitle="$(eval_gettext "Fonts")"

    yesno=$(yesnoBox 0 0 "$(eval_gettext "Fonts")" "$(eval_gettext "Do you want tu install recomended fonts?")")
    if [ "$yesno" == "0" ]; then
        reset
        pacman -S ttf-liberation ttf-bitstream-vera ttf-dejavu ttf-droid ttf-freefont
    fi
}

function installDesktop {
    backtitle="$(eval_gettext "Desktop")"

    yesno=$(yesnoBox 0 0 "$(eval_gettext "Desktop")" "$(eval_gettext "Do you want to install a desktop enviroment?")")
    if [ "$yesno" == "0" ]; then

        desktop=$(menuBoxN 15 50 "$(eval_gettext "Select your favorite desktop")" "gnome kde lxde xfce lxqt cinnamon openbox")
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
        sessionManager=$(menuBoxN 15 50 "$(eval_gettext "Select your favorite session manager")" "sddm gdm")
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
}

function finishInstallation {
    reset
    clear

    yesno=$(yesnoBox 10 50 "$(eval_gettext "Installation finished")" "$(eval_gettext "Installation is finised. If everthing went fine, after reboot, you will be able to start your brand new system.\n\nDo you want to reboot now?")")
    reset
    if [ "$yesno" == "0" ]; then
        reboot
    fi
    
    exit 0
}

function onStepError {
    if [ "$1" != "quiet" ]; then
        echo
        echo "$(eval_gettext "Error:") $(eval_gettext "An unexpected error has occurred")"
        read -n 1 -s -r -p "$(eval_gettext "Press any key to continue")"
    fi
    step=$(($step * -1))
}

################################################## MAIN ##################################################

backtitle="$(printf "$(eval_gettext "ArchLinux instalation script %s")" "v$version")"

msgBox 10 50 "$(eval_gettext "Welcome back")" "$(eval_gettext "Base system installation is finised. Now you can proceed to configure and install some other packages.")"

step=1

if [ "$1" == "menu" ]; then
    step=-1
fi

while [ true ]; do
    if [ "$step" -le "0" ]; then
        step="$(menuBoxNn 15 50 "$(($step*-1))" "$(eval_gettext "Select installation step:")" \
        1  "$(eval_gettext "Network setup")"            \
        2  "$(eval_gettext "Install xdg-user-dirs")"    \
        3  "$(eval_gettext "Setup users")"              \
        4  "$(eval_gettext "Install X11 server")"       \
        5  "$(eval_gettext "Setup X11 keyboard")"       \
        6  "$(eval_gettext "Setup repositories")"       \
        7  "$(eval_gettext "Install sound system")"     \
        8  "$(eval_gettext "Install recomended fonts")" \
        9  "$(eval_gettext "Install desktop")"          \
        10 "$(eval_gettext "Finish instalation")"       \
        11 "$(eval_gettext "Open terminal")"            \
        )"
    fi

    case "$step" in
        1)
            if setupNetwork; then
                step=$(($step+1))
            else
                onStepError "quiet"
                continue
            fi
            ;;
        2)
            if installXdgUserDirs; then
                step=$(($step+1))
            else
                onStepError
                continue
            fi
            ;;
        3)
            if setupUsers; then
                step=$(($step+1))
            else
                onStepError
                continue
            fi
            ;;
        4)
            if installX11; then
                step=$(($step+1))
            else
                onStepError
                continue
            fi
            ;;
        5)
            if setupX11Keyboard; then
                step=$(($step+1))
            else
                onStepError
                continue
            fi
            ;;
        6)
            if setupRepositories; then
                step=$(($step+1))
            else
                onStepError
                continue
            fi
            ;;
        7)
            if installSound; then
                step=$(($step+1))
            else
                onStepError
                continue
            fi
            ;;
        8)
            if installFonts; then
                step=$(($step+1))
            else
                onStepError
                continue
            fi
            ;;
        9)
            if installDesktop; then
                step=$(($step+1))
            else
                onStepError
                continue
            fi
            ;;
        10)
            if finishInstallation; then
                step=$(($step+1))
            else
                onStepError
                continue
            fi
            ;;
        11)
            echo "$(eval_gettext "Type 'exit' to return to menu:")"
            if zsh; then
                step=$(($step*-1))
            else
                onStepError "quiet"
                continue
            fi
            ;;
        *)
            step=0
            exit 1
            ;;
    esac
done

exit 1
