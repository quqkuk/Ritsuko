sshd_local_tcp_forwarding.pp:
	checkmodule -m sshd_local_tcp_forwarding.te -o sshd_local_tcp_forwarding.mod
	semodule_package -m sshd_local_tcp_forwarding.mod -o sshd_local_tcp_forwarding.pp
	rm sshd_local_tcp_forwarding.mod
