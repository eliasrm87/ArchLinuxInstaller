#! /bin/bash
# shellcheck disable=SC2059


TEXTDOMAIN=install
export TEXTDOMAIN
TEXTDOMAINDIR="$( cd "$( dirname "$0" )" && pwd )/locale"
export TEXTDOMAINDIR
LANGUAGE="${*: -1}"
export LANGUAGE

# shellcheck disable=SC1091
. gettext.sh

IS_UEFI="legacy"
if [ -e /sys/firmware/efi ]; then
    IS_UEFI="uefi"
fi
export IS_UEFI

version="1.0"

############################################# DIALOG HELPERS #############################################

reset

pacman --noconfirm -Sy
pacman --noconfirm -S dialog

reset

function menuBox {
    local h=20
    local w=50

    if [ "$1" -gt "0" ]; then h=$1; fi
    if [ "$2" -gt "0" ]; then w=$2; fi

    local menu="$3"

    shift 3

    dialog --backtitle "$backtitle" --menu "$menu" "$h" "$w" "$(($#/2))" "$@" 3>&1 1>&2 2>&3 3>&-
}

function menuBoxN {
    local h=20
    local w=50

    if [ "$1" -gt "0" ]; then h=$1; fi
    if [ "$2" -gt "0" ]; then w=$2; fi

    local menu="$3"

    shift 3

    local options=()
    local n=1
    for option in "$@"
    do
        options+=("$n" "$option")
        n=$((n+1))
    done

    n=$(dialog --backtitle "$backtitle" --menu "$menu" "$h" "$w" "$#" "${options[@]}" 3>&1 1>&2 2>&3 3>&-)

    if [ -n "$n" ]; then
        echo "${options[(($n*2-1))]}"
    else
        echo ""
    fi
}

function menuBoxNn {
    local h=20
    local w=50

    if [ "$1" -gt "0" ]; then h=$1; fi
    if [ "$2" -gt "0" ]; then w=$2; fi

    local defaultItem="$3"
    local menu="$4"

    shift 4

    dialog --backtitle "$backtitle" --default-item "$defaultItem" --menu "$menu" "$h" "$w" "$(($#/2))" "$@" 3>&1 1>&2 2>&3 3>&-
}

function yesnoBox {
    local h=8
    local w=50

    if [ "$1" -gt "0" ]; then h=$1; fi
    if [ "$2" -gt "0" ]; then w=$2; fi

    local menu="$3"

    shift 3

    dialog --backtitle "$backtitle" --title "$menu" --yesno "$@" "$h" "$w" 3>&1 1>&2 2>&3 3>&-

    echo $?
}

function msgBox {
    local h=8
    local w=50

    if [ "$1" -gt "0" ]; then h=$1; fi
    if [ "$2" -gt "0" ]; then w=$2; fi

    local menu="$3"

    shift 3

    dialog --backtitle "$backtitle"  --title "$menu" --msgbox "$@" "$h" "$w"
}

function inputBox {
    local h=8
    local w=50

    if [ "$1" -gt "0" ]; then h=$1; fi
    if [ "$2" -gt "0" ]; then w=$2; fi

    local menu="$3"

    shift 3

    dialog --backtitle "$backtitle" --inputbox "$menu" "$h" "$w" 3>&1 1>&2 2>&3 3>&-
}

function checklistBox {
    local h=20
    local w=50

    if [ "$1" -gt "0" ]; then h=$1; fi
    if [ "$2" -gt "0" ]; then w=$2; fi

    local menu="$3"

    shift 3

    selected=$(dialog --backtitle "$backtitle" --checklist "$menu" "$h" "$w" "$(($#/3))" "$@" 3>&1 1>&2 2>&3 3>&-)

    if [ -n "$selected" ]; then
        echo "$selected"
    else
        echo ""
    fi
}

function checklistBoxN {
    local h=20
    local w=50

    if [ "$1" -gt "0" ]; then h=$1; fi
    if [ "$2" -gt "0" ]; then w=$2; fi

    local menu="$3"

    shift 3

    local options=()
    local n=1
    for i in $(seq 1 2 "$#")
    do
        options+=("$n" "$1" "$2")
        n=$((n+1))
        shift 2
    done

    selected=$(dialog --backtitle "$backtitle" --checklist "$menu" "$h" "$w" "$(($#/2))" "${options[@]}" 3>&1 1>&2 2>&3 3>&-)

    local result=()
    if [ -n "$selected" ]; then
        for i in $selected; do
            result+=("${options[(($i*3-2))]}")
        done
    fi
    echo "${result[@]}"
}

