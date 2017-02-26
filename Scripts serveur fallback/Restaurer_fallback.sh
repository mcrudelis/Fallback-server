#/bin/bash

# Check root
CHECK_ROOT=$EUID
if [ -z "$CHECK_ROOT" ];then CHECK_ROOT=0;fi
if [ $CHECK_ROOT -ne 0 ]
then	# $EUID est vide sur une exécution avec sudo. Et vaut 0 pour root
   echo "Le script doit être exécuté avec les droits admin"
   exit 1
fi

if [ ! -e /usr/bin/7z ]
then
	echo "7z semble ne pas être installé. Merci d'installer le paquet p7zip-full."
	exit 1
fi

# Il faut éviter les espaces dans ARCHIVE_DIR, ça pose des soucis avec la boucle d'envoi
VACUUM="/home/fallback_sender/vacuum"
LOG="./fallback_restore.log"

# ------------------------- #

####### Fonction restaurant la copie VACUUM pour effacer les données.
COPY_VACUUM () {
	echo "Suppression des données de $1"
	sudo rm -r --preserve-root "$1"
	echo "Restauration de l'état précédent des fichiers de $1."
	sudo mv "$VACUUM/$(basename $1)" "$1"
}

####### Fonction restaurant la base de donnée VACUUM pour effacer les données.
COPY_VACUUM_SQL () {
	echo "Restauration de l'état précédent de la base de donnée $1."
	mysql -h localhost -u root -p$(sudo cat /etc/yunohost/mysql) < "$VACUUM/$1.sql"
	sudo rm "$VACUUM/$1.sql"
}

####### Fonction de compression de dossier
COMPRESS () {
	echo "\n--\nCompression de $1."
	file=$(basename $1)
	tar -c -f "extract_data/$file.tar" "$1"	# On passe par une archive tar pour préserver les permissions de fichiers.
	7z a -t7z -ms=on -m0=LZMA2 -mx=9 -mhe=on "extract_data/$file.tar.7z" "extract_data/$file.tar" > /dev/null
	rm "extract_data/$file.tar"
	COPY_VACUUM $1
}

####### Fonction d'extraction de bdd
EXTRACT_BDD () {
	echo "\n--\nExtraction de la base de donnée $1."
	mysqldump -u save_script -pPASSWORD --databases --add-drop-database --add-drop-table "$1" > "extract_data/$1.sql"
	7z a -t7z -ms=on -m0=LZMA2 -mx=9 -mhe=on "extract_data/$1.sql.7z" "extract_data/$1.sql" > /dev/null
	rm "extract_data/$1.sql"
	COPY_VACUUM_SQL $1
}

####### Fonction restaurant la base ldap dans son ensemble.
LDAP_RESTORE() {
	# On se connecte en root pour l'opération, car l'arrêt du service empêchera l'usage de sudo
	echo "\n--\nConnection au compte root"
	su root -c "echo \"Arrêt du service ldap\" ;\
		service slapd stop ;\
		echo \"Récupération de la base ldap\" ;\
		slapcat -f /etc/ldap/slapd.conf -b dc=yunohost,dc=org -l \"extract_data/ldap.ldif\" ;\
		echo \"Suppression de la base ldap actuelle\" ;\
		rm -r /var/lib/ldap/* ;\
		echo \"Restauration de la base ldap\" ;\
		slapadd -b dc=yunohost,dc=org -l \"$VACUUM/ldap.ldif\" ;\
		echo \"Restauration des droits de ldap sur les fichiers restaurés\" ;\
		chown -R openldap: /var/lib/ldap ;\
		echo \"Redémarrage du service ldap\" ;\
		service slapd start ;"
	rm "$VACUUM/ldap.ldif"
}

# ------------------------- #

####### MAIN
# Horodatage pour le log
echo "---" | tee -a "$LOG" 2>&1
date | tee -a "$LOG" 2>&1

## Liste des fichiers et dossiers à copier
# COMPRESS compresse les fichier, puis restaure les fichiers VACUUM
# EXTRACT_BDD extrait une base de donnée avant de la compresser, puis restaure la bdd VACUUM

mkdir -p extract_data

# Dossier mails
COMPRESS "/var/mail" | tee -a "$LOG" 2>&1

# Dossier metronome
COMPRESS "/var/lib/metronome" | tee -a "$LOG" 2>&1

# Dossier CALDAV/CARDDAV
COMPRESS "/var/www/radicale/collections" | tee -a "$LOG" 2>&1

# Dossier rainloop
COMPRESS "/var/www/rainloop" | tee -a "$LOG" 2>&1

# Leed
EXTRACT_BDD leed | tee -a "$LOG" 2>&1

# Teampass
COMPRESS "/etc/teampass/sk.php" | tee -a "$LOG" 2>&1
EXTRACT_BDD teampass | tee -a "$LOG" 2>&1

# Ldap
LDAP_RESTORE | tee -a "$LOG" 2>&1
