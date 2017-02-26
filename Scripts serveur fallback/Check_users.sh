#/bin/bash

WORK_DIR="$1"
VACUUM="$2"
LOG="$3"

####### Fonction listant les utilisateurs Yunohost
LISTE_USER() {
	echo "Création de la liste des utilisateurs locaux."
	echo "" > "$WORK_DIR/Liste_local_users"	# Vide la liste locale
	# Extraction de la liste des utilisateurs Yunohost
	for user in $(sudo yunohost user list | grep -B1 "username:" | grep -v "username" |grep ":" | cut -d ':' -f1 | cut -d ' ' -f3)	# La liste est filtrée en prenant la ligne avant username. Puis en retirant la ligne username. Ensuite en gardant uniquement les lignes des noms d'user. Puis en gardant que le nom en lui même.
	do
# 		echo "$user"
		echo ">$user:" >>  "$WORK_DIR/Liste_local_users"
	done
}

####### Fonction d'extraction des données utilisateur
EXTRACT_USER() {
	EXTRACT_USERNAME=$(cat "$WORK_DIR/Liste_users" | grep -A1 "$1" | sed -n 2p | sed 's/username: //')
	EXTRACT_FIRSTNAME=$(cat "$WORK_DIR/Liste_users" | grep -A2 "$1" | sed -n 3p | sed 's/firstname: //')
	EXTRACT_LASTNAME=$(cat "$WORK_DIR/Liste_users" | grep -A3 "$1" | sed -n 4p | sed 's/lastname: //')
	EXTRACT_QUOTA=$(cat "$WORK_DIR/Liste_users" | grep -A7 "$1" | sed -n '5,7 p')
	if [ $(echo "$EXTRACT_QUOTA" | grep -c "No quota") -eq 1 ]
	then
		EXTRACT_QUOTA=0
	else
		EXTRACT_QUOTA=$(echo "$EXTRACT_QUOTA" | grep "limit" | sed 's/  limit: //')
	fi
	EXTRACT_ALIASES=$(cat "$WORK_DIR/Liste_users" | sed -n "/$1/,/\!$1/p" | grep " - .*@" | sed 's/  - //')
	EXTRACT_MAIL=$(cat "$WORK_DIR/Liste_users" | grep -B2 "\!$1" | sed -n 1p | sed 's/mail: //')
	EXTRACT_FULLNAME=$(cat "$WORK_DIR/Liste_users" | grep -B1 "\!$1" | sed -n 1p | sed 's/fullname: //')
# echo EXTRACT_USERNAME=$EXTRACT_USERNAME.
# echo EXTRACT_FIRSTNAME=$EXTRACT_FIRSTNAME.
# echo EXTRACT_LASTNAME=$EXTRACT_LASTNAME.
# echo EXTRACT_QUOTA=$EXTRACT_QUOTA.
# echo EXTRACT_ALIASES=$EXTRACT_ALIASES.
# echo EXTRACT_MAIL=$EXTRACT_MAIL.
# echo EXTRACT_FULLNAME=$EXTRACT_FULLNAME.
}

####### Fonction d'ajout d'utilisateur
ADD_USER() {
	echo "Ajout de l'utilisateur $1." | tee -a "$LOG" 2>&1
	EXTRACT_USER $1
	sudo yunohost user create --firstname "$EXTRACT_FIRSTNAME" --mail "$EXTRACT_MAIL" --lastname "$EXTRACT_LASTNAME" --password $(cat /dev/urandom | head -n20 | tr -c -d 'A-Za-z0-9' | head -c20) $EXTRACT_USERNAME
	# Le mot de passe, impossible à récupérer sur la base ldap est ici généré aléatoirement. Il sera remplacé par la restauration de la base ldap.
}

####### Fonction de suppression d'utilisateur
SUPPR_USER() {
	mod1=$( echo "$1" | cut -d'>' -f2 | cut -d':' -f1)
	echo "Suppression de l'utilisateur $mod1." | tee -a "$LOG" 2>&1
	sudo yunohost user delete --purge $mod1
}

####### Fonction comparant les utilisateurs Yunohost entre le serveur d'origine et le fallback
COMPARE_USER() {
	# Tout d'abord, vérifie si un utilisateur a été supprimé sur le serveur d'origine
	for user in $(cat "$WORK_DIR/Liste_local_users" | grep "^>.*:")	# Liste les utilisateurs présent dans la liste du serveur fallback.
	do
		if [ $(cat "$WORK_DIR/Liste_users" | grep -c $user) -eq 0 ]
		then	# Si un utilisateur existe sur le fallback, mais pas sur le serveur d'origine. L'user doit être supprimé du fallback.
 			SUPPR_USER $user
		fi
	done
	# Ensuite, vérifie la présence des utilisateurs sur le serveur fallback.
	for user in $(cat "$WORK_DIR/Liste_users" | grep "^>.*:")	# Liste les utilisateurs présent dans la liste d'origine.
	do
		if [ $(cat "$WORK_DIR/Liste_local_users" | grep -c $user) -eq 0 ]
		then	# Si un utilisateur existe sur le serveur d'origine, mais pas sur le serveur fallback. L'user doit être créé sur le fallback.
 			ADD_USER $user
		fi
	done
	rm "$WORK_DIR/Liste_users" "$WORK_DIR/Liste_local_users"
}

####### Fonction restaurant la base ldap dans son ensemble.
LDAP_RESTORE() {
	# On se connecte en root pour l'opération, car l'arrêt du service empêchera l'usage de sudo

	if [ ! -e "$VACUUM/ldap.ldif" ]
	then
		echo "Archivage des anciens fichiers ldap"
		slapcat -f /etc/ldap/slapd.conf -b dc=yunohost,dc=org -l "$VACUUM/ldap.ldif"
	fi
	echo "\nConnection au compte root"
	su root -c "echo \"Arrêt du service ldap\" ;\
		service slapd stop ;\
		echo \"Suppression de la base ldap actuelle\" ;\
		rm -r /var/lib/ldap/* ;\
		echo \"Restauration de la base ldap\" ;\
		slapadd -b dc=yunohost,dc=org -l \"$WORK_DIR/ldap.ldif\" ;\
		echo \"Restauration des droits de ldap sur les fichiers restaurés\" ;\
		chown -R openldap: /var/lib/ldap ;\
		echo \"Redémarrage du service ldap\" ;\
		service slapd start ;"
	rm "$WORK_DIR/ldap.ldif"
}

LISTE_USER | tee -a "$LOG" 2>&1
COMPARE_USER
LDAP_RESTORE | tee -a "$LOG" 2>&1
