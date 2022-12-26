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

echo -e "\e[1mUse this script when you've finished to use this fallback server.
The system and the apps will be backed up and the server will be restored in the
state it was before you use 'deploy_fallback.sh'.
To update your main server with this data, use the script
'update_from_fallback.sh' on your main server.\e[0m
"

if [ $auto_mode -eq 0 ]
then
	read -p "Press a key to continue."
fi

#=================================================
# READ CONFIGURATION FROM CONFIG.CONF
#=================================================

config_file="$script_dir/config.conf"
get_infos_from_config

#=================================================
# SET VARIABLES
#=================================================

# Usually is the home directory of the ssh user, then updated_backup
local_archive_dir="/home/fallback/updated_backup"
sudo mkdir -p "$local_archive_dir"
temp_backup_dir="$local_archive_dir/temp_fallback_backup"

#=================================================
# DEFINE A ENCRYPTION KEY
#=================================================

pass_file="$local_archive_dir/pass"
define_encryption_key

#=================================================
# DECLARE FUNCTIONS
#=================================================

# Encrypt the backup, if the encryption is set.
backup_encrypt() {
	if [ $encrypt -eq 1 ]
	then
		main_message ">>>> Encryption of $backup_name"
		encrypt_a_file "$local_archive_dir/$backup_name.tar.gz"
	fi
}

#=================================================
# MAKE A BACKUP OF THE SYSTEM
#=================================================

backup_name="system$backup_extension"
backup_hooks=($(get_backup_hooks))
if [ "$(get_debian_release)" = "jessie" ]
then
	backup_ignore="--ignore-apps"
else
	backup_ignore=""
fi
backup_command="$ynh_backup $backup_ignore --system ${backup_hooks[@]} --name $backup_name"

main_message ">>> Make a backup for $backup_name"
# Make a backup
$backup_command
# Compress the backup
$ynh_compress_backup --file "$local_archive_dir/$backup_name.tar.gz" /home/yunohost.backup/archives/$backup_name.{tar,info.json}
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
	backup_name="$appid$backup_extension"
	if [ "$(get_debian_release)" = "jessie" ]
	then
		backup_ignore="--ignore-system"
	else
		backup_ignore=""
	fi
	backup_command="$ynh_backup $backup_ignore --name $backup_name --apps"
	main_message ">>> Make a backup for $backup_name"
	# Make a backup
	$backup_command $appid
	# Compress the backup
	$ynh_compress_backup --file "$local_archive_dir/$backup_name.tar.gz" /home/yunohost.backup/archives/$backup_name.{tar,info.json}
	# Then remove the backup in yunohost directory.
	sudo yunohost backup delete "$backup_name"
	# Encrypt the backup
	backup_encrypt
	main_message ">>> Remove the app $appid"
	sudo yunohost app remove $appid
done <<< "$(grep "^\[\.\]\:" "$script_dir/app_list")"

#=================================================
# MOVE LIST
#=================================================

sudo mv "$script_dir/app_list" "$local_archive_dir/app_list"
encrypt_a_file "$local_archive_dir/app_list"

#=================================================
# CLEAN THE FILES
#=================================================

main_message "> Remove the temporary files"
sudo rm "$script_dir/config.conf"
sudo rm "$pass_file"

#=================================================
# CLEAN THE SYSTEM
#=================================================

# Clean the system to remove old config files.
main_message "> Clean the system"

sudo rm -r /etc/nginx/conf.d/*
sudo yunohost tools regen-conf nginx --force
sudo rm -r /etc/metronome/conf.d/*
sudo yunohost tools regen-conf metronome --force
sudo rm -r /var/mail/*

#=================================================
# RESTORE THE GLOBAL BACKUP
#=================================================

main_message "> Restore the global backup"
sudo yunohost backup restore --force backup_before_deploy_fallback

#=================================================
# DISCLAIMER
#=================================================

echo -e	 "\n\e[1mNow that you're done with this fallback server, you should check
your dns and be sure it points on your main server.\e[0m"
