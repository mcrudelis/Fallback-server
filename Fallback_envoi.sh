#/bin/bash

# Check root
CHECK_ROOT=$EUID
if [ -z "$CHECK_ROOT" ];then CHECK_ROOT=0;fi
if [ $CHECK_ROOT -ne 0 ]
then	# $EUID est vide sur une exécution avec sudo. Et vaut 0 pour root
   echo "Le script doit être exécuté avec les droits admin."
   exit 1
fi

if [ ! -e /usr/bin/7z ]
then
	echo "7z semble ne pas être installé. Merci d'installer le paquet p7zip-full."
	exit 1
fi
if [ ! -e /usr/bin/ccrypt ]
then
        echo "ccrypt semble ne pas être installé. Merci d'installer le paquet ccrypt."
        exit 1
fi

# Il faut éviter les espaces dans ARCHIVE_DIR, ça pose des soucis avec la boucle d'envoi
ARCHIVE_DIR="/media/data/Archives/Archives_fallback"
MIRROR_DIR="$ARCHIVE_DIR/Miroir"
LOGFILE="/var/log/fallback/fallback.log"

SSH_USER="fallback_sender"
SSH_HOST="NOM_DU_VPS"
SSH_KEY="/media/data/scripts/fallback/.ssh/fallback"
SSH_OPTION="-p PORT -C -i $SSH_KEY"


# ------------------------- #

####### Fonction de compression d'une archive.
COMPRESS () {
	echo "Compression de $1."
	tar -c -C "$MIRROR_DIR" -f "$ARCHIVE_DIR/$1.tar" "$1"	# On passe par une archive tar pour préserver les permissions de fichiers.
	7z a -t7z -ms=on -m0=LZMA2 -mx=9 -mhe=on "$ARCHIVE_DIR/$1.tar.7z" "$ARCHIVE_DIR/$1.tar" > /dev/null
	rm "$ARCHIVE_DIR/$1.tar"
}

####### Fonction de chiffrage des fichiers et archives.
CHIFFRAGE() {
	if [ -d "$ARCHIVE_DIR/$1" ]
	then
		echo "Chiffrage du dossier $1."
	else
		echo "Chiffrage du fichier $1."
	fi
	sudo ccrypt -ersfq -k compress "$ARCHIVE_DIR/$1"
}


####### Fonction de copie dans le dossier mirror. Pour compression et chiffrage ensuite.
COPY_COMPRESS () {
	# Créer une copie de $1 dans le dossier miroir. En remplaçant uniquement les fichiers modifiés en comparant les sommes de contrôle. Et vérifie qu'au moins 1 fichier à changé.
	# Copie les fichiers
	echo "\nCopie des fichiers modifiés de $1."
	rsync -acEhv --dry-run --delete --exclude="_/cache" "$1" "$MIRROR_DIR/"	# Le rsync dry-run est simplement informatif pour avoir la liste des modifications.
	rsync -acEh --stats --delete --exclude="_/cache" "$1" "$MIRROR_DIR/" > ../tmp/rsync_stats
	# Analyse le nombre de fichiers modifiés
	CREATED=$(cat ../tmp/rsync_stats | grep created | cut -d ':' -f 2 | cut -c2)
	DELETED=$(cat ../tmp/rsync_stats | grep deleted | cut -d ':' -f 2 | cut -c2)
	TRANSFERED=$(cat ../tmp/rsync_stats | grep transferred: | cut -d ':' -f 2 | cut -c2)
	# Affiche quelques infos sur le transfert.
	cat ../tmp/rsync_stats | grep "Total [f|t]"
	if [ $CREATED -ne 0 ] || [ $DELETED -ne 0 ] || [ $TRANSFERED -ne 0 ]
	then	# Les fichiers ont été modifiés, l'archive doit être refaite
		COMPRESS "$(basename $1)"
		CHIFFRAGE "$(basename $1).tar.7z"
	fi
}

