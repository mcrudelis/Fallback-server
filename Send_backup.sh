#!/bin/bash

#=================================================
# READ CONFIGURATION FROM CONFIG.CONF
#=================================================
# Fallback credential
ssh_user=$(grep ssh_user= config.conf | cut -d'=' -f2)
ssh_host=$(grep ssh_host= config.conf | cut -d'=' -f2)
ssh_key="$(grep ssh_key= config.conf | cut -d'=' -f2)"
ssh_port=$(grep ssh_port= config.conf | cut -d'=' -f2)
# ssh_port has a default value at 22
ssh_port=${ssh_port:-22}
ssh_options="-p $ssh_port -i \"$ssh_key\" $(grep ssh_options= config.conf | cut -d'=' -f2)"

# Encryption
encrypt=$(grep encrypt= config.conf | cut -d'=' -f2)
# encrypt has a default value at 0
encrypt=${encrypt:-0}
pass_file="$(grep pass_file= config.conf | cut -d'=' -f2)"

#=================================================
# SET VARIABLES
#=================================================

temp_backup_dir="temp_fallback_backup"
generic_backup="sudo yunohost backup create --output-directory $temp_backup_dir"
local_archive_dir=backup
logfile=send_backup.log
logger="tee --append $logfile"

#=================================================
# INITIALISE THE LOG FILE
#=================================================

echo -e "\n\n" >> $logfile
date >> $logfile

#=================================================
# DECLARE FUNCTIONS
#=================================================

main_message () {
	echo -e "\e[1m$1\e[0m"
	echo "$1" >> $logfile
}

# Make a temporary backup and compare the checksum with the previous backup.
backup_checksum () {
	local backup_cmd="$1"
	# Make a temporary backup
	main_message "> Make a temporary backup for $backup_name"
	$backup_cmd --no-compress > /dev/null 2>&1
	# Remove the info.json file
	sudo rm "$temp_backup_dir/info.json" 2>&1 | $logger
	# Make a checksum of each file in the directory, then a checksum of all these cheksums.
	# That give us a checksum for the whole directory
	new_checksum=$(sudo find "$temp_backup_dir" -type f -exec md5sum {} \; | md5sum | cut -d' ' -f1)
	# Get the previous checksum
	old_checksum=$(cat "checksum/$backup_name" 2> /dev/null)
	sudo rm -r "$temp_backup_dir" 2>&1 | $logger
	# And compare the 2 checksum
	if [ "$new_checksum" == "$old_checksum" ]
	then
		main_message ">> This backup is the same than the previous one"
		return 1
	else
		main_message ">> This backup is different than the previous one"
		echo $new_checksum > "checksum/$backup_name"
		return 0
	fi
}

# Encrypt the backup, if the encryption is set.
backup_encrypt() {
	if [ $encrypt -eq 1 ]
	then
		main_message ">>>> Encryption of $backup_name"
		# Remove the previous encrypted backup
		rm -f "$local_archive_dir/$backup_name.tar.gz.cpt" 2>&1 | $logger
		sudo ccrypt --encrypt --keyfile "$pass_file" "$local_archive_dir/$backup_name.tar.gz" 2>&1 | $logger
	fi
}

#=================================================
# MAKE A BACKUP OF THE SYSTEM
#=================================================

backup_name="system_fallback_backup"
backup_hooks="conf_ldap conf_ynh_mysql conf_ssowat conf_ynh_certs data_mail conf_xmpp conf_nginx conf_cron conf_ynh_currenthost"
backup_command="$generic_backup --ignore-apps --system $backup_hooks --name $backup_name"
# If the backup is different than the previous one
if backup_checksum "$backup_command"
then
	main_message ">>> Make a real backup for $backup_name"
	# Make a real backup
	$backup_command 2>&1 | $logger
	# Move the backup in the dedicated directory
	sudo mv "$temp_backup_dir/$backup_name.tar.gz" "$local_archive_dir/$backup_name.tar.gz" 2>&1 | $logger
	# Then remove the link in yunohost directory.
	sudo yunohost backup delete "$backup_name" 2>&1 | $logger
	# Encrypt the backup
	backup_encrypt
fi

#=================================================
# MAKE BACKUPS OF THE APPS
#=================================================

while read app
do
	appid="${app//\[.\]\: /}"
	backup_name="${appid}_fallback_backup"
	backup_command="$generic_backup --ignore-system --name $backup_name --apps"
	# If the backup is different than the previous one
	if backup_checksum "$backup_command $appid"
	then
		main_message ">>> Make a real backup for $backup_name"
		# Make a real backup
		$backup_command $appid 2>&1 | $logger
		# Move the backup in the dedicated directory
		sudo mv "$temp_backup_dir/$backup_name.tar.gz" "$local_archive_dir/$backup_name.tar.gz" 2>&1 | $logger
		# Then remove the link in yunohost directory.
		sudo yunohost backup delete "$backup_name" 2>&1 | $logger
		# Encrypt the backup
		backup_encrypt
	fi
done <<< "$(grep "^\[\.\]\:" app_list)"

#=================================================
# REMOVE OLD APPS BACKUPS
#=================================================

while read archive
do
	# Remove the ending of each file name, to keep only the id of the app
	appid="${archive//_fallback_backup.*/}"
	# Ignore the system backup
	if [ "$appid" != system ]
	then
		# Try to find the app in the app_list, with its point.
		if ! grep --quiet "^\[\.\]\: $appid" app_list
		then
			main_message "> Remove the old backup $archive"
			# If this app is not is the list of app to backup, remove it
			rm "$local_archive_dir/$archive" 2>&1 | $logger
			rm "checksum/${appid}_fallback_backup" 2>&1 | $logger
		fi
	fi
done <<< "$(ls -1 "$local_archive_dir")"

#=================================================
# SEND ARCHIVES ON THE FALLBACK SERVER
#=================================================

main_message "> Send the archives on the server $ssh_host"
sudo rsync --archive --verbose --human-readable --delete "$local_archive_dir" \
	--rsh="ssh $ssh_options" $ssh_user@$ssh_host: 2>&1 | $logger
