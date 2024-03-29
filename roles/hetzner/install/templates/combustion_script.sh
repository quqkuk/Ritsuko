#!/bin/bash
# combustion: network
# Network is needed to install packages

set -ex

#-------- Timezone
rm /etc/localtime || true
ln -s /usr/share/zoneinfo/Europe/Rome /etc/localtime

#-------- Partitions

# Removing Config partition, Growing SWAP until end of the disk, Growing data partition to fill the empty space
DISK_PATH='{{ ('/dev/', hetzner_install_installation_drive) | path_join }}'
PARTED_OUTPUT=$(parted -s "$DISK_PATH" unit MiB print)
CONFIG_PART_NUMBER=$(printf "$PARTED_OUTPUT" | tail -n 1 | cut -d ' ' -f2)
SWAP_PART=$(printf "$PARTED_OUTPUT" | tail -n 2 | head -n 1)
SWAP_PART_NUMBER=$(printf "$SWAP_PART" | cut -d ' ' -f2)
DATA_PART_NUMBER=$(printf "$PARTED_OUTPUT" | tail -n 3 | head -n 1 | cut -d ' ' -f2)
DATA_PART_END=$(($(printf "$SWAP_PART" | tr -s ' ' | cut -d ' ' -f 3 | tr -d 'MiB')-1))
#TODO: Use sfdisk/sgdisk
parted -s "$DISK_PATH" rm "$CONFIG_PART_NUMBER" || true
parted -s "$DISK_PATH" resizepart "$SWAP_PART_NUMBER" 100% || true
parted -s "$DISK_PATH" resizepart "$DATA_PART_NUMBER" "${DATA_PART_END}MiB" || true
#TODO: Resize btrfs filesystem
btrfs filesystem resize max /
partprobe "$DISK_PATH" && udevadm settle

# Adding swap to fstab
#TODO: Filter by disk before looking for the swap partition
printf "UUID=$(blkid | grep 'TYPE="swap"' | sed 's/.* UUID="\([a-zA-Z0-9-]*\)".*/\1/') none swap defaults 0 0" >> /etc/fstab

#-------- User/Authentication
# Mount home subvolume
mount -o subvol=/@/home /dev/disk/by-partlabel/p.lxroot /home

# Install docker
zypper --non-interactive install docker

# Create User
useradd --create-home -G docker {{ hetzner_install_ansible_user }}
SSH_FOLDER="{{ ("/home/", hetzner_install_ansible_user, ".ssh") | path_join }}"
mkdir -pm700 "$SSH_FOLDER"
cat > "{{ ("/home/", hetzner_install_ansible_user, ".ssh", "authorized_keys") | path_join }}" <<EOF
{{ lookup('ansible.builtin.file', ansible_ssh_private_key_file+'.pub') }}
EOF
chown -R --reference="{{ ("/home/", hetzner_install_ansible_user) | path_join }}" "$SSH_FOLDER"

#-------- firewall
zypper --non-interactive install firewalld python3-firewall
#systemctl enable firewalld.service
#firewall-cmd --permanent --add-port=69

#-------- SELinux
# Add port to selinux
semanage port --add -t ssh_port_t -p tcp {{ hetzner_install_ansible_port }}
# Installing selinux policy to snapshot /var[/container-volumes]
#Assuming current working directory contains /combustion
#TODO: Currently this fails with 'child process /usr/lib/selinux/hll/pp failed with code: 255. (No such file or directory)'
semodule -i ./snapperd_snapshot_var.pp

#-------- Sudoers + SSHd + Logrotate

cat > /etc/sudoers.d/90-allow-user-nopasswd <<-EOF
	# Allow passwordless sudo to template_user
	{{ hetzner_install_ansible_user }} ALL=(ALL:ALL) NOPASSWD: ALL
EOF

echo 'Include /etc/ssh/sshd_config.d/*' >> /etc/ssh/sshd_config
mkdir /etc/ssh/sshd_config.d || true

cat > /etc/ssh/sshd_config.d/40-prohibit-root-login.conf <<-EOF
	# Prohibiting login as root
	PermitRootLogin no
EOF

cat > /etc/ssh/sshd_config.d/40-disable-password-authentication.conf <<-EOF
	# Disable Password and Challenge Authentication
	PasswordAuthentication no
	ChallengeResponseAuthentication no
EOF

cat > /etc/ssh/sshd_config.d/90-change-port.conf <<-EOF
	# Changing the ssh port
	Port {{ hetzner_install_ansible_port }}
EOF

systemctl enable sshd.service

