#!/bin/bash

#=================================================
# DISCLAIMER
#=================================================

echo -e "\e[1mBe carreful with this script !
It will change your system by restoring the backup from your fallback server.
Before any restoring, a backup will be make for each part of your server.
Then, each backup from your fallback server will be restored to update the data
of your server.\e[0m
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
# READ CONFIGURATION FROM CONFIG.CONF
#=================================================

config_file="$script_dir/../send_process/config.conf"
get_infos_from_config

ssh_options="-p $ssh_port -i $ssh_key $ssh_options"

#=================================================
# SET VARIABLES
#=================================================

# Usually is updated_backup
distant_archive_dir="updated_backup"

local_archive_dir="$main_storage_dir/backup_from_fallback"
decrypted_dir="$local_archive_dir/../decrypted"

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
# DOWNLOAD ARCHIVES FROM THE FALLBACK SERVER
#=================================================

main_message "> Download the archives from the server $ssh_host"
sudo rsync --archive --verbose --human-readable --delete \
	--rsh="ssh $ssh_options" $ssh_user@$ssh_host:$distant_archive_dir/ "$local_archive_dir/"

#=================================================
# DECRYPT LIST
#=================================================

backup_decrypt app_list
sudo cp "$decrypted_dir/app_list" "$script_dir/app_list"

#=================================================
# SYSTEM
#=================================================

echo -en "\n\e[33m\e[1mWould you restore the system from the fallback backup ? (Y/n):\e[0m "
read answer
# Transform all the charactere in lowercase
answer=${answer,,}
if [ "$answer" != "no" ] && [ "$answer" != "n" ]
then
	#=================================================
	# MAKE A BACKUP OF THE SYSTEM
	#=================================================

	main_message "> Create a backup of the system before restoring"
	backup_name="system_pre_flbck_restore"
	$ynh_backup_delete $backup_name 2> /dev/null
	backup_hooks="conf_ldap conf_ynh_mysql conf_ssowat conf_ynh_certs data_mail conf_xmpp conf_nginx conf_cron conf_ynh_currenthost"
	if [ "$(get_debian_release)" = "jessie" ]
	then
		backup_ignore="--ignore-apps"
	else
		backup_ignore=""
	fi
	$ynh_backup $backup_ignore --system $backup_hooks --name $backup_name

	#=================================================
	# RESTORE THE SYSTEM FROM THE MAIN SERVER BACKUP
	#=================================================

	main_message "> Restore the system from the main server's backup"
	restore_a_backup system$backup_extension
fi

#=================================================
# RESTORE APPS FROM THE MAIN SERVER BACKUP
#=================================================

while read <&3 app
do
	appid="${app//\[.\]\: /}"
	backup_name="$appid$backup_extension"
	# Ask only if there really a backup for this app
	if ( cd "$local_archive_dir" && test -e $backup_name.* )
	then
		echo -en "\n\e[33m\e[1mWould you restore $appid from the fallback backup ? (Y/n):\e[0m "
		read answer
		# Transform all the charactere in lowercase
		answer=${answer,,}
		if [ "$answer" != "no" ] && [ "$answer" != "n" ]
		then
			main_message "> Restore the app $appid"
			# If an app exist with the same id
			if sudo yunohost app list --installed --filter $appid | grep -q id:
			then
				$ynh_backup_delete ${appid}_pre_flbck_restore 2> /dev/null
				# Make a backup before
				if [ "$(get_debian_release)" = "jessie" ]
				then
					backup_ignore="--ignore-system"
				else
					backup_ignore=""
				fi
				$ynh_backup $backup_ignore --name ${appid}_pre_flbck_restore --apps $appid
				# Remove this app
				sudo yunohost app remove $appid
			fi
			restore_a_backup $backup_name
		fi
	fi
done 3<<< "$(grep "^\[\.\]\:" "$script_dir/app_list")"

#=================================================
# CLEAN THE FILES
#=================================================

main_message "> Remove the temporary files"
sudo rm -r "$decrypted_dir"