######################################## INSTALLER STEP FUNCTIONS ########################################

setupNetwork() (
    set -e

    reset
    clear

    if ping archlinux.org -c 3 2> /dev/null; then
        return 0
    fi

    if [ "$(iw dev | wc -l)" -gt "0" ]; then
        wifi-menu
    else
        eval_gettext "Looks like you don't have Internet access and cannot find any WiFi interface"

        eval_gettext "Restarting dhcpcd..."
        systemctl restart dhcpcd
        sleep 5

        if ping archlinux.org -c 3 2> /dev/null; then
            return 0
        fi

        msgBox 10 50 "$(eval_gettext "ERROR")" "$(eval_gettext "Looks like you still don't have Internet access\nEnsure that you are connected and repeat this step or use the terminal")"
        return 1
    fi
)

mountFormatPartition() (
    set -e

    backtitle="$(printf "$(eval_gettext "Partitions - Mount points and format (%s)")" "$IS_UEFI")"

    yesno=0
    cryptPartition=1
    partitionPath=""
    if [ "$1" != "/" ]; then
        if [ "$1" != "/boot" ] || [ "$IS_UEFI" == "legacy" ]; then
            yesno=$(yesnoBox 0 0 "$(printf "$(eval_gettext "Mount %s")" "$1")" "$(printf "$(eval_gettext "Do you want to specify a mount point for %s?")" "$1")")
        fi
    fi
    if [ "$yesno" == "0" ]; then
        partition=""
        while [ -z "$partition" ]; do
            mapfile -t partitions < <(lsblk -l | grep part | awk '{printf "%s\n%s\n",$1,$4}')
            partition=$(menuBox 15 50 "$(printf "$(eval_gettext "Select the partition you want to be mounted as %s")" "$1")" "${partitions[@]}")
        done
        if [ -n "$partition" ]; then
            partitionPath="/dev/$partition"
            map="cryptroot${1/\//}"
            yesno=$(yesnoBox 0 0 "$(eval_gettext "Format")" "$(printf "$(eval_gettext "Do you want to format %s (%s)?")" "$partition" "$1")")
            if [ "$yesno" == "0" ]; then
                format=""
                if [ "$IS_UEFI" == "uefi" ] && [ "$1" == "/boot" ]; then
                    format="fat -F32"
                else
                    if [ "$1" != "/boot" ]; then
                        cryptPartition=$(yesnoBox 0 0 "$(eval_gettext "Encrypt")" "$(printf "$(eval_gettext "Do you want to encrypt %s (%s)?")" "$partition" "$1")")
                        if [ "$cryptPartition" == "0" ]; then
                            if [ "$1" == "/" ]; then
                                cryptsetup -y -v luksFormat "$partitionPath"
                                cryptsetup open "$partitionPath" "$map"
                            else
                                dd bs=512 count=4 if=/dev/urandom "of=$map.keyfile" iflag=fullblock
                                cryptsetup -y -v luksFormat "$partitionPath" "$map.keyfile"
                                cryptsetup --key-file "$map.keyfile" open "$partitionPath" "$map"
                            fi
                            partitionPath="/dev/mapper/$map"
                        fi
                    fi
                    mapfile -t avalFormats < <(find /bin/mkfs.* | cut -d "." -f2)
                    format=$(menuBoxN 15 50 "$(printf "$(eval_gettext "Select the file system you want for %s")" "$partition")" "${avalFormats[@]}")
                fi
                if [ -n "$format" ]; then
                    yesno=$(yesnoBox 0 0 "$(eval_gettext "WARNING!")" "$(printf "$(eval_gettext "Are you sure that you want to format %s (%s) as %s?\nALL DATA WILL BE LOST!")" "$partition" "$1" "$format")")
                    if [ "$yesno" == "0" ]; then
                        reset
                        # shellcheck disable=SC2086
                        mkfs.$format "$partitionPath"
                    fi
                fi
            else
                if [ "$(blkid "$partitionPath" | grep -c "crypto_LUKS")" != "0" ]; then
                    reset
                    if [ "$1" == "/" ]; then
                        cryptsetup open "$partitionPath" "$map"
                    else
                        cryptsetup --key-file "/mnt/etc/keyfiles/$map.keyfile" open "$partitionPath" "$map"
                    fi
                    partitionPath="/dev/mapper/$map"
                fi
            fi

            mkdir -p "/mnt$1"
            mount "$partitionPath" "/mnt$1"
        fi
    fi
)

