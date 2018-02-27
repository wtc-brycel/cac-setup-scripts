#!/bin/bash

if [ $EUID != 0 ]; then
	sudo "$0" "$@"
	exit $?
fi

# Text Colors

# Reset
Color_Off='\033[0m'       # Text Reset

# Regular Colors
Black='\033[0;30m'        # Black
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow
Blue='\033[0;34m'         # Blue
Purple='\033[0;35m'       # Purple
Cyan='\033[0;36m'         # Cyan
White='\033[0;37m'        # White

upgrade_machine() {
	apt-get update
	apt-get upgrade -y
	apt-get dist-upgrade -y
	apt-get autoremove -y
}

cleanup_old_kernels() {

	# clean up old kernels

	echo
	echo "=========================================="
	echo -e $Green"cleaning up old kernels..."$Color_Off
	echo "=========================================="
	echo

	mapfile -t kernels < <(dpkg -l | tail -n +6 | grep -E 'linux-image-[0-9]+' | grep -Fv $(uname -r) | awk '{print $2}' | sed s/-generic//)

	for kernel in "${kernels[@]}"
	do
		echo "=========================================="
		echo -e $Green"removing $kernel"$Color_Off
		echo "=========================================="
		sudo dpkg --purge $kernel-generic
		sudo dpkg --purge $kernel-header $kernel
	done


	echo
	echo "=========================================="
	echo -e $Green"deleting old linux images from boot partition..."$Color_Off
	echo "=========================================="
	echo

	ls /boot | grep "\-generic" | grep -Fv $(uname -r) | awk '{print "/boot/" $1}' | xargs rm

}

regenerate_ssh_server_keys() {
	mapfile -t ssh_key_types < <(ls -l /etc/ssh | grep .pub | awk '{print $9}' | sed -r 's/ssh_host_([a-zA-Z0-9]+)_key.pub/\1/')

	echo "new ssh server keys:"

	for ssh_key_type in "${ssh_key_types[@]}"
	do
		rm /etc/ssh/ssh_host_"$ssh_key_type"_key
		rm /etc/ssh/ssh_host_"$ssh_key_type"_key.pub

		ssh-keygen -q -N "" -t $ssh_key_type -f  /etc/ssh/ssh_host_"$ssh_key_type"_key

		echo
		echo $ssh_key_type | awk '{print toupper($1)}'
		ssh-keygen -E sha256 -lf /etc/ssh/ssh_host_"$ssh_key_type"_key
		ssh-keygen -E md5 -lf /etc/ssh/ssh_host_"$ssh_key_type"_key
	done
}

if [ ! -f .kernel_remove_ready ]; then

	echo "=========================================="
	echo -e $Green"basic information"$Color_Off
	echo "=========================================="
	echo
	tput bel
	echo -e $Yellow"machine name [ubuntu]:"$Color_Off
	read machine_name

	if [[ -z "${machine_name// }" ]]; then
		machine_name=ubuntu
	fi

	sed -i s/ubuntu/$machine_name/ /etc/hosts
	sed -i s/ubuntu/$machine_name/ /etc/hostname
	hostname $machine_name

	tput bel
	echo -e $Yellow"new password for "$Red"root:"$Color_Off
	read -s new_root_password
	
	echo "changing root password"
	echo "root:$new_root_password" | chpasswd
	
	tput bel
	echo -e $Yellow"username:"$Color_Off
	read new_account
	
	tput bel
	echo -e $Yellow"password for new user:"$Color_Off
	read -s new_account_password

	echo "deleting default user"
	deluser --remove-home user

	echo "creating new user $new_account"
	adduser --quiet --disabled-password --gecos "" $new_account
	echo "setting password for $new_account"
	echo "$new_account:$new_account_password" | chpasswd
	adduser $new_account sudo

	echo
	echo "=========================================="
	echo -e $Green"upgrading to latest version before doing a release upgrade..."$Color_Off
	echo "=========================================="
	echo

	# upgrade everything before release upgrade
	upgrade_machine

	touch .kernel_remove_ready
	tput bel
	echo -e $Yellow"press any key to "$Red"reboot machine"$Red", then "$Purple"rerun this script"$Yellow" after rebooting"$Color_Off
	read confirm_key
	reboot -h now
	exit

fi



if [ ! -f .release_upgrade_done ]; then

	cleanup_old_kernels

	# manually select upgrade options (important)

	echo
	echo "=========================================="
	echo -e $Green"begin release upgrade..."$Color_Off
	echo "=========================================="
	echo

	do-release-upgrade

	touch .release_upgrade_done
	tput bel
	echo -e $Yellow"press any key to reboot machine, rerun script after rebooting"$Color_Off
	read confirm_key
	reboot -h now
	exit

fi



cleanup_old_kernels

# check for newer updates

echo
echo "=========================================="
echo -e $Green"check for further updates..."$Color_Off
echo "=========================================="
echo

upgrade_machine

echo
echo "=========================================="
echo -e $Green"cleaning up temporary files..."$Color_Off
echo "=========================================="
echo

rm .kernel_remove_ready
rm .release_upgrade_done


echo
echo "=========================================="
echo -e $Green"Configuring SSH..."$Color_Off
echo "=========================================="
echo

echo "disabling root login..."
sed -i "s/PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config

tput bel
echo -e $Yellow"new ssh port [22]:"$Color_Off
read ssh_port

if [[ -z "${ssh_port// }" ]]; then
	ssh_port=22
fi

sed -i "s/Port 22/Port $ssh_port/" /etc/ssh/sshd_config


echo "creating new ssh server keys..."
regenerate_ssh_server_keys

echo "restarting ssh..."
service ssh restart

echo
echo "=========================================="
echo -e $Green"Configuring firewall..."$Color_Off
echo "=========================================="
echo
tput bel
echo -e $Yellow"administrative network or host with netmask (1.2.3.4/32):"$Color_Off	# Network or host we'll allow to SSH in.
read administrative_network

while [[ "$administrative_network" == "" ]] 											# While input empty
do
tput bel
	echo -e $Red"(ERROR) Enter a valid network or host."$Color_off						# Ask the user to enter a valid string
    read administrative_network															# Get input again
done

echo "creating firewall rules..."
echo -e $White"ufw allow from "$Cyan"$administrative_network "$White"to any port "$Cyan"$ssh_port"$Color_Off
ufw allow from $administrative_network to any port $ssh_port

echo "enabling firewall..."
tput bel
echo -e $Red"CONFIRM CORRECT "$Purple"ADMINISTRATIVE NETWORK "$Red"BELOW."$Color_Off
ufw enable


echo
echo "=========================================="
echo -e $Green"System is Ready"$Color_Off
echo "=========================================="
echo
tput bel
echo -e $Yellow"press any key to reboot"$Color_Off
read confirm_key
reboot -h now

