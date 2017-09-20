#!/bin/bash

ynh_backup="sudo yunohost backup create"
ynh_restore="sudo yunohost backup restore --force"
ynh_backup_delete="sudo yunohost backup delete"

backup_extension="_fallback_bck"

get_infos_from_config () {
	# Fallback credential
	ssh_user=$(grep ssh_user= "$config_file" | cut -d'=' -f2)
	ssh_host=$(grep ssh_host= "$config_file" | cut -d'=' -f2)
	ssh_key="$(grep ssh_key= "$config_file" | cut -d'=' -f2)"
	ssh_port=$(grep ssh_port= "$config_file" | cut -d'=' -f2)
	# ssh_port has a default value at 22
	ssh_port=${ssh_port:-22}
	ssh_options="-p $ssh_port -i \"$ssh_key\" $(grep ssh_options= "$config_file" | cut -d'=' -f2)"

	# Encryption
	encrypt=$(grep encrypt= "$config_file" | cut -d'=' -f2)
	# encrypt has a default value at 0
	encrypt=${encrypt:-0}
	pass_file="$(grep pass_file= "$config_file" | cut -d'=' -f2)"

	# Main backup directory
	main_storage_dir=$(grep main_storage_dir= "$config_file" | cut -d'=' -f2)
}

main_message () {
	echo -e "\e[1m$1\e[0m"
}

main_message_log () {
	main_message "$1"
	echo "$1" >> $logfile
}

encrypt_a_file () {
	local file_to_encrypt="$1"
	# Remove the previous encrypted file
	sudo rm -f "$file_to_encrypt.cpt"
	sudo ccrypt --encrypt --keyfile "$pass_file" "$file_to_encrypt"
}

decrypt_a_file () {
	local file_to_decrypt="$1"
	sudo ccrypt --decrypt --keyfile "$pass_file" "$file_to_decrypt"
}

define_encryption_key () {
	echo -en "\e[1m\e[33m>>> Please enter your encryption key:\e[0m "
	read -s ccrypt_mdp
	# Store the password in pass_file
	echo $ccrypt_mdp | sudo tee "$pass_file" > /dev/null
	# Clear the variable
	unset ccrypt_mdp
	echo -e "\n"
	# And securise the file
	sudo chmod 400 "$pass_file"
}
