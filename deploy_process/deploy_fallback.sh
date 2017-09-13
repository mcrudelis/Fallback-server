#!/bin/bash

#=================================================
# DISCLAIMER
#=================================================

echo -e "\e[1mThis script will deploy your backups on this server and make it your
fallback server.
When you're done and you would cease to use this other server. Use the script
'close_fallback.sh'.\e[0m
"

read -p "Press a key to continue."

#=================================================
# GET THE SCRIPT'S DIRECTORY
#=================================================

script_dir="$(dirname $(realpath $0))"

#=================================================
# IMPORT FUNCTIONS
#=================================================

source "$script_dir/../commons/functions.sh"

#=================================================
# SET VARIABLES
#=================================================

# Usually is the home directory of the ssh user, then backup
local_archive_dir="/home/USER/backup"

decrypted_dir="$local_archive_dir/decrypted"
pass_file="$decrypted_dir/pass"

#=================================================
# DECLARE FUNCTIONS
#=================================================

# Decrypt a backup, if the file is encrypted
backup_decrypt() {
	# crypt_file take the name of the file, with or without .cpt
	local crypt_file="$(cd "$local_archive_dir" && ls -1 "$1"*)"
	sudo mkdir -p "$decrypted_dir"
	sudo cp "$local_archive_dir/$crypt_file" "$decrypted_dir/$crypt_file"
	# If the file has .cpt as extension, it's a crypted file
	if [ "${crypt_file##*.}" == cpt ]
	then
		main_message ">> Decrypt $crypt_file"
		# If there no file for the decryption password.
		if [ ! -s "$pass_file" ]
		then
			while [ ! -s "$pass_file" ]
			do
				define_encryption_key
				if ! decrypt_a_file "$decrypted_dir/$crypt_file"; then
					# If ccrypt fail, remove the pass_file and reask for the password
					sudo rm "$pass_file"
				fi
			done
		else
			decrypt_a_file "$decrypted_dir/$crypt_file"
		fi
	fi
}

restore_a_backup() {
	local backup_file="$1"
	backup_decrypt "$backup_file"
	sudo cp "$decrypted_dir/$backup_file.tar.gz" "/home/yunohost.backup/archives/$backup_file.tar.gz"
	$ynh_restore $backup_file
	$ynh_backup_delete $backup_file
}

#=================================================
# DECRYPT CONFIG AND LIST
#=================================================

backup_decrypt config.conf
sudo cp "$decrypted_dir/config.conf" "$script_dir/config.conf"
backup_decrypt app_list
sudo cp "$decrypted_dir/app_list" "$script_dir/app_list"

#=================================================
# MAKE A GLOBAL BACKUP
#=================================================

main_message "> Create a global backup before deploying the fallback"
$ynh_backup_delete backup_before_deploy_fallback 2> /dev/null
backup_hooks="conf_ldap conf_ynh_mysql conf_ssowat conf_ynh_certs data_mail conf_xmpp conf_nginx conf_cron conf_ynh_currenthost"
$ynh_backup --system $backup_hooks --name backup_before_deploy_fallback

#=================================================
# RESTORE THE SYSTEM FROM THE MAIN SERVER BACKUP
#=================================================

main_message "> Restore the system from the main server's backup"
restore_a_backup system$backup_extension

#=================================================
# RESTORE APPS FROM THE MAIN SERVER BACKUP
#=================================================

while read app
do
	appid="${app//\[.\]\: /}"
	backup_name="$appid$backup_extension"
	main_message "> Restore the app $appid"
	# If an app exist with the same id
	if sudo yunohost app list --installed --filter $appid | grep -q id:
	then
		# Remove this app
		sudo yunohost app remove $appid
	fi
	restore_a_backup $backup_name
done <<< "$(grep "^\[\.\]\:" "$script_dir/app_list")"

#=================================================
# CLEAN THE FILES
#=================================================

main_message "> Remove the temporary files"
sudo rm -r "$decrypted_dir"

#=================================================
# DISCLAIMER
#=================================================

echo -e "\n\e[1mTo be able to use this server in replacement of your main server, you
should check your dns and be sure it points on this server.\e[0m"
