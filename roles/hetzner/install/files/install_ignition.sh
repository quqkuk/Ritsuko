#!/usr/bin/bash
# Modified from https://github.com/kube-hetzner/kube-hetzner/blob/master/locals.tf

# Quit on Error / Show every line before execution
set -ex

# Download image and write it to disk
TMPIMG=$(mktemp --suffix=".qcow2")
curl -sL https://mirrorcache.opensuse.org/tumbleweed/appliances/openSUSE-MicroOS.x86_64-ContainerHost-kvm-and-xen.qcow2 > "$TMPIMG"
qemu-img convert -f qcow2 -O host_device "$TMPIMG" "$1"
rm "$TMPIMG"

# Move GPT trailer to end of disk
sgdisk -e "$1"

# Find Root Partition
PARTED_OUTPUT=$(parted -s "$1" unit MiB print)
ROOT_PARTITION=$(printf "$PARTED_OUTPUT" | grep 'p.lxroot' | tr -s ' ')
ROOT_PART_NUMBER=$(printf "$ROOT_PARTITION" | cut -d ' ' -f 2)
SHRINK_FACTOR_MiB=$((2*1024))

# Shrink btrfs filesystem
mount "$1$ROOT_PART_NUMBER" /mnt
btrfs filesystem resize --enqueue "-${SHRINK_FACTOR_MiB}M" /mnt
umount /mnt

# Shrink partition
ROOT_PART_END=$(printf "$ROOT_PARTITION" | cut -d ' ' -f 4  | tr -d 'MiB')
ROOT_PART_NEW_END="$((ROOT_PART_END - SHRINK_FACTOR_MiB))"
parted "$1" ---pretend-input-tty resizepart "$ROOT_PART_NUMBER" "${ROOT_PART_NEW_END}MiB" <<< "Yes"

#TODO: This script is dependant on the disk being 20GB, that might not be true
#      but as of right now it's a safe assumption as we don't deploy on larger disks
#Move var/spare partition and create swap and ignition config partitions
printf "%iM\n" "-${SHRINK_FACTOR_MiB}" | sfdisk --move-data "$1" -N "$(printf "$PARTED_OUTPUT" | grep 'p.spare' | tr -s ' ' | cut -d ' ' -f 2)"
partprobe "$1" && udevadm settle

#Create swap and ignition config partitions
PARTED_OUTPUT=$(parted -s "$1" unit MiB print)
LAST_PART_END=$(printf "$PARTED_OUTPUT" | tail -n1 | tr -s ' ' | cut -d ' ' -f4 | tr -d 'MiB')
DISK_END=$(printf "$PARTED_OUTPUT" | grep "Disk $1" | cut -d ' ' -f3 | tr -d 'MiB')
SWAP_END=$((DISK_END-512))
parted -s "$1" mkpart primary linux-swap "${LAST_PART_END}MiB" "${SWAP_END}MiB"
parted -s "$1" mkpart primary ext4 "${SWAP_END}MiB" 100%
partprobe "$1" && udevadm settle

#TODO: We can rely on this being the 5th partition, but we shouldn't
mkswap "${1}5"
