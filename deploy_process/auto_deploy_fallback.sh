#!/bin/bash

# And also a delay between the check !?
	# Delay could be define from the delay.

#=================================================
# GET THE SCRIPT'S DIRECTORY
#=================================================

script_dir="$(dirname $(realpath $0))"

#=================================================
# SET VARIABLES
#=================================================

# Usually the backup directory is the home directory of the ssh user
local_archive_dir="/home/USER/backup"
decrypted_dir="$local_archive_dir/decrypted"
pass_file="$decrypted_dir/pass"

incident=0

ip_main_server=$(cat "$local_archive_dir/ip_main_server")

type_of_exec=$1

#=================================================
# REGULAR_CHECK
#=================================================

# Detect a failure of the main server
if [ "$type_of_exec" = "regular_check" ]
then
	#=================================================
	# CHECK THE CONNECTION TO THE MAIN SERVER
	#=================================================
	# If ping fails
	if ! ping -q -c5 $ip_main_server > /dev/null
	then
		# Get the first failure of ping, or set at the current time
		first_failure=$(cat "$script_dir/first_failure" || date +%s)
		if [ -e "$script_dir/first_failure" ]
		then
			echo "$first_failure" > "$script_dir/first_failure"
		fi

		# Get the time before declaring the failure as an incident
		delay_before_incident=$(grep "^delay_before_incident=" "$script_dir/auto_check.conf" | cut -d'=' -f2)

		delay_since_first_failure=$(( ($(date +%s) - $first_failure) / 3600))
		if [ "$delay_since_first_failure" -ge "$delay_before_incident" ]
		then
			incident=1
		fi
	else
		# If ping succeeds, remove the failure file
		rm -f "$script_dir/first_failure"
	fi

	if [ $incident -eq 1 ]
	then
		#=================================================
		# DECLARE AN INCIDENT
		#=================================================

		# Send an email to inform that there's an incident
		# Get the email
		contact_mail=$(grep "^contact_mail=" "$script_dir/auto_check.conf" | cut -d'=' -f2)

		# Get authorisation to auto deploy the fallback
		auto_deploy=$(grep "^auto_deploy=" "$script_dir/auto_check.conf" | cut -d'=' -f2)

		# Build the message to send
		mail_notification="The server, usually available at $ip_main_server, is not reachable since $(date --date=@$first_failure)."
		if [ $auto_deploy -eq 1 ]
		then
			mail_notification="$mail_notification
The fallback server is going to be deployed.
An email will be send as soon as the main server will be back online."
		else
			mail_notification="$mail_notification
To deploy your fallback, please use the script $script_dir/deploy_fallback.sh"
		fi

		# Send the email
		echo "$mail_notification" | mail -a "Content-Type: text/plain; charset=UTF-8" -s "$ip_main_server unavailable" "$contact_mail"

		#=================================================
		# ACTIVATE CHECKS OF AVAILABILITY OF THE MAIN SERVER
		#=================================================

		# Deactive regular check to detect a failure of the server.
		sed -i "s/.*regular_check/#&/" /etc/cron.d/auto_deploy_fallback
		# Active the check to detect if the server is back online.
		sed -i "s/#\(.*post_failure_check\)/\1/" /etc/cron.d/auto_deploy_fallback

		#=================================================
		# FALLBACK AUTO DEPLOYEMENT
		#=================================================

		if [ $auto_deploy -eq 1 ]
			"$script_dir/deploy_fallback.sh" auto > "$script_dir/auto_deploy.log"
			fallback_success=$?
			cat "$script_dir/auto_deploy.log" | mail -a "Content-Type: text/plain; charset=UTF-8" -s "Auto deployement of the fallback for $ip_main_server" "$contact_mail"
		fi

		# Get authorisation to modify the DNS
		auto_update_DNS=$(grep "^auto_update_DNS=" "$script_dir/auto_check.conf" | cut -d'=' -f2)
		# And the script to use to do it
		auto_update_script=$(grep "^auto_update_script=" "$script_dir/auto_check.conf" | cut -d'=' -f2)

		# Update the DNS if it's allowed and if deploy_fallback hasn't failed.
		if [ $fallback_success -eq 0 ] && [ $auto_update_DNS -eq 1 ]
		then
			# Use the script to update the DNS with the IP of the fallback
			"$auto_update_script"
		fi
	fi
fi


#=================================================
# POST_FAILURE_CHECK
#=================================================

# Detect if the main server is back online
if [ "$type_of_exec" = "post_failure_check" ]
then
	#=================================================
	# CHECK THE CONNECTION TO THE MAIN SERVER
	#=================================================
	# If ping succeed
	if ping -q -c5 $ip_main_server > /dev/null
	then
		# The main server is back online

		# Remove the failure file
		rm -f "$script_dir/first_failure"

		#=================================================
		# DECLARE THE END OF THE INCIDENT
		#=================================================

		# Get the email
		contact_mail=$(grep "^contact_mail=" "$script_dir/auto_check.conf" | cut -d'=' -f2)

		# Build the message to send
		mail_notification="The main server, available at $ip_main_server, is back online \o/
If you've deployed your fallback, please use the script $script_dir/close_fallback.sh to return this server to its sleeping mode"

		# Send the email
		echo "$mail_notification" | mail -a "Content-Type: text/plain; charset=UTF-8" -s "$ip_main_server back online" "$contact_mail"

		#=================================================
		# RESTORE REGULAR_CHECK
		#=================================================

		# Reactive regular check to detect a failure of the server.
		sed -i "s/#\(.*regular_check\)/\1/" /etc/cron.d/auto_deploy_fallback
		# Deactive the check to detect if the server is back online.
		sed -i "s/.*post_failure_check/#&/" /etc/cron.d/auto_deploy_fallback
	fi
fi
