#! /bin/bash

set -e

TEXTDOMAIN=install

ping archlinux.org -c 3 2> /dev/null
if [ "$?" != "0" ]; then
    wifi-menu
fi

wget https://raw.githubusercontent.com/erm2587/ArchLinuxInstaller/master/utils.sh

source $( cd "$( dirname "$0" )" && pwd )/utils.sh


function mountFormatPartition {
    backtitle="$(printf $"Partitions - Mount points and format (%s)" "$uefi")"

    yesno=0
    cryptPartition=1
    partitionPath=""
    if [ "$1" != "/" ]; then
        if [ "$1" != "/boot" ] || [ "$uefi" == "legacy" ]; then
            yesno=$(yesnoBox 0 0 "$(printf $"Mount %s" "$1")" "$(printf $"Do you want to specify a mount point for %s?" "$1")")
        fi
    fi
    if [ "$yesno" == "0" ]; then
        partition=""
        while [ -z $partition ]; do
            partition=$(menuBox 15 50 "$(printf $"Select the partition you want to be mounted as %s" "$1")" $(lsblk -l | grep part | awk '{print $1,$4}'))
        done
        if [ -n "$partition" ]; then
            partitionPath="/dev/$partition"
            map="cryptroot${1/\//}"
            yesno=$(yesnoBox 0 0 $"Format" "$(printf $"Do you want to format %s (%s)?" "$partition" "$1")")
            if [ "$yesno" == "0" ]; then
                format=""
                if [ "$uefi" == "uefi" ] && [ "$1" == "/boot" ]; then
                    format="fat -F32"
                else
                    if [ "$1" != "/boot" ]; then
                        cryptPartition=$(yesnoBox 0 0 $"Encrypt" "$(printf $"Do you want to encrypt %s (%s)?" "$partition" "$1")")
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
                    format=$(menuBoxN 15 50 "$(printf $"Select the file system you want for %s" "$partition")" "$(ls /bin/mkfs.* | cut -d "." -f2)")
                fi
                if [ -n "$format" ]; then
                    yesno=$(yesnoBox 0 0 $"WARNING!" "$(printf $"Are you sure that you want to format %s (%s) as %s?\nALL DATA WILL BE LOST!" "$partition" "$1" "$format")")
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

backtitle="$(printf $"ArchLinux instalation script %s" "v$version")"

msgBox 10 50 $"Welcome" $"This script works as a guide during Arch Linux installation process. You will be able to cancel it at any time by just pressing Ctrl+C"

backtitle=$"Partitions - Creation"

continue=$(yesnoBox 0 0 $"Partitions" $"Do you want to edit partitions of any disk?")
while [ "$continue" == "0" ]; do
    device=$(menuBox 10 50 $"Select the disk you want to partition:" $(lsblk -l | grep disk | awk '{print $1,$4}'))
    if [ -n "$device" ]; then
        partitionProgram=$(menuBoxN 12 50 "$(printf $"Select the partition tool you want to use for partitioning %s:" "$device")" "cfdisk parted cgdisk")
        if [ -n "$partitionProgram" ]; then
            reset
            $partitionProgram /dev/$device
        fi
    fi

    continue=$(yesnoBox 0 0 $"Partitions" $"Do you want to edit partitions of any other disk?")
done

mountFormatPartition "/"
mountFormatPartition "/boot"
mountFormatPartition "/home"

backtitle=$"Partitions - SWAP"

yesno=$(yesnoBox 0 0 $"SWAP" $"Do you want to use a partition as SWAP?")
if [ "$yesno" == "0" ]; then
    partition=$(menuBox 15 50 $"Select the partition you want to use as SWAP:" $(lsblk -l | grep part | awk '{print $1,$4}'))
    if [ -n "$partition" ]; then
        yesno=$(yesnoBox 0 0 $"WARNING!" "$(printf $"Are you sure that you want to format %s as SWAP?\nALL DATA WILL BE LOST!" "$partition")")
        if [ "$yesno" == "0" ]; then
            reset
            mkswap /dev/$partition
            swapon /dev/$partition
        fi
    fi
fi

backtitle=$"Base system installation"

packages="base grub dialog"

if [ "$uefi" == "uefi" ]; then
    packages="$packages efibootmgr"
fi

extraPkgs=$(checklistBoxN 0 0 $"Select packages you want to install:" "base-devel on networkmanager on os-prober on openssh off curl off wget off vim off")
userPkgs=$(inputBox 0 0 $"Specify any other packages you want to install (optional):")
packages="$packages $extraPkgs $userPkgs"

yesno=$(yesnoBox 15 50 $"Summary" "$(printf $"The following packages will be installed:\n\n%s\n\nDo you want to continue?" "$packages")")
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

backtitle=$"Base system configuration - Keyboard"

keymap=$(menuBoxN 20 50 $"Select your keyboard distribution:" "$(ls /mnt/usr/share/kbd/keymaps/i386/qwerty | cut -d "." -f1)")
if [ -n "$keymap" ]; then
    echo "KEYMAP=$keymap" > /mnt/etc/vconsole.conf
fi

backtitle=$"Base system configuration - Hostname"

hostname=$(inputBox 0 0 $"Type your host name")

echo $hostname > /mnt/etc/hostname

backtitle=$"Base system configuration - Time zone"

zone=""
continent=""
while [ -z "$zone" ]; do
    continent=$(menuBoxN 15 50 $"Select your time zone continent" "$(ls -l /mnt/usr/share/zoneinfo/ | grep -e "^d.*" | awk '{print $9}')")
    zone=$(menuBoxN 15 50 $"Select your time zone" "$(ls -l /mnt/usr/share/zoneinfo/$continent | grep -e "^-.*" | awk '{print $9}')")
done
rm /mnt/etc/localtime | true
ln -s /mnt/usr/share/zoneinfo/$continent/$zone /mnt/etc/localtime

backtitle=$"Base system configuration - Localization"

yesno="0"
if [ -f /mnt/etc/locale.conf ]; then
    yesno=$(yesnoBox 0 0 $"Localization" $"Do you want to change the localization?")
fi
if [ "$yesno" == "0" ]; then
    locale=""
    while [ -z "$locale" ]; do
        locale=$(menuBox 15 50 $"Select your localization" $(cat /mnt/etc/locale.gen | grep -e "^#[a-z]\{2,3\}_[A-Z]\{2\}.*" | tr -d "#" | awk '{print $1,$2}'))
    done

    echo "LANG=$locale" > /mnt/etc/locale.conf
    sed -i "s/^#$locale/$locale/g" /mnt/etc/locale.gen
    arch-chroot /mnt locale-gen
fi

backtitle="$(printf $"Boot loader - GRUB (%s)" "$uefi")"

yesno=$(yesnoBox 0 0 $"Localization" $"Do you want to install GRUB boot loader?")
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
        device=$(menuBox 10 50 $"Select the disk where you want to install GRUB boot loader" $(lsblk -l | grep disk | awk '{print $1,$4}'))
        if [ -n "$device" ]; then
            reset
            arch-chroot /mnt grub-install /dev/$device
            arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
            arch-chroot /mnt mkinitcpio -p linux
        fi
    fi
fi

backtitle=$"Security"

msgBox 10 50 $"Root password" $"You will be asked for root password."

reset

arch-chroot /mnt passwd

wget https://github.com/erm2587/ArchLinuxInstaller/archive/master.tar.gz -O /mnt/opt/ArchLinuxInstaller.tar.gz
tar -xzvf /mnt/opt/ArchLinuxInstaller.tar.gz -C /mnt/opt
rm /mnt/opt/ArchLinuxInstaller.tar.gz
mv /mnt/opt/ArchLinuxInstaller-master /mnt/opt/ArchLinuxInstaller
reset

yesno=$(yesnoBox 10 50 $"Installation finished" $"Base system installation is finised. If everthing went fine, after reboot, you will be able to start your brand new system.\n\nDo you want to unmount disks and reboot?")
reset
if [ "$yesno" == "0" ]; then
    umount -R /mnt
    #Close all encrypted partitions
    for partition in $(lsblk -l | grep crypt | awk '{print $1}'); do
        cryptsetup close $partition
    done
    reboot
fi
