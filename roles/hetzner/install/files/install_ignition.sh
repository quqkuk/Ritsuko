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

# Gather disk data
PARTED_OUTPUT=$(parted -s "$1" unit MB print | tail -n2 | head -n1 | tr -s ' ')
PART_NUMBER=$(printf "$PARTED_OUTPUT" | cut -d ' ' -f 2)

# Shrink filesystem
SHRINK_BY_MiB=512
mount "$1$PART_NUMBER" /mnt
btrfs filesystem resize --enqueue "-${SHRINK_BY_MiB}M" /mnt
umount /mnt

# Shrink partition
PART_END=$(printf "$PARTED_OUTPUT" | cut -d ' ' -f 4  | tr -d 'MB')
PART_NEW_END="$((PART_END - SHRINK_BY_MiB))MB"
parted "$1" ---pretend-input-tty resizepart "$PART_NUMBER" "$PART_NEW_END" <<< "Yes"
parted -s "$1" mkpart primary ext4 "$PART_NEW_END" 100%
partprobe "$1" && udevadm settle