createPartitions() (
    set -e

    backtitle="$(eval_gettext "Partitions - Creation")"

    continue=$(yesnoBox 0 0 "$(eval_gettext "Partitions")" "$(eval_gettext "Do you want to edit partitions of any disk?")")
    while [ "$continue" == "0" ]; do
        mapfile -t devices < <(lsblk -l | grep disk | awk '{printf "%s\n%s\n",$1,$4}')
        device=$(menuBox 10 50 "$(eval_gettext "Select the disk you want to partition:")" "${devices[@]}")
        if [ -n "$device" ]; then
            partitionProgram=$(menuBoxN 12 50 "$(printf "$(eval_gettext "Select the partition tool you want to use for partitioning %s:")" "$device")" "cfdisk" "parted" "cgdisk")
            if [ -n "$partitionProgram" ]; then
                reset
                $partitionProgram "/dev/$device"
            fi
        fi

        continue=$(yesnoBox 0 0 "$(eval_gettext "Partitions")" "$(eval_gettext "Do you want to edit partitions of any other disk?")")
    done
)

setupSwap() (
    set -e

    backtitle="$(eval_gettext "Partitions - SWAP")"

    yesno=$(yesnoBox 0 0 "$(eval_gettext "SWAP")" "$(eval_gettext "Do you want to use a partition as SWAP?")")
    if [ "$yesno" == "0" ]; then
        mapfile -t partitions < <(lsblk -l | grep part | awk '{printf "%s\n%s\n",$1,$4}')
        partition=$(menuBox 15 50 "$(eval_gettext "Select the partition you want to use as SWAP:")" "${partitions[@]}")
        if [ -n "$partition" ]; then
            yesno=$(yesnoBox 0 0 "$(eval_gettext "WARNING!")" "$(printf "$(eval_gettext "Are you sure that you want to format %s as SWAP?\nALL DATA WILL BE LOST!")" "$partition")")
            if [ "$yesno" == "0" ]; then
                reset
                mkswap "/dev/$partition"
                swapon "/dev/$partition"
            fi
        fi
    fi
)

installBaseSystem() (
    set -e

    backtitle="$(eval_gettext "Base system installation")"

    packages="base linux linux-firmware grub dialog"

    if [ "$IS_UEFI" == "uefi" ]; then
        packages="$packages efibootmgr"
    fi

    extraPkgs=$(checklistBoxN 0 0 "$(eval_gettext "Select packages you want to install:")" "base-devel" "on" "networkmanager" "on" "os-prober" "on" "openssh" "off" "curl" "off" "wget" "off" "vim" "off")
    userPkgs=$(inputBox 0 0 "$(eval_gettext "Specify any other packages you want to install (optional):")")
    packages="$packages $extraPkgs $userPkgs"

    yesno=$(yesnoBox 15 50 "$(eval_gettext "Summary")" "$(printf "$(eval_gettext "The following packages will be installed:\n\n%s\n\nDo you want to continue?")" "$packages")")
    reset
    if [ "$yesno" == "0" ]; then
        read -r -a packagesArr <<< "$packages"
        pacstrap /mnt "${packagesArr[@]}"
        genfstab -U -p /mnt >> /mnt/etc/fstab
        #Check if there are encrypted partitions
        if mount | grep -q "cryptroot"; then
            #Add "encrypt" hook if root partition is encrypted
            n=$(grep -n "^HOOKS=" < /mnt/etc/mkinitcpio.conf | cut -d ":" -f1)
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
                        uuid=$(lsblk -lf | grep "$partition" | awk '{print $3}')
                        sed -i "s/^GRUB_CMDLINE_LINUX=\"/GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$uuid:cryptroot root=\/dev\/mapper\/cryptroot/g" /mnt/etc/default/grub
                    else
                        mkdir -p /mnt/etc/keyfiles
                        cp "$map.keyfile" "/mnt/etc/keyfiles/$map.keyfile"
                        chmod 0400 "/mnt/etc/keyfiles/$map.keyfile"
                        echo "$map    /dev/$partition      /etc/keyfiles/$map.keyfile luks" >> /mnt/etc/crypttab
                    fi
                    partition=""
                fi
            done
        fi
    fi
)

