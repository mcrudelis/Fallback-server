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
if [ ! -e /usr/bin/ccrypt ]
then
        echo "ccrypt semble ne pas être installé. Merci d'installer le paquet ccrypt."
        exit 1
fi

# Il faut éviter les espaces dans ARCHIVE_DIR, ça pose des soucis avec la boucle d'envoi
UPLOAD_DIR="/home/fallback_sender/upload"
WORK_DIR="/home/fallback_sender/fallback_work"
VACUUM="/home/fallback_sender/vacuum"
LOG="./fallback_deploy.log"

# ------------------------- #

####### Fonction assurant une copie de sauvegarde des fichiers avant mise en place du fallback. Afin de garder une version "vide" de l'installation.
COPY_VACUUM () {
	echo "Copie de sauvegarde de l'état précédent des fichiers de $2."
	if [ ! -e "$VACUUM/$1" ]
	then # Si un dossier est déjà sauvegardé, la copie n'est pas refaite. Pour ne pas perdre les fichiers d'origine.
		if [ -d "$2" ]
		then
			file="$2/."
		else
			file="$2"
		fi
		sudo cp -a "$file" "$VACUUM/$1"
	fi
}

####### Fonction de copie des fichiers à leurs nouveaux emplacements.
TRAITEMENT () {
	COPY_VACUUM "$1" "$2"
	# Copie les fichiers
	echo "Mise en place des nouveaux fichiers pour $1."
	if [ -d "$WORK_DIR/$1" ]
	then
		file="$1/"
	else
		file="$1"
	fi
	rsync -ah --stats --delete "$WORK_DIR/$file" "$2" > $WORK_DIR/rsync_stats
	# Affiche quelques infos sur le transfert.
	cat $WORK_DIR/rsync_stats | grep "transferred:"
	cat $WORK_DIR/rsync_stats | grep "Total [f|t]"
	echo "Suppression des fichiers déchiffrés, après copie."
	rm -r "$WORK_DIR/$1"
}

####### Fonction d'import de bdd
IMPORT_BDD () {
	EXTRACTION $1.sql NO_TRAITEMENT
	echo "Copie de sauvegarde de l'état précédent de la base de donnée $1."
	mysqldump -u save_script -pPASSWORD --databases --add-drop-database --add-drop-table "$1" > "$VACUUM/$1.sql"
	echo "Import de la base de donnée $1."
	mysql -h localhost -u root -p$(sudo cat /etc/yunohost/mysql) < "$WORK_DIR/$1.sql"
	echo "Suppression des fichiers déchiffrés, après copie."
	rm -r "$WORK_DIR/$1.sql"
}

####### Fonction de déchiffrage des dossiers et archives du dossier UPLOAD_DIR
DECHIFFRAGE () {
	if [ -d "$WORK_DIR/$1" ]
	then
		echo "Déchiffrage du dossier $1."
		ccrypt -drfq -k extract "$WORK_DIR/$1"
	else
		echo "Déchiffrage du fichier $1."
		ccrypt -dfq -k extract "$WORK_DIR/$1.cpt"
	fi
	if [ "$?" -ne "0" ]
	then
		echo "Erreur de déchiffrage! Impossible de continuer."
		touch EXIT
		exit 1
	fi
}

####### Fonction assurant le rétablissement des permissions, précédemment anéanties par rsync.
PERMISSIONS () {
	echo "Rétablissement des permissions sur $1"
	while read file_mod
	do	# Lit les lignes du fichier de permissions
		file=$(echo "$file_mod" | cut -d':' -f1)
		owner=$(echo "$file_mod" | cut -d':' -f2)
		group=$(echo "$file_mod" | cut -d':' -f3)
		option=$(echo "$file_mod" | cut -d':' -f4)
		sudo chown $option $owner:$group "$WORK_DIR/$file"
	done < "$UPLOAD_DIR/$1.perm"
}

