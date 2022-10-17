ignition_file.ign.j2:
	podman run -i --rm quay.io/coreos/butane:release --strict < butane_file.bu | \
		sed -e 's^/template_installation_drive^{{ ('\''/dev/'\'', hetzner_install_installation_drive) | path_join }}^' \
		-e 's^\("sizeMiB"\):1234567890^\1:{{ (swap_partition_details['\''start'\''] | int - spare_partition_details['\''start'\''] | int)*(swap_partition_details['\''sectorsize'\''] | int)/(1024**2) }}^' \
		-e 's^template_ssh_port^{{ hetzner_install_ansible_port }}^' \
		-e 's^template_user^{{ hetzner_install_ansible_user }}^g' \
		> ignition_file.ign.j2