setupKeyboard() (
    set -e

    backtitle="$(eval_gettext "Base system configuration - Keyboard")"

    mapfile -t keymaps < <(find /mnt/usr/share/kbd/keymaps/i386/qwerty | sed 's/.*\/\([^\/]*\)$/\1/g;s/\.map\.gz//g' | sort)
    keymap=$(menuBoxN 20 50 "$(eval_gettext "Select your keyboard distribution:")" "${keymaps[@]}")
    if [ -n "$keymap" ]; then
        echo "KEYMAP=$keymap" 2> /mnt/etc/vconsole.conf
    fi
)

setupHostname() (
    set -e

    backtitle="$(eval_gettext "Base system configuration - Hostname")"

    hostname=$(inputBox 0 0 "$(eval_gettext "Type your host name")")

    echo "$hostname" 2> /mnt/etc/hostname
)

setupTimezone() (
    set -e

    backtitle="$(eval_gettext "Base system configuration - Time zone")"

    zone=""
    continent=""
    while [ -z "$zone" ]; do
        mapfile -t continents < <(find /mnt/usr/share/zoneinfo/* -maxdepth 0 -type d | sed 's/.*\/\([^\/]*\)$/\1/g' | sort)
        continent=$(menuBoxN 15 50 "$(eval_gettext "Select your time zone continent")" "${continents[@]}")
        mapfile -t zones < <(find "/mnt/usr/share/zoneinfo/$continent/"* -maxdepth 0 -type f | sed 's/.*\/\([^\/]*\)$/\1/g' | sort)
        zone=$(menuBoxN 15 50 "$(eval_gettext "Select your time zone")" "${zones[@]}")
    done
    rm /mnt/etc/localtime || true
    ln -s "/mnt/usr/share/zoneinfo/$continent/$zone" /mnt/etc/localtime
)

setupLocalization() (
    set -e

    backtitle="$(eval_gettext "Base system configuration - Localization")"

    yesno="0"
    if [ -f /mnt/etc/locale.conf ]; then
        yesno=$(yesnoBox 0 0 "$(eval_gettext "Localization")" "$(eval_gettext "Do you want to change the localization?")")
    fi
    if [ "$yesno" == "0" ]; then
        locale=""
        while [ -z "$locale" ]; do
            mapfile -t locales < <(grep -e "^#[a-z]\{2,3\}_[A-Z]\{2\}.*" < /mnt/etc/locale.gen | tr -d "#" | awk '{printf "%s\n%s\n",$1,$2}')
            locale=$(menuBox 15 50 "$(eval_gettext "Select your localization")" "${locales[@]}")
        done

        echo "LANG=$locale" 2> /mnt/etc/locale.conf
        sed -i "s/^#$locale/$locale/g" /mnt/etc/locale.gen
        arch-chroot /mnt locale-gen
    fi
)

installBootloader() (
    set -e

    backtitle="$(printf "$(eval_gettext "Boot loader - GRUB (%s)")" "$IS_UEFI")"

    yesno=$(yesnoBox 0 0 "$(eval_gettext "Boot loader")" "$(eval_gettext "Do you want to install GRUB boot loader?")")
    if [ "$yesno" == "0" ]; then
        if [ "$IS_UEFI" == "uefi" ]; then
            reset
            arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=arch_grub --recheck
            arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
            arch-chroot /mnt mkinitcpio -p linux
            #UEFI firmware workaround - https://wiki.archlinux.org/index.php/GRUB#UEFI_firmware_workaround
            mkdir /mnt/boot/EFI/boot
            cp /mnt/boot/EFI/arch_grub/grubx64.efi /mnt/boot/EFI/boot/bootx64.efi
        else
            mapfile -t devices < <(lsblk -l | grep disk | awk '{printf "%s\n%s\n",$1,$4}')
            device=$(menuBox 10 50 "$(eval_gettext "Select the disk where you want to install GRUB boot loader")" "${devices[@]}")
            if [ -n "$device" ]; then
                reset
                arch-chroot /mnt grub-install "/dev/$device"
                arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
                arch-chroot /mnt mkinitcpio -p linux
            fi
        fi
    fi
)

setupRootPassword() (
    set -e

    backtitle="$(eval_gettext "Security")"

    msgBox 10 50 "$(eval_gettext "Root password")" "$(eval_gettext "You will be asked for root password.")"

    reset

    arch-chroot /mnt passwd
)

installXdgUserDirs() {
    set -e

    reset
    arch-chroot /mnt pacman --noconfirm -Syu
    arch-chroot /mnt pacman --noconfirm -S xdg-user-dirs
}

setupUsers() {
    set -e

    backtitle="$(eval_gettext "Users")"

    yesno=$(yesnoBox 0 0 "$(eval_gettext "New user")" "$(eval_gettext "Do you want to create a new user?")")
    if [ "$yesno" == "0" ]; then
        username=$(inputBox 0 0 "$(eval_gettext "Type name for the new user")")
        if [ -n "$username" ]; then
            arch-chroot /mnt useradd -m -g users -G audio,lp,optical,storage,video,wheel,games,power,scanner -s /bin/bash "$username"
            reset
            arch-chroot /mnt passwd "$username"
        fi
    fi

    n=$(grep -n -m1 "^# %wheel ALL=(ALL) ALL" /mnt/etc/sudoers | cut -d ":" -f1)
    if [ -n "$n" ]; then
        yesno=$(yesnoBox 0 0 "$(eval_gettext "Enable sudo")" "$(eval_gettext "Do you want to enable wheel group on sudoers?")")
        if [ "$yesno" == "0" ]; then
            sed -i "${n}s/^#//g" /mnt/etc/sudoers
        fi
    fi
}

installX11() {
    set -e

    backtitle="$(eval_gettext "X11 graphical server")"

    yesno=$(yesnoBox 0 0 "X11" "$(eval_gettext "Do you want to install X11 graphical server?")")
    if [ "$yesno" == "0" ]; then
        reset
        arch-chroot /mnt pacman --noconfirm -S xorg-server xorg-xinit mesa mesa-demos

        videoCard=$(menuBoxN 15 50 "$(eval_gettext "Select your graphics card manufacturer")" "intel" "nvidia" "nvidia_nouveau" "optimus_bumblebee" "ati" "vesa" "virtualbox" "nvidia-340xx_legacy" "nvidia-304xx_legacy" "optimus_bumblebee_340xx_legacy" "optimus_bumblebee_304xx_legacy" "$(eval_gettext "None")")
        reset

        case "$videoCard" in
        intel)
            # Nothing to do
            ;;
        nvidia)
            arch-chroot /mnt pacman --noconfirm -S nvidia nvidia-utils
            ;;
        nvidia_nouveau)
            arch-chroot /mnt pacman --noconfirm -S xf86-video-nouveau
            ;;
        optimus_bumblebee)
            arch-chroot /mnt pacman --noconfirm -S nvidia nvidia-utils bumblebee primus xf86-video-intel mesa
            arch-chroot /mnt systemctl enable bumblebeed.service
            ;;
        ati)
            arch-chroot /mnt pacman --noconfirm -S xf86-video-ati
            ;;
        vesa)
            arch-chroot /mnt pacman --noconfirm -S xf86-video-vesa
            ;;
        virtualbox)
            arch-chroot /mnt pacman --noconfirm -S virtualbox-guest-utils
            arch-chroot /mnt systemctl start vboxservice
            arch-chroot /mnt systemctl enable vboxservice
            ;;
        nvidia-340xx_legacy)
            arch-chroot /mnt pacman --noconfirm -S nvidia-340xx nvidia-340xx-utils
            ;;
        nvidia-304xx_legacy)
            arch-chroot /mnt pacman --noconfirm -S nvidia-304xx nvidia-304xx-utils
            ;;
        optimus_bumblebee_340xx_legacy)
            arch-chroot /mnt pacman --noconfirm -S nvidia-340xx nvidia-340xx-utils bumblebee primus xf86-video-intel mesa
            arch-chroot /mnt systemctl enable bumblebeed.service
            ;;
        optimus_bumblebee_304xx_legacy)
            arch-chroot /mnt pacman --noconfirm -S nvidia-304xx nvidia-304xx-utils bumblebee primus xf86-video-intel mesa
            arch-chroot /mnt systemctl enable bumblebeed.service
            ;;
        *)
            ;;
        esac

        arch-chroot /mnt pacman --noconfirm -S xorg-twm xorg-xclock xterm
    fi
}

setupX11Keyboard() {
    set -e

    backtitle="$(eval_gettext "X11 keyboard")"

    #Hay que mejorar esto para que soporte varios idiomas
    yesno=$(yesnoBox 0 0 "$(eval_gettext "Keyboard")" "$(eval_gettext "Do you want to set keyboard distribution for X11 to 'es'?")")
    if [ "$yesno" == "0" ]; then
        reset
        cp 10-keyboard.conf -O /mnt/etc/X11/xorg.conf.d/
    fi
}

enableRepo() {
    set -e

    backtitle="$(eval_gettext "Repositories")"

    n=$(grep -n -m1 "^#\[$1\]" /mnt/etc/pacman.conf | cut -d ":" -f1)
    if [ -n "$n" ]; then
        yesno=$(yesnoBox 0 0 "$1" "$(printf "$(eval_gettext "Do you want to enable %s repository?")" "$1")")
        if [ "$yesno" == "0" ]; then
            sed -i "${n}s/^#//g" /mnt/etc/pacman.conf
            ((n++))
            sed -i "${n}s/^#//g" /mnt/etc/pacman.conf
            reset
            arch-chroot /mnt pacman --noconfirm -Sy
        fi
    fi
}

setupRepositories() {
    set -e

    enableRepo "multilib"
    enableRepo "community"

    yesno=$(yesnoBox 0 0 "Pacman" "$(eval_gettext "Do you want to enable pacman colors?")")
    if [ "$yesno" == "0" ]; then
        sed -i '/^#Color/s/^#//' /mnt/etc/pacman.conf
    fi
}

installSound() {
    set -e

    backtitle="$(eval_gettext "Sound")"

    yesno=$(yesnoBox 0 0 "Pulseaudio" "$(eval_gettext "Do you want to install Pulseaudio?")")
    if [ "$yesno" == "0" ]; then
        reset
        arch-chroot /mnt pacman --noconfirm -S pulseaudio pulseaudio-alsa
    fi
}

installFonts() {
    set -e

    backtitle="$(eval_gettext "Fonts")"

    yesno=$(yesnoBox 0 0 "$(eval_gettext "Fonts")" "$(eval_gettext "Do you want tu install recomended fonts?")")
    if [ "$yesno" == "0" ]; then
        reset
        arch-chroot /mnt pacman --noconfirm -S ttf-liberation ttf-bitstream-vera ttf-dejavu ttf-droid ttf-freefont
    fi
}

installDesktop() {
    set -e

    backtitle="$(eval_gettext "Desktop")"

    yesno=$(yesnoBox 0 0 "$(eval_gettext "Desktop")" "$(eval_gettext "Do you want to install a desktop enviroment?")")
    if [ "$yesno" == "0" ]; then

        desktop=$(menuBoxN 15 50 "$(eval_gettext "Select your favorite desktop")" "gnome" "kde" "lxde" "xfce" "lxqt" "cinnamon" "openbox")
        reset

        case "$desktop" in
        gnome)
            arch-chroot /mnt pacman --noconfirm -S gnome gnome-extra gnome-tweak-tool
            ;;
        kde)
            arch-chroot /mnt pacman --noconfirm -S plasma
            ;;
        lxde)
            arch-chroot /mnt pacman --noconfirm -S lxde
            ;;
        xfce)
            arch-chroot /mnt pacman --noconfirm -S xfce4 xfce4-goodies network-manager-applet
            ;;
        lxqt)
            arch-chroot /mnt pacman --noconfirm -S lxqt
            ;;
        cinnamon)
            arch-chroot /mnt pacman --noconfirm -S cinnamon
            ;;
        openbox)
            arch-chroot /mnt pacman --noconfirm -S openbox
            ;;
        *)
            ;;
        esac

        reset
        sessionManager=$(menuBoxN 15 50 "$(eval_gettext "Select your favorite session manager")" "sddm" "gdm")
        reset

        case "$sessionManager" in
        gdm)
            arch-chroot /mnt pacman --noconfirm -S gdm
            arch-chroot /mnt systemctl disable sddm
            arch-chroot /mnt systemctl enable gdm.service
            ;;
        sddm)
            arch-chroot /mnt pacman --noconfirm -S sddm sddm-kcm
            arch-chroot /mnt systemctl disable gdm.service
            arch-chroot /mnt systemctl enable sddm
            ;;
        *)
            ;;
        esac
    fi
}

umountDisks() {
    umount -R /mnt
    #Close all encrypted partitions
    for partition in $(lsblk -l | grep crypt | awk '{print $1}'); do
        cryptsetup close "$partition"
    done
}

finishInstallation() (
    set -e

    yesno=$(yesnoBox 10 50 "$(eval_gettext "Installation finished")" "$(eval_gettext "Base system installation is finised. If everthing went fine, after reboot, you will be able to start your brand new system.\n\nDo you want to unmount disks and reboot?")")
    reset
    if [ "$yesno" == "0" ]; then
        umountDisks
        reboot
    fi
)

onStepError() {
    if [ "$1" != "quiet" ]; then
        echo
        echo "$(eval_gettext "Error:") $(eval_gettext "An unexpected error has occurred")"
        read -n 1 -s -r -p "$(eval_gettext "Press any key to continue")"
    fi
    step=$((step * -1))
}

################################################## MAIN ##################################################

backtitle="$(printf "$(eval_gettext "ArchLinux instalation script %s")" "v$version")"

msgBox 10 50 "$(eval_gettext "Welcome")" "$(eval_gettext "This script works as a guide during Arch Linux installation process. You will be able to cancel it at any time by just pressing Ctrl+C")"

step=1

if [ "$1" == "menu" ] || [ "$2" == "menu" ]; then
    step=-1
fi

while true; do
    if [ "$step" -le "0" ]; then
        step="$(menuBoxNn 15 50 "$((step*-1))" "$(eval_gettext "Select installation step:")" \
        1  "$(eval_gettext "Network setup")"            \
        2  "$(eval_gettext "Manage partitions")"        \
        3  "$(eval_gettext "Mount partitions")"         \
        4  "$(eval_gettext "Setup swap")"               \
        5  "$(eval_gettext "Install base system")"      \
        6  "$(eval_gettext "Setup keyboard")"           \
        7  "$(eval_gettext "Setup hostname")"           \
        8  "$(eval_gettext "Setup time zone")"          \
        9  "$(eval_gettext "Setup localization")"       \
        10 "$(eval_gettext "Setup root password")"      \
        11 "$(eval_gettext "Install xdg-user-dirs")"    \
        12 "$(eval_gettext "Setup users")"              \
        13 "$(eval_gettext "Install X11 server")"       \
        14 "$(eval_gettext "Setup X11 keyboard")"       \
        15 "$(eval_gettext "Setup repositories")"       \
        16 "$(eval_gettext "Install sound system")"     \
        17 "$(eval_gettext "Install recomended fonts")" \
        18 "$(eval_gettext "Install desktop")"          \
        19 "$(eval_gettext "Install bootloader")"       \
        20 "$(eval_gettext "Finish installation")"      \
        21 "$(eval_gettext "Open terminal")"            \
        99 "$(eval_gettext "Exit")"                     \
        )"
    fi

    errorCmd=""

    case "$step" in
        1)
            errorCmd="quiet"
            setupNetwork
            ;;
        2)
            createPartitions
            ;;
        3)
            if ! mountFormatPartition "/"; then
                onStepError
                continue
            fi

            if ! mountFormatPartition "/boot"; then
                onStepError
                continue
            fi

            if ! mountFormatPartition "/home"; then
                onStepError
                continue
            fi

            ;;
        4)
            setupSwap
            ;;
        5)
            installBaseSystem
            ;;
        6)
            setupKeyboard
            ;;
        7)
            setupHostname
            ;;
        8)
            setupTimezone
            ;;
        9)
            setupLocalization
            ;;
        10)
            setupRootPassword
            ;;
        11)
            installXdgUserDirs
            ;;
        12)
            setupUsers
            ;;
        13)
            installX11
            ;;
        14)
            setupX11Keyboard
            ;;
        15)
            setupRepositories
            ;;
        16)
            installSound
            ;;
        17)
            installFonts
            ;;
        18)
            installDesktop
            ;;
        19)
            installBootloader
            ;;
        20)
            finishInstallation
            ;;
        21)
            errorCmd="quiet"
            eval_gettext "Type 'exit' to return to menu:"
            bash && step=$((step * -1))
            ;;
        *)
            step=0
            umountDisks
            exit 1
            ;;
    esac

    # shellcheck disable=SC2181
    if [ "$?" == "0" ]; then
        if [ "$step" == "20" ]; then
            exit 0
        elif [ "$step" -lt "21" ]; then
            step=$((step+1))
        fi
    else
        onStepError "$errorCmd"
    fi
done

exit 1
