#!/bin/bash

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

config_file="$script_dir/config.conf"
get_infos_from_config

#=================================================
# SET VARIABLES
#=================================================

main_archive_dir="$main_storage_dir/backup"
temp_backup_dir="$main_storage_dir/temp_fallback_backup"
checksum_dir="$script_dir/checksum"
logfile="$script_dir/send_backup.log"

logger="tee --append $logfile"

#=================================================
# INITIALISE THE LOG FILE
#=================================================

echo -e "\n\n" >> "$logfile"
date >> "$logfile"

#=================================================
# DECLARE FUNCTIONS
#=================================================

# Make a temporary backup and compare the checksum with the previous backup.
backup_checksum () {
	local backup_cmd="$1"
	# Make a temporary backup
	main_message_log "> Make a temporary backup for $backup_name"
	$backup_cmd --no-compress > /dev/null 2>&1
	# Remove the info.json file
	sudo rm "$temp_backup_dir/info.json" 2>&1 | $logger
	# Make a checksum of each file in the directory, then a checksum of all these cheksums.
	# That give us a checksum for the whole directory
	new_checksum=$(sudo find "$temp_backup_dir" -type f -exec md5sum {} \; | md5sum | cut -d' ' -f1)
	# Get the previous checksum
	old_checksum=$(cat "$checksum_dir/$backup_name" 2> /dev/null)
	sudo rm -r "$temp_backup_dir" 2>&1 | $logger
	# And compare the 2 checksum
	if [ "$new_checksum" == "$old_checksum" ]
	then
		main_message_log ">> This backup is the same than the previous one"
		return 1
	else
		main_message_log ">> This backup is different than the previous one"
		echo $new_checksum > "$checksum_dir/$backup_name"
		return 0
	fi
}

# Encrypt the backup, if the encryption is set.
backup_encrypt() {
	if [ $encrypt -eq 1 ]
	then
		main_message_log ">>>> Encryption of $backup_name"
		sudo encrypt_a_file "$main_archive_dir/$backup_name.tar.gz" 2>&1 | $logger
	fi
}

#=================================================
# MAKE A BACKUP OF THE SYSTEM
#=================================================

backup_name="system$backup_extension"
backup_hooks="conf_ldap conf_ynh_mysql conf_ssowat conf_ynh_certs data_mail conf_xmpp conf_nginx conf_cron conf_ynh_currenthost"
backup_command="$ynh_backup --output-directory $temp_backup_dir --ignore-apps --system $backup_hooks --name $backup_name"
# If the backup is different than the previous one
if backup_checksum "$backup_command"
then
	main_message_log ">>> Make a real backup for $backup_name"
	# Make a real backup
	$backup_command 2>&1 | $logger
	# Move the backup in the dedicated directory
	sudo mv "$temp_backup_dir/$backup_name.tar.gz" "$main_archive_dir/$backup_name.tar.gz" 2>&1 | $logger
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
	backup_name="$appid$backup_extension"
	backup_command="$ynh_backup --output-directory $temp_backup_dir --ignore-system --name $backup_name --apps"
	# If the backup is different than the previous one
	if backup_checksum "$backup_command $appid"
	then
		main_message_log ">>> Make a real backup for $backup_name"
		# Make a real backup
		$backup_command $appid 2>&1 | $logger
		# Move the backup in the dedicated directory
		sudo mv "$temp_backup_dir/$backup_name.tar.gz" "$main_archive_dir/$backup_name.tar.gz" 2>&1 | $logger
		# Then remove the link in yunohost directory.
		sudo yunohost backup delete "$backup_name" 2>&1 | $logger
		# Encrypt the backup
		backup_encrypt
	fi
done <<< "$(grep "^\[\.\]\:" "$script_dir/app_list")"

#=================================================
# REMOVE OLD APPS BACKUPS
#=================================================

while read archive
do
	# Remove the ending of each file name, to keep only the id of the app
	appid="$(basename "${archive//$backup_extension.*/}")"
	# Ignore the system backup
	if [ "$appid" != system ] || [ "$appid" != app_list.cpt ] || [ "$appid" != config.conf.cpt ]
	then
		# Try to find the app in the app_list, with its point.
		if ! grep --quiet "^\[\.\]\: $appid" "$script_dir/app_list"
		then
			main_message_log "> Remove the old backup $archive"
			# If this app is not is the list of app to backup, remove it
			rm "$main_archive_dir/$archive" 2>&1 | $logger
			rm "$checksum_dir/$appid$backup_extension" 2>&1 | $logger
		fi
	fi
done <<< "$(ls -1 "$main_archive_dir")"

#=================================================
# COPY CONFIG AND LIST
#=================================================

simple_checksum () {
	local file="$1"
	# Compare the checksum
	if ! md5sum --status --check "$checksum_dir/${file}_checksum" > /dev/null 2>&1
	then
		# If it's different, reset the checksum and copy then encrypt the file
		md5sum --status $file > "$checksum_dir/${file}_checksum" 2> /dev/null
		cp "$file" "$main_archive_dir/$file" 2>&1 | $logger
		if [ $encrypt -eq 1 ]
		then
			main_message_log "> Encryption of $file"
			sudo encrypt_a_file "$main_archive_dir/$file" 2>&1 | $logger
		fi
	fi
}

simple_checksum "$script_dir/config.conf"
simple_checksum "$script_dir/app_list"

#=================================================
# SEND ARCHIVES ON THE FALLBACK SERVER
#=================================================

main_message_log "> Send the archives on the server $ssh_host"
sudo rsync --archive --verbose --human-readable --delete "$main_archive_dir" \
	--rsh="ssh $ssh_options" $ssh_user@$ssh_host: 2>&1 | $logger