####### Fonction de copie dans le WORK_DIR
COPY_CRYPT () {
	echo "\n--\nCopie de $1"
	if [ -e "$UPLOAD_DIR/$1" ]
	then
		sudo cp -a "$UPLOAD_DIR/$1" "$WORK_DIR/"
	else	# Si le fichier n'existe pas, il faut copier la version chiffrée.
		sudo cp -a "$UPLOAD_DIR/$1.cpt" "$WORK_DIR/"
	fi
	DECHIFFRAGE "$1"
	# Rétablissement des permissions sur les fichiers en copie direct.
	PERMISSIONS "$1"
	if [ $(echo "$2" | grep -c "^NO_TRAITEMENT$") -eq 0 ]
	then	# Si $2 contient NO_TRAITEMENT, on saute cette étape.
		TRAITEMENT "$1" "$2"
	fi
}

####### Fonction de décompression
EXTRACTION () {
	echo "\n--\n"
	sudo cp -a "$UPLOAD_DIR/$1.tar.7z.cpt" "$WORK_DIR/"
	DECHIFFRAGE "$1.tar.7z"
	if [ $? -eq 1 ]
	then
		exit 1
	fi
	echo "Extraction de $1.tar.7z"
	7z e -aoa "$WORK_DIR/$1.tar.7z" -o"$WORK_DIR/"
	tar -x -C "$WORK_DIR" -f "$WORK_DIR/$1.tar"
	rm "$WORK_DIR/$1.tar"
	if [ $(echo "$2" | grep -c "^NO_TRAITEMENT$") -eq 0 ]
	then	# Si $2 contient NO_TRAITEMENT, on saute cette étape.
		TRAITEMENT "$1" "$2"
	fi
	sudo rm "$WORK_DIR/$1.tar.7z"
}

# ------------------------- #

# Stockage du mot de passe de déchiffrage.
echo -n "Mot de passe de déchiffrage: "
stty -echo
read mdp
stty echo
echo $mdp | tee extract > /dev/null
mdp=NULL
chmod 400 extract
echo "\n\n"

date | tee "$LOG" 2>&1

## Liste des fichiers et dossiers à copier
# COPY_CRYPT déchiffre un dossier non compressé et le copie dans WORK_DIR.
# EXTRACTION déchiffre une archive, puis la décompresse dans WORK_DIR.
# IMPORT_BDD déchiffre une base de donnée, la décompresse, puis l'importe.

# Liste users
EXTRACTION ldap.ldif NO_TRAITEMENT | tee -a "$LOG" 2>&1

# LDAP
EXTRACTION Liste_users NO_TRAITEMENT | tee -a "$LOG" 2>&1

if [ -e EXIT ]
then	# Erreur de déchiffrage
	rm EXIT
	exit 1
fi

sudo ./Check_users.sh "$WORK_DIR" "$VACUUM" "$LOG"	# Les commandes d'admin (celles demandant le mot de passe admin, pas root) yunohost ne supportent pas le pipe... Ça provoque une erreur "NotImplementedError: this signal is not handled"

# Dossier mails
COPY_CRYPT mail "/var/mail" | tee -a "$LOG" 2>&1

# Dossier metronome
sudo service metronome stop | tee -a "$LOG" 2>&1
COPY_CRYPT metronome "/var/lib/metronome" | tee -a "$LOG" 2>&1
sudo service metronome start | tee -a "$LOG" 2>&1

# Dossier CALDAV/CARDDAV
COPY_CRYPT collections "/var/www/radicale/collections" | tee -a "$LOG" 2>&1

# Dossier rainloop
EXTRACTION rainloop "/var/www/rainloop" | tee -a "$LOG" 2>&1

# Leed
IMPORT_BDD leed | tee -a "$LOG" 2>&1

# Teampass
COPY_CRYPT sk.php "/etc/teampass/sk.php" | tee -a "$LOG" 2>&1
IMPORT_BDD teampass | tee "$LOG" 2>&1

rm extract | tee -a "$LOG" 2>&1
