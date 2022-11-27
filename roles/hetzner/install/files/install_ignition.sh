#!/usr/bin/bash
# Modified from https://github.com/kube-hetzner/kube-hetzner/blob/master/locals.tf

# Quit on Error / Show every line before execution
set -ex

# Download image and write it to disk
#TMPIMG=$(mktemp --suffix=".qcow2")
#curl -sL https://mirrorcache.opensuse.org/tumbleweed/appliances/openSUSE-MicroOS.x86_64-ContainerHost-kvm-and-xen.qcow2 > "$TMPIMG"
#qemu-img convert -f qcow2 -O host_device "$TMPIMG" "$1"
#rm "$TMPIMG"
curl -sL 'https://download.opensuse.org/distribution/leap-micro/5.3/appliances/openSUSE-Leap-Micro.x86_64-Default.raw.xz' | \
	xz --decompress > "$1"

# Move GPT trailer to end of disk
sfdisk --relocate gpt-bak-std "$1"

# Update partition table
partprobe "$1" && udevadm settle

#Create swap and ignition config partitions
PARTED_OUTPUT=$(parted -s "$1" unit MiB print)
DISK_END=$(printf "$PARTED_OUTPUT" | grep "Disk $1" | cut -d ' ' -f3 | tr -d 'MiB')
SWAP_START=$((DISK_END-2*1024))
SWAP_END=$((DISK_END-512))
parted -s "$1" mkpart primary linux-swap "${SWAP_START}MiB" "${SWAP_END}MiB"
parted -s "$1" mkpart primary ext4 "${SWAP_END}MiB" 100%
partprobe "$1" && udevadm settle

#TODO: We can rely on this being the 4th partition for now, but we probably shouldn't
mkswap "${1}4"