####### Fonction de copie dans le dossier archive directement, sans passer par la compression.
COPY_ONLY () {
	# Créer une copie de $1 dans le dossier archive. En remplaçant uniquement les fichiers modifiés en comparant les sommes de contrôle.
	echo "\nCopie des fichiers modifiés de $1."
	rsync -acEhv --delete "$1" "$MIRROR_DIR/" > ../tmp/rsync_stats
	grep '^deleting ' ../tmp/rsync_stats | sed 's#^deleting ##g' > ../tmp/rsync_del	# Isole les lignes commençant par 'deleting ', en retirant la mention deleting
	sed -i '\#^deleting #d' ../tmp/rsync_stats	# Et supprime les lignes des fichiers supprimés.
	# Suppression des 3 lignes d'rsync dans le fichier d'origine
	sed -i '\#[a-z]*ing incremental file list#d' ../tmp/rsync_stats
	sed -i '\#sent.*bytes  received.*bytes.*bytes/sec#d' ../tmp/rsync_stats
	sed -i '\#total size is.*speedup is.*#d' ../tmp/rsync_stats
	while read file
	do	# Suppression des fichiers à supprimer dans le dossier chiffré.
		if [ -n "$file" ]
		then	# Ne traite pas les lignes vides
			if [ -d "$ARCHIVE_DIR/$file" ]
			then	# Si c'est un dossier
				echo "Suppression du dossier $file."
				sudo rmdir "$ARCHIVE_DIR/$file"
			else
				echo "Suppression du fichier $file."
				sudo rm "$ARCHIVE_DIR/$file.cpt"
			fi
		fi
	done < ../tmp/rsync_del
	while read file
	do	# Remplacement des fichiers modifiés dans le dossier chiffré.
		if [ -n "$file" ]
		then	# Ne traite pas les lignes vides
			if [ -d "$MIRROR_DIR/$file" ]
			then	# Si c'est un dossier
				if [ ! -e "$ARCHIVE_DIR/$file" ]
				then	# Et que ce dossier n'existe pas.
					echo "Création du dossier $file."
					sudo cp -a "$MIRROR_DIR/$file" "$ARCHIVE_DIR/$file"
				fi
			else	# Si c'est un fichier normal
				if [ -e "$ARCHIVE_DIR/$file.cpt" ]
				then	# Si le fichier existe, il est supprimé.
					sudo rm "$ARCHIVE_DIR/$file.cpt"
				fi
				echo "Copie du fichier $file."
				sudo cp -a "$MIRROR_DIR/$file" "$ARCHIVE_DIR/$file"
			fi
		fi
	done < ../tmp/rsync_stats
	CHIFFRAGE "$(basename $1)"
# 	echo "Création de la liste des propiétaires des fichiers."
# 	file=$(basename $1)/
# 	sudo find "$MIRROR_DIR/$(basename $1)" -printf "$(basename $1)/%P|:|%u|:|%g\n" > "$ARCHIVE_DIR/$(basename $1).perm"
}

####### Fonction d'extraction de bdd
EXTRACT_BDD () {
	echo "\nExtraction de la base de donnée $1."
	mysqldump -u save_script -pPASSWORD --databases --add-drop-database --add-drop-table "$1" > "$MIRROR_DIR/$1.sql"
	# Copie de la date du dump, pour la remettre en place ensuite.
	DATE_EXTRACT=$(cat "$MIRROR_DIR/$1.sql" | grep "^-- Dump completed on ")
	# Suppression de la date du dump, pour ne pas fausser la somme de contrôle.
	sed -i "s@^-- Dump completed on .*@-- Dump completed on ...@g" "$MIRROR_DIR/$1.sql"
	MD5=$(md5sum "$MIRROR_DIR/$1.sql" | cut -d' ' -f1)
	oldMD5=$(cat "$MIRROR_DIR/$1.md5")
	# Réécrit la somme de contrôle dans le fichier.
	echo $MD5 > "$MIRROR_DIR/$1.md5"
	# Remise en place de la date du dump
	sed -i "s@^-- Dump completed on ...@$DATE_EXTRACT@g" "$MIRROR_DIR/$1.sql"
	if [ "$MD5" != "$oldMD5" ]
	then	# Si les sommes de contrôle ne correspondent pas, la base de donnée a changé.
		COMPRESS "$1.sql"
		CHIFFRAGE "$1.sql.tar.7z"
	fi
}


