#! /bin/bash
# shellcheck disable=SC2059
# shellcheck disable=SC1090
# shellcheck disable=SC1091

set -e

. gettext.sh

# shellcheck disable=SC2034
TEXTDOMAIN=install

source "$( cd "$( dirname "$0" )" && pwd )/utils.sh"

uefi="legacy"
if [ -e /sys/firmware/efi ]; then
    uefi="uefi"
fi

function setupNetwork {
    reset
    clear

    if ping archlinux.org -c 3 2> /dev/null; then
        return 0
    fi

    if [ "$(iw dev | wc -l)" -gt "0" ]; then
        wifi-menu
    else
        echo "$(eval_gettext "Looks like you don't have Internet access and cannot find any WiFi interface")";
        
        echo "$(eval_gettext "Restarting dhcpcd...")";
        systemctl restart dhcpcd
        sleep 5
        
        if ping archlinux.org -c 3 2> /dev/null; then
            return 0
        fi
        
        msgBox 10 50 "$(eval_gettext "ERROR")" "$(eval_gettext "Looks like you still don't have Internet access\nEnsure that you are connected and repeat this step or use the terminal")"
        return 1
    fi
    
    # wget http://192.168.0.164:8000/utils.sh -O utils.sh
}

function mountFormatPartition {
    backtitle="$(printf "$(eval_gettext "Partitions - Mount points and format (%s)")" "$uefi")"

    yesno=0
    cryptPartition=1
    partitionPath=""
    if [ "$1" != "/" ]; then
        if [ "$1" != "/boot" ] || [ "$uefi" == "legacy" ]; then
            yesno=$(yesnoBox 0 0 "$(printf "$(eval_gettext "Mount %s")" "$1")" "$(printf "$(eval_gettext "Do you want to specify a mount point for %s?")" "$1")")
        fi
    fi
    if [ "$yesno" == "0" ]; then
        partition=""
        while [ -z $partition ]; do
            options=( $(lsblk -l | grep part | awk '{print $1,$4}') )
            partition=$(menuBox 15 50 "$(printf "$(eval_gettext "Select the partition you want to be mounted as %s")" "$1")" "${options[@]}")
        done
        if [ -n "$partition" ]; then
            partitionPath="/dev/$partition"
            map="cryptroot${1/\//}"
            yesno=$(yesnoBox 0 0 "$(eval_gettext "Format")" "$(printf "$(eval_gettext "Do you want to format %s (%s)?")" "$partition" "$1")")
            if [ "$yesno" == "0" ]; then
                format=""
                if [ "$uefi" == "uefi" ] && [ "$1" == "/boot" ]; then
                    format="fat -F32"
                else
                    if [ "$1" != "/boot" ]; then
                        cryptPartition=$(yesnoBox 0 0 "$(eval_gettext "Encrypt")" "$(printf "$(eval_gettext "Do you want to encrypt %s (%s)?")" "$partition" "$1")")
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
                    format=$(menuBoxN 15 50 "$(printf "$(eval_gettext "Select the file system you want for %s")" "$partition")" "$(ls /bin/mkfs.* | cut -d "." -f2)")
                fi
                if [ -n "$format" ]; then
                    yesno=$(yesnoBox 0 0 "$(eval_gettext "WARNING!")" "$(printf "$(eval_gettext "Are you sure that you want to format %s (%s) as %s?\nALL DATA WILL BE LOST!")" "$partition" "$1" "$format")")
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

function createPartitions {
    backtitle="$(eval_gettext "Partitions - Creation")"

    continue=$(yesnoBox 0 0 "$(eval_gettext "Partitions")" "$(eval_gettext "Do you want to edit partitions of any disk?")")
    while [ "$continue" == "0" ]; do
        device=$(menuBox 10 50 "$(eval_gettext "Select the disk you want to partition:")" $(lsblk -l | grep disk | awk '{print $1,$4}'))
        if [ -n "$device" ]; then
            partitionProgram=$(menuBoxN 12 50 "$(printf "$(eval_gettext "Select the partition tool you want to use for partitioning %s:")" "$device")" "cfdisk parted cgdisk")
            if [ -n "$partitionProgram" ]; then
                reset
                $partitionProgram /dev/$device
            fi
        fi

        continue=$(yesnoBox 0 0 "$(eval_gettext "Partitions")" "$(eval_gettext "Do you want to edit partitions of any other disk?")")
    done
}

function setupSwap {
    backtitle="$(eval_gettext "Partitions - SWAP")"

    yesno=$(yesnoBox 0 0 "$(eval_gettext "SWAP")" "$(eval_gettext "Do you want to use a partition as SWAP?")")
    if [ "$yesno" == "0" ]; then
        partition=$(menuBox 15 50 "$(eval_gettext "Select the partition you want to use as SWAP:")" $(lsblk -l | grep part | awk '{print $1,$4}'))
        if [ -n "$partition" ]; then
            yesno=$(yesnoBox 0 0 "$(eval_gettext "WARNING!")" "$(printf "$(eval_gettext "Are you sure that you want to format %s as SWAP?\nALL DATA WILL BE LOST!")" "$partition")")
            if [ "$yesno" == "0" ]; then
                reset
                mkswap /dev/$partition
                swapon /dev/$partition
            fi
        fi
    fi
}

function installBaseSystem {
    backtitle="$(eval_gettext "Base system installation")"

    packages="base linux linux-firmware grub dialog"

    if [ "$uefi" == "uefi" ]; then
        packages="$packages efibootmgr"
    fi

    extraPkgs=$(checklistBoxN 0 0 "$(eval_gettext "Select packages you want to install:")" "base-devel on networkmanager on os-prober on openssh off curl off wget off vim off")
    userPkgs=$(inputBox 0 0 "$(eval_gettext "Specify any other packages you want to install (optional):")")
    packages="$packages $extraPkgs $userPkgs"

    yesno=$(yesnoBox 15 50 "$(eval_gettext "Summary")" "$(printf "$(eval_gettext "The following packages will be installed:\n\n%s\n\nDo you want to continue?")" "$packages")")
    reset
    if [ "$yesno" == "0" ]; then
        pacstrap /mnt $packages
        genfstab -U -p /mnt >> /mnt/etc/fstab
        #Check if there are encrypted partitions
        if mount | grep -q "cryptroot"; then
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
}

function setupKeyboard {
    backtitle="$(eval_gettext "Base system configuration - Keyboard")"

    keymap=$(menuBoxN 20 50 "$(eval_gettext "Select your keyboard distribution:")" "$(ls /mnt/usr/share/kbd/keymaps/i386/qwerty | cut -d "." -f1)")
    if [ -n "$keymap" ]; then
        echo "KEYMAP=$keymap" 2> /mnt/etc/vconsole.conf
    fi
}

function setupHostname {
    backtitle="$(eval_gettext "Base system configuration - Hostname")"

    hostname=$(inputBox 0 0 "$(eval_gettext "Type your host name")")

    echo $hostname 2> /mnt/etc/hostname
}

function setupTimezone {
    backtitle="$(eval_gettext "Base system configuration - Time zone")"

    zone=""
    continent=""
    while [ -z "$zone" ]; do
        continent=$(menuBoxN 15 50 "$(eval_gettext "Select your time zone continent")" "$(ls -l /mnt/usr/share/zoneinfo/ | grep -e "^d.*" | awk '{print $9}')")
        zone=$(menuBoxN 15 50 "$(eval_gettext "Select your time zone")" "$(ls -l /mnt/usr/share/zoneinfo/$continent | grep -e "^-.*" | awk '{print $9}')")
    done
    rm /mnt/etc/localtime | true
    ln -s /mnt/usr/share/zoneinfo/$continent/$zone /mnt/etc/localtime
}

function setupLocalization {
    backtitle="$(eval_gettext "Base system configuration - Localization")"

    yesno="0"
    if [ -f /mnt/etc/locale.conf ]; then
        yesno=$(yesnoBox 0 0 "$(eval_gettext "Localization")" "$(eval_gettext "Do you want to change the localization?")")
    fi
    if [ "$yesno" == "0" ]; then
        locale=""
        while [ -z "$locale" ]; do
            locale=$(menuBox 15 50 "$(eval_gettext "Select your localization")" $(cat /mnt/etc/locale.gen | grep -e "^#[a-z]\{2,3\}_[A-Z]\{2\}.*" | tr -d "#" | awk '{print $1,$2}'))
        done

        echo "LANG=$locale" 2> /mnt/etc/locale.conf
        sed -i "s/^#$locale/$locale/g" /mnt/etc/locale.gen
        arch-chroot /mnt locale-gen
    fi
}

function installBootloader {
    backtitle="$(printf "$(eval_gettext "Boot loader - GRUB (%s)")" "$uefi")"

    yesno=$(yesnoBox 0 0 "$(eval_gettext "Boot loader")" "$(eval_gettext "Do you want to install GRUB boot loader?")")
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
            device=$(menuBox 10 50 "$(eval_gettext "Select the disk where you want to install GRUB boot loader")" $(lsblk -l | grep disk | awk '{print $1,$4}'))
            if [ -n "$device" ]; then
                reset
                arch-chroot /mnt grub-install /dev/$device
                arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
                arch-chroot /mnt mkinitcpio -p linux
            fi
        fi
    fi
}

function setupRootPassword {
    backtitle="$(eval_gettext "Security")"

    msgBox 10 50 "$(eval_gettext "Root password")" "$(eval_gettext "You will be asked for root password.")"

    reset

    arch-chroot /mnt passwd
}

function finishInstallation {
    wget https://github.com/erm2587/ArchLinuxInstaller/archive/master.tar.gz -O /mnt/opt/ArchLinuxInstaller.tar.gz
    tar -xzvf /mnt/opt/ArchLinuxInstaller.tar.gz -C /mnt/opt
    rm /mnt/opt/ArchLinuxInstaller.tar.gz
    mv /mnt/opt/ArchLinuxInstaller-master /mnt/opt/ArchLinuxInstaller
    reset

    yesno=$(yesnoBox 10 50 "$(eval_gettext "Installation finished")" "$(eval_gettext "Base system installation is finised. If everthing went fine, after reboot, you will be able to start your brand new system.\n\nDo you want to unmount disks and reboot?")")
    reset
    if [ "$yesno" == "0" ]; then
        umount -R /mnt
        #Close all encrypted partitions
        for partition in $(lsblk -l | grep crypt | awk '{print $1}'); do
            cryptsetup close $partition
        done
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

msgBox 10 50 "$(eval_gettext "Welcome")" "$(eval_gettext "This script works as a guide during Arch Linux installation process. You will be able to cancel it at any time by just pressing Ctrl+C")"

step=1

if [ "$1" == "menu" ]; then
    step=-1
fi

while [ true ]; do
    if [ "$step" -le "0" ]; then
        step="$(menuBoxNn 15 50 "$(($step*-1))" "$(eval_gettext "Select installation step:")" \
        1  "$(eval_gettext "Network setup")"       \
        2  "$(eval_gettext "Manage partitions")"   \
        3  "$(eval_gettext "Mount partitions")"    \
        4  "$(eval_gettext "Setup swap")"          \
        5  "$(eval_gettext "Install base system")" \
        6  "$(eval_gettext "Setup keyboard")"      \
        7  "$(eval_gettext "Setup hostname")"      \
        8  "$(eval_gettext "Setup time zone")"     \
        9  "$(eval_gettext "Setup localization")"  \
        10 "$(eval_gettext "Setup root password")" \
        11 "$(eval_gettext "Install bootloader")"  \
        12 "$(eval_gettext "Finish installation")" \
        14 "$(eval_gettext "Open terminal")"       \
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
            if createPartitions; then
                step=$(($step+1))
            else
                onStepError
                continue
            fi
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
            step=$(($step+1))
            ;;
        4)
            if setupSwap; then
                step=$(($step+1))
            else
                onStepError
                continue
            fi
            ;;
        5)
            if installBaseSystem; then
                step=$(($step+1))
            else
                onStepError
                continue
            fi
            ;;
        6)
            if setupKeyboard; then
                step=$(($step+1))
            else
                onStepError
                continue
            fi
            ;;
        7)
            if setupHostname; then
                step=$(($step+1))
            else
                onStepError
                continue
            fi
            ;;
        8)
            if setupTimezone; then
                step=$(($step+1))
            else
                onStepError
                continue
            fi
            ;;
        9)
            if setupLocalization; then
                step=$(($step+1))
            else
                onStepError
                continue
            fi
            ;;
        10)
            if setupRootPassword; then
                step=$(($step+1))
            else
                onStepError
                continue
            fi
            ;;
        11)
            if installBootloader; then
                step=$(($step+1))
            else
                onStepError
                continue
            fi
            ;;
        12)
            if finishInstallation; then
                step=$(($step+1))
            else
                onStepError
                continue
            fi
            ;;
        13)
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
