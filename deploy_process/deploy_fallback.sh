#!/bin/bash

#=================================================
# SET VARIABLES
#=================================================

local_archive_dir=backup
pass_file=cred

#=================================================
# DECLARE FUNCTIONS
#=================================================

main_message () {
	echo -e "\e[1m$1\e[0m"
}

# Decrypt a backup, if the file is encrypted
backup_decrypt() {

	decryptafile () {
		sudo ccrypt --decrypt --keyfile "$pass_file" "decrypted/$crypt_file"
	}

	# crypt_file take the name of the file, with or without .cpt
	local crypt_file="$(cd backup && ls -1 "$1"*)"
	mkdir -p decrypted
	cp "$local_archive_dir/$crypt_file" "decrypted/$crypt_file"
	# If the file has .cpt as extension, it's a crypted file
	if [ "${crypt_file##*.}" == cpt ]
	then
		main_message ">> Decrypt $crypt_file"
		# If there no file for the decryption password.
		if [ ! -s "$pass_file" ]
		then
			while [ ! -s "$pass_file" ]
			do
				read -p ">>> Please enter the decryption key: " -s ccrypt_mdp
				# Store the password in pass_file
				echo $ccrypt_mdp > "$pass_file"
				# Clear the variable
				unset ccrypt_mdp
				echo -e "\n"
				# And securise the file
				sudo chmod 400 $pass_file
				if ! decryptafile; then
					# If ccrypt fail, remove the pass_file and reask for the password
					sudo rm $pass_file
				fi
			done
		else
			decryptafile
		fi
	fi
}

restore_a_backup() {
	local backup_file="$1"
	backup_decrypt $backup_file
	sudo cp "decrypted/$backup_file.tar.gz" "/home/yunohost.backup/archives/$backup_file.tar.gz"
	sudo yunohost backup restore --force $backup_file
	sudo yunohost backup delete $backup_file
}

#=================================================
# DECRYPT CONFIG AND LIST
#=================================================

backup_decrypt config.conf
cp decrypted/config.conf ./config.conf
backup_decrypt app_list
cp decrypted/app_list ./app_list

#=================================================
# MAKE A GLOBAL BACKUP
#=================================================

main_message "> Create a global backup before deploying the fallback"
sudo yunohost backup delete backup_before_deploy_fallback 2> /dev/null
backup_hooks="conf_ldap conf_ynh_mysql conf_ssowat conf_ynh_certs data_mail conf_xmpp conf_nginx conf_cron conf_ynh_currenthost"
sudo yunohost backup create --system $backup_hooks --name backup_before_deploy_fallback

#=================================================
# RESTORE THE SYSTEM FROM THE MAIN SERVER BACKUP
#=================================================

main_message "> Restore the system from the main server's backup"
restore_a_backup system_fallback_backup

#=================================================
# RESTORE APPS FROM THE MAIN SERVER BACKUP
#=================================================

while read app
do
	appid="${app//\[.\]\: /}"
	backup_name="${appid}_fallback_backup"
	main_message "> Restore the app $appid"
	# If an app exist with the same id
	if sudo yunohost app list --installed --filter $appid | grep -q id:
	then
		# Remove this app
		sudo yunohost app remove $appid
	fi
	restore_a_backup $backup_name
done <<< "$(grep "^\[\.\]\:" "decrypted/app_list")"

#=================================================
# CLEAN THE FILES
#=================================================

main_message "> Remove the temporary files"
rm -r decrypted
sudo rm "$pass_file"
