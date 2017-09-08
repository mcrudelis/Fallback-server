#!/bin/bash

#=================================================
# READ CONFIGURATION FROM CONFIG.CONF
#=================================================
# Encryption
encrypt=$(grep encrypt= config.conf | cut -d'=' -f2)
# encrypt has a default value at 0
encrypt=${encrypt:-0}

#=================================================
# SET VARIABLES
#=================================================

generic_backup="sudo yunohost backup create"
local_archive_dir=new_backup
mkdir -p "$local_archive_dir"
pass_file=cred

#=================================================
# DECLARE FUNCTIONS
#=================================================

main_message () {
	echo -e "\e[1m$1\e[0m"
}

# Encrypt the backup, if the encryption is set.
backup_encrypt() {
	if [ $encrypt -eq 1 ]
	then
		main_message ">>>> Encryption of $backup_name"
		# Remove the previous encrypted backup
		rm -f "$local_archive_dir/$backup_name.tar.gz.cpt"
		sudo ccrypt --encrypt --keyfile "$pass_file" "$local_archive_dir/$backup_name.tar.gz"
	fi
}

#=================================================
# DEFINE A ENCRYPTION KEY
#=================================================

read -p ">>> Please enter a encryption key: " -s ccrypt_mdp
# Store the password in pass_file
echo $ccrypt_mdp > "$pass_file"
# Clear the variable
unset ccrypt_mdp
echo -e "\n"
# And securise the file
sudo chmod 400 $pass_file

#=================================================
# MAKE A BACKUP OF THE SYSTEM
#=================================================

backup_name="system_new_fallback_backup"
backup_hooks="conf_ldap conf_ynh_mysql conf_ssowat conf_ynh_certs data_mail conf_xmpp conf_nginx conf_cron conf_ynh_currenthost"
backup_command="$generic_backup --ignore-apps --system $backup_hooks --name $backup_name"
# If the backup is different than the previous one

main_message ">>> Make a backup for $backup_name"
# Make a backup
$backup_command
# Copy the backup in the dedicated directory
sudo cp "/home/yunohost.backup/archives/$backup_name.tar.gz" "$local_archive_dir/$backup_name.tar.gz"
# Then remove the backup in yunohost directory.
sudo yunohost backup delete "$backup_name"
# Encrypt the backup
backup_encrypt

#=================================================
# MAKE BACKUPS OF THE APPS
#=================================================

while read app
do
	appid="${app//\[.\]\: /}"
	backup_name="${appid}_new_fallback_backup"
	backup_command="$generic_backup --ignore-system --name $backup_name --apps"
	main_message ">>> Make a backup for $backup_name"
	# Make a backup
	$backup_command $appid
	# Move the backup in the dedicated directory
	sudo cp "/home/yunohost.backup/archives/$backup_name.tar.gz" "$local_archive_dir/$backup_name.tar.gz"
	# Then remove the backup in yunohost directory.
	sudo yunohost backup delete "$backup_name"
	# Encrypt the backup
	backup_encrypt
	main_message ">>> Remove the app $appid"
	sudo yunohost app remove $appid
done <<< "$(grep "^\[\.\]\:" app_list)"

#=================================================
# MOVE LIST
#=================================================

mv app_list "$local_archive_dir/app_list"
ccrypt --encrypt --keyfile "$pass_file" "$local_archive_dir/app_list"

#=================================================
# CLEAN THE FILES
#=================================================

main_message "> Remove the temporary files"
rm config.conf
sudo rm "$pass_file"

#=================================================
# RESTORE THE GLOBAL BACKUP
#=================================================

main_message "> Restore the global backup"
sudo yunohost backup restore --force backup_before_deploy_fallback