####### Fonction listant les utilisateurs Yunohost
LISTE_USER() {
	echo "\nCréation de la liste des utilisateurs et de leurs caractéristiques."
	echo "" > $MIRROR_DIR/Liste_users

	# Extraction de la liste des utilisateurs Yunohost
	for user in $(sudo yunohost user list | grep -B1 "username:" | grep -v "username" |grep ":" | cut -d ':' -f1 | cut -d ' ' -f3)	# La liste est filtrée en prenant la ligne avant username. Puis en retirant la ligne username. Ensuite en gardant uniquement les lignes des noms d'user. Puis en gardant que le nom en lui même.
	do
		echo ">$user:" >> $MIRROR_DIR/Liste_users
		sudo yunohost user info $user >> $MIRROR_DIR/Liste_users
		echo "!>$user:" >> $MIRROR_DIR/Liste_users
	done
	# Vérifie si la liste d'user a changé.
	MD5=$(md5sum "$MIRROR_DIR/Liste_users" | cut -d' ' -f1)
	oldMD5=$(cat "$MIRROR_DIR/Liste_users.md5")
	# Réécrit la somme de contrôle dans le fichier.
	echo $MD5 > "$MIRROR_DIR/Liste_users.md5"
	if [ "$MD5" != "$oldMD5" ]
	then	# La liste d'utilisateurs a changé
		COMPRESS "Liste_users"
		CHIFFRAGE "Liste_users.tar.7z"
	fi

	# Extraction de la base de donnée ldap
	sudo slapcat -f /etc/ldap/slapd.conf -b dc=yunohost,dc=org -l "$MIRROR_DIR/ldap.ldif"
	# Vérifie si la base ldap a changé.
	MD5=$(md5sum "$MIRROR_DIR/ldap.ldif" | cut -d' ' -f1)
	oldMD5=$(cat "$MIRROR_DIR/ldap.ldif.md5")
	# Réécrit la somme de contrôle dans le fichier.
	echo $MD5 > "$MIRROR_DIR/ldap.ldif.md5"
	if [ "$MD5" != "$oldMD5" ]
	then	# La base ldap a changé
		COMPRESS "ldap.ldif"
		CHIFFRAGE "ldap.ldif.tar.7z"
	fi
}


####### Fonction d'envoi des archives sur le serveur fallback
ENVOI () {
	echo "Transfert des fichiers sur le serveur fallback"
	sudo rsync -azchEv --delete --exclude='Miroir' "$ARCHIVE_DIR/" -e "ssh $SSH_OPTION" $SSH_USER@$SSH_HOST:/upload
}

# ------------------------- #


####### MAIN
# Horodatage pour le log
echo "---" | tee -a "$LOGFILE" 2>&1
date | tee -a "$LOGFILE" 2>&1

## Liste des fichiers et dossiers à copier
# COPY_COMPRESS copie les fichiers dans MIRROR_DIR pour passer ensuite à la compression du dossier dans son ensemble.
# COPY_ONLY copie les fichiers dans MIRROR_DIR sans les compresser.
# EXTRACT_BDD extrait une base de donnée avant de la compresser.

# Mise à jour de la liste des utilisateurs Yunohost
LISTE_USER | tee -a "$LOGFILE" 2>&1

# Dossier mails
COPY_ONLY "/var/mail" | tee -a "$LOGFILE" 2>&1
echo "mail/:vmail:mail:-R" > "$ARCHIVE_DIR/mail.perm"
echo "mail/:root:mail:" >> "$ARCHIVE_DIR/mail.perm"

# Dossier metronome
COPY_ONLY "/var/lib/metronome" | tee -a "$LOGFILE" 2>&1
echo "metronome/:metronome:metronome:-R" > "$ARCHIVE_DIR/metronome.perm"

# Dossier CALDAV/CARDDAV
COPY_ONLY "/var/www/radicale/collections" | tee -a "$LOGFILE" 2>&1
echo "collections/:radicale:radicale:-R" > "$ARCHIVE_DIR/collections.perm"

# Dossier rainloop
COPY_COMPRESS "/var/www/rainloop" "/cache/" | tee -a "$LOGFILE" 2>&1

# Leed
EXTRACT_BDD leed | tee -a "$LOGFILE" 2>&1

# Teampass
COPY_ONLY "/etc/teampass/sk.php" | tee -a "$LOGFILE" 2>&1
echo "sk.php:root:www-data:" > "$ARCHIVE_DIR/sk.php.perm"
EXTRACT_BDD teampass | tee -a "$LOGFILE" 2>&1

# Envoi des archives chiffrées sur le serveur fallback
ENVOI | tee -a "$LOGFILE" 2>&1
