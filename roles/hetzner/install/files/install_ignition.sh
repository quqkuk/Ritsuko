#!/usr/bin/bash
# Modified from https://github.com/kube-hetzner/kube-hetzner/blob/master/locals.tf

# Quit on Error / Show every line before execution
set -ex

# Download image and write it to disk
curl -sL 'https://download.opensuse.org/distribution/leap-micro-current/appliances/openSUSE-Leap-Micro.x86_64-Default.raw.xz' | \
	xz --decompress > "$1"

# Move GPT trailer to end of disk
sfdisk --relocate gpt-bak-std "$1"

# Update partition table
partprobe "$1" && udevadm settle

#Create swap and ignition config partitions
PARTED_OUTPUT=$(parted -s "$1" unit MiB print)
DISK_END=$(printf "$PARTED_OUTPUT" | grep "Disk $1" | cut -d ' ' -f3 | tr -d 'MiB')
DISK_LAST_PARTITION_NUMBER=$(printf "$PARTED_OUTPUT" | tail -n1 | cut -d ' ' -f2)
SWAP_PARTITION_NUMBER=$((DISK_LAST_PARTITION_NUMBER+1))
SWAP_START=$((DISK_END-2*1024))
CONFIG_END=$((DISK_END-512))
parted -s "$1" mkpart primary linux-swap "${SWAP_START}MiB" "${CONFIG_END}MiB"
parted -s "$1" mkpart primary ext4 "${CONFIG_END}MiB" 100%
partprobe "$1" && udevadm settle

mkswap "${1}${SWAP_PARTITION_NUMBER}"
