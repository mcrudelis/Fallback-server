#!/bin/bash

#=================================================
# GET THE SCRIPT'S DIRECTORY
#=================================================

script_dir="$(dirname $(realpath $0))"

#=================================================
# DETECT AUTO-MODE
#=================================================

auto_mode=0
if [ "$1" = "auto" ]
then
	auto_mode=1
fi

#=================================================
# IMPORT FUNCTIONS
#=================================================

source "$script_dir/../commons/functions.sh"

#=================================================
# DISCLAIMER
#=================================================

main_message "This script will deploy your backups on this server and make it your
fallback server.
When you're done and you would cease to use this other server. Use the script
'close_fallback.sh'.
"

if [ $auto_mode -eq 0 ]
then
	read -p "Press a key to continue."
fi

#=================================================
# SET VARIABLES
#=================================================

# Usually the backup directory is the home directory of the ssh user
local_archive_dir="/home/fallback/backup"

decrypted_dir="$local_archive_dir/decrypted"
pass_file="$decrypted_dir/pass"

#=================================================
# DECLARE FUNCTIONS
#=================================================

# Decrypt a backup, if the file is encrypted
backup_decrypt() {
	# crypt_file take the name of the file, with or without .cpt
	local crypt_file="$(cd "$local_archive_dir" && ls -1 "$1"*)"
	# Remove the info.json file name
	crypt_file="$(echo "$crypt_file" | sed '/.info.json/d')"
	sudo mkdir -p "$decrypted_dir"
	sudo cp "$local_archive_dir/$crypt_file" "$decrypted_dir/$crypt_file"
	# If the file has .cpt as extension, it's a crypted file
	if [ "${crypt_file##*.}" == cpt ]
	then
		main_message ">> Decrypt $crypt_file"
		# If there no file for the decryption password.
		if [ ! -s "$pass_file" ]
		then
			if [ $auto_mode -eq 1 ]
			then
				echo "!!! Your backup is encrypted, but the password file isn't available ($pass_file).
!!! The fallback can't be deployed automatically without this password."
				exit 1
			fi
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
	# Uncompress the archive file to its simple original tar file.
	tar -xf "$decrypted_dir/$backup_file.tar.gz" -C "$decrypted_dir"
	# And move it to yunohost backup
	sudo mv "$decrypted_dir/home/yunohost.app/fallback/fallback_backup/temp_fallback_backup/$backup_file.tar" "/home/yunohost.backup/archives/"
	# Restore the archive
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
backup_hooks=($(get_backup_hooks))
$ynh_backup --system ${backup_hooks[@]} --name backup_before_deploy_fallback

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
	if sudo yunohost app list | grep --quiet "id: $appid"
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

main_message "\nTo be able to use this server in replacement of your main server, you
should check your dns and be sure it points to this server."