sed -i '/^rotate/s/-\?[0-9]\+/0/' /etc/logrotate.conf

#-------- BTRFS + Snapper
# Mounting the correct subvolume
mount -o subvol=/@/var /dev/disk/by-partlabel/p.lxroot /var

# Creating subvolume and adding config to snapper
SUBVOLUME_PATH="{{ ("/var/", "container-volumes") | path_join }}"
btrfs -q subvolume create "$SUBVOLUME_PATH"
btrfs -q property set "$SUBVOLUME_PATH" compression zstd
btrfs quota enable "$SUBVOLUME_PATH"
chown '--reference={{ ("/home/", hetzner_install_ansible_user) | path_join }}' "$SUBVOLUME_PATH"
btrfs -q subvolume create "{{ ("/var/", "container-volumes", ".snapshots") | path_join }}"

cat > /etc/snapper/configs/container-volumes <<-EOF
	# subvolume to snapshot
	SUBVOLUME="{{ ("/var/", "container-volumes") | path_join }}"
	
	# qgroup of the subvolume
	QGROUP="$(btrfs subvolume show $SUBVOLUME_PATH | grep Quota | cut -f4)"
	
	# filesystem type
	FSTYPE="btrfs"
	
	# fraction of the filesystems space the snapshots may use
	SPACE_LIMIT="0.5"
	
	# fraction of the filesystems space that should be free
	FREE_LIMIT="0.2"
	
	# users and groups allowed to work with config
	ALLOW_USERS=""
	ALLOW_GROUPS=""
	
	# sync users and groups from ALLOW_USERS and ALLOW_GROUPS to .snapshots
	# directory
	SYNC_ACL="no"
	
	# start comparing pre- and post-snapshot in background after creating
	# post-snapshot
	BACKGROUND_COMPARISON="yes"
	
	# run daily number cleanup
	NUMBER_CLEANUP="yes"
	
	# limit for number cleanup
	NUMBER_MIN_AGE="0"
	NUMBER_LIMIT="0"
	NUMBER_LIMIT_IMPORTANT="10"
	
	# create hourly snapshots
	TIMELINE_CREATE="yes"
	
	# cleanup hourly snapshots after some time
	TIMELINE_CLEANUP="yes"
	
	# limits for timeline cleanup
	TIMELINE_MIN_AGE="1800"
	TIMELINE_LIMIT_HOURLY="6"
	TIMELINE_LIMIT_DAILY="2"
	TIMELINE_LIMIT_WEEKLY="0"
	TIMELINE_LIMIT_MONTHLY="0"
	TIMELINE_LIMIT_YEARLY="0"
	
	# cleanup empty pre-post-pairs
	EMPTY_PRE_POST_CLEANUP="yes"
	
	# limits for empty pre-post-pair cleanup
	EMPTY_PRE_POST_MIN_AGE="0"
EOF

umount /var
sed -i '/^SNAPPER_CONFIGS/s/"\(.*\)"/"\1 container-volumes"/' /etc/sysconfig/snapper

sed -i \
	-e '/^BTRFS_BALANCE_MOUNTPOINTS/s$"\(.*\)"$"\1:/var"$' \
	-e '/^BTRFS_BALANCE_\(D\|M\)USAGE/s/".*"/"50"/' /etc/sysconfig/btrfsmaintenance

mkdir -p /etc/systemd/system/snapper-cleanup.timer.d
cat > /etc/systemd/system/snapper-cleanup.timer.d/schedule.conf <<-EOF
	[Timer]
	OnUnitActiveSec=1h
EOF

#-------- Docker
# Uninstall podman
zypper --non-interactive remove podman

# Install docker's python modules
python3 -m ensurepip
python3 -m pip install docker

# Forcing subuids/subgids
sed -i '/^DOCKER_OPTS/s/"\(.*\)"/"\1 --userns-remap default --default-address-pool base=172.17.0.0/12,size=24"/' /etc/sysconfig/docker

# Enabling docker
systemctl enable docker.service

# Installing compose for ansible_user
COMPOSE_VERSION='v2.24.5'
COMPOSE_INSTALL_COMMAND=$(cat <<EOF
mkdir -p "$HOME/.docker/cli-plugins"
curl -SL "https://github.com/docker/compose/releases/download/$COMPOSE_VERSION/docker-compose-linux-x86_64" -o "$HOME/.docker/cli-plugins/docker-compose"
chmod +x "$HOME/.docker/cli-plugins/docker-compose"
EOF
)
su -c "$COMPOSE_INSTALL_COMMAND" - {{ hetzner_install_ansible_user }}
