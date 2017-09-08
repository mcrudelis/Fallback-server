#!/bin/bash

if [ ! -e etape ]
then	# Si le fichier etape n'existe pas, on démarre par l'étape 1
	# La première connexion est en root
	# Mise à jour des paquets
	echo "Update et upgrade"
	apt-get update
	apt-get dist-upgrade

	# Pause
	read -p "Appuyer sur une touche pour continuer..."

	# Installer git
	apt-get install git

	# Pause
	read -p "Appuyer sur une touche pour continuer..."

	# Récupération du script d'install
	git clone https://github.com/YunoHost/install_script /tmp/install_script

	# Infos
	echo "Pour la postinstall, domaine crudelis.fr et mot de passe serveur"
	read -p "Appuyer sur une touche pour continuer..."

	# Exécution du script d'install Yunohost
	echo "Installation Yunohost"
	cd /tmp/install_script && ./install_yunohost

	# Pause
	read -p "Appuyer sur une touche pour continuer..."

	# Création de l'user maniack
	adduser maniack
	adduser maniack sudo

	## Modification de la config sshd
	echo "Modif conf ssh"
	sed -i "s@^Port 22$@@Port 22911@g" /etc/ssh/sshd_config
	sed -i "s@^PermitRootLogin yes$@@PermitRootLogin no@g" /etc/ssh/sshd_config
	sed -i "/^StrictModes yes$/ a\AllowUsers maniack fallback_sender" /etc/ssh/sshd_config

	# Ouverture du nouveau port ssh
	sudo yunohost firewall allow TCP 22911

	# Retour dans /root
	cd /root

	# Étape 1 terminée!
	echo "1" > etape

	# Copie du script dans /home/maniack
	cp Install_fallback.sh /home/maniack/
	cp etape /home/maniack/
	chown maniack: /home/maniack/{Install_fallback.sh,etape}

	# Infos
	echo "Connexion à présent avec ssh maniack@vps279266.ovh.net -p 22911"
	echo "Fin étape 1"
	read -p "Appuyer sur une touche pour continuer..."

	# Redémarrage du service ssh
	sudo service ssh restart
	exit 0	# On devrait s'être fait kické de toute manière...
fi

if [ -e etape ]
then	# Si le fichier etape existe, on va voir son contenu
	if [ $(cat etape) == "1" ]	# Si l'étape 1 est passée, on part sur l'étape 2.
	then
		# On retire le port 22
		sudo yunohost firewall disallow TCP 22

		# Ajout de l'user mcrudelis
		echo "Créer l'user mcrudelis sur Yunohost"
		sudo yunohost user create --firstname Maniack --mail maniack@crudelis.fr --lastname crudelis mcrudelis

		# Pause
		read -p "Appuyer sur une touche pour continuer..."

		echo "Montage du disque additionnel"
		## Monter le disque externe
		sudo mkdir /media/disque_sup
		# Formater le disque:
		sudo mkfs.ext4 /dev/vdb
		# Identifier le UUID
# 		uuid=$(sudo blkid | grep /dev/vdb | cut -d "\"" -f 2)
		# Ajouter la ligne de montage dans fstab
# 		echo "UUID=$uuid  /media/disque_sup  ext4 auto,user,rw,exec,suid  0       2" | sudo tee -a /etc/fstab
		echo "/dev/vdb  /media/disque_sup  ext4 auto,user,rw,exec,suid  0       2" | sudo tee -a /etc/fstab
		sudo mount -a
		# Et on vérifie que tout est bon.
		df -h

		# Pause
		read -p "Appuyer sur une touche pour continuer..."

		# Enfin, on met un mount_bind sur le home de l'user fallback.
		sudo mkdir /media/disque_sup/fallback_sender
		sudo mkdir /home/fallback_sender
		echo "/media/disque_sup/fallback_sender        /home/fallback_sender none bind,default,auto    0       0" | sudo tee -a /etc/fstab
		sudo mount -a

		# Pause
		read -p "Appuyer sur une touche pour continuer..."

		echo "Chroot fallback_sender"
		## Création du chroot de l'user fallback_sender
		sudo addgroup fallback_sender
		sudo useradd fallback_sender --gid fallback_sender -m --shell /bin/false
		sudo cp -a /etc/skel/. /home/fallback_sender
		sudo chown fallback_sender: -R /home/fallback_sender
		sudo chown root: /home/fallback_sender
		sudo mkdir /home/fallback_sender/{upload,fallback_work,vacuum}
		sudo chown fallback_sender: -R /home/fallback_sender/upload
		sudo mkdir /home/fallback_sender/{bin,lib,lib64}

		echo "Copie des binaires dans le chroot"
		# Copie des exécutables bash et rsync dans le chroot
		sudo cp `which bash` /home/fallback_sender/bin/bash
		sudo cp `which rsync` /home/fallback_sender/bin/rsync
		ldd `which bash` `which rsync`	# Pour info
		sudo cp /lib/x86_64-linux-gnu/libncurses.so.5 /home/fallback_sender/lib/
		sudo cp /lib/x86_64-linux-gnu/libtinfo.so.5 /home/fallback_sender/lib/
		sudo cp /lib/x86_64-linux-gnu/libdl.so.2 /home/fallback_sender/lib/
		sudo cp /lib/x86_64-linux-gnu/libc.so.6 /home/fallback_sender/lib/
		sudo cp /lib/x86_64-linux-gnu/libattr.so.1 /home/fallback_sender/lib/
		sudo cp /lib/x86_64-linux-gnu/libacl.so.1 /home/fallback_sender/lib/
		sudo cp /lib/x86_64-linux-gnu/libpopt.so.0 /home/fallback_sender/lib/
		sudo cp /lib64/ld-linux-x86-64.so.2 /home/fallback_sender/lib64/

		# Pause
		read -p "Appuyer sur une touche pour continuer..."

		# Script pour brider le shell de fallback_sender
		echo "#!/bin/bash" | sudo tee /home/fallback_sender/bin/fakeshell
		echo "if (( \$# == 0 )); then        # L'accès n'est pas autorisé si il n'y a pas d'arguments" | sudo tee -a /home/fallback_sender/bin/fakeshell
		echo "        echo \"L\'accès au shell n\'est pas autorisé.\"" | sudo tee -a /home/fallback_sender/bin/fakeshell
		echo "        exit 1" | sudo tee -a /home/fallback_sender/bin/fakeshell
		echo "elif (( \$# == 2 )) && [[ \$1 == \"-c\" && \$2 == \"rsync --server\"* ]]; then" | sudo tee -a /home/fallback_sender/bin/fakeshell
		echo "        exec \$2        # Autorise uniquement l\'exécution de rsync --server" | sudo tee -a /home/fallback_sender/bin/fakeshell
		echo "fi" | sudo tee -a /home/fallback_sender/bin/fakeshell

		# Le script devient exécutable
		sudo chmod +x /home/fallback_sender/bin/fakeshell
		# Et devient le shell de l'user fallback_sender
		sudo usermod -s /bin/fakeshell fallback_sender

		# On ajoute le chroot pour l'user fallback_sender
		echo -e "\nMatch User fallback_sender" | sudo tee -a /etc/ssh/sshd_config
        echo -e "\tChrootDirectory /home/%u" | sudo tee -a /etc/ssh/sshd_config
        echo -e "\tAllowTcpForwarding no" | sudo tee -a /etc/ssh/sshd_config
        echo -e "\tX11Forwarding no" | sudo tee -a /etc/ssh/sshd_config

		# Pause
		read -p "Appuyer sur une touche pour continuer..."

		# Étape 2 terminée!
		echo "2" > etape

		# Infos
		echo "Il faut copier la clé ssh sur le serveur fallback depuis servus"
		echo "sudo scp -P 22911 /media/data/scripts/fallback/.ssh/fallback.pub maniack@vps279266.ovh.net:authorized_keys"
		echo "Fin étape 2"
		read -p "Appuyer sur une touche pour continuer..."
		exit 0
	fi
	if [ $(cat etape) == "2" ]	# Si l'étape 2 est passée, on part sur l'étape 3.
	then
		# Mise en place de la clé ssh
		echo "Mise en place de la clé ssh"
		sudo mkdir /home/fallback_sender/.ssh
		sudo mv authorized_keys /home/fallback_sender/.ssh/
		sudo chown fallback_sender: -R /home/fallback_sender/.ssh/
		# Et bridage de la clé
		sudo sed -i 's/^.*/from="192.168.1.150",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty &/g' /home/fallback_sender/.ssh/authorized_keys
		sudo service ssh reload

		# Pause
		read -p "Appuyer sur une touche pour continuer..."

		# Modification de la page du portail
		echo "<center>Bonjour, bienvenue sur le serveur fallback</p>En cas de difficulté pour s'identifier, contactez l'administrateur.</center>" | sudo tee -a /usr/share/ssowat/portal/login.html

		echo "Installation de phpmyadmin"
		# Installation de phpmyadmin
		sudo yunohost --verbose app install https://github.com/YunoHost-apps/phpmyadmin_ynh

		# Pause
		read -p "Appuyer sur une touche pour continuer..."

		# Création de l'user save_script avec uniquement les droits LOCK TABLE et SELECT.
		echo "Création de l'user save_script sur mysql"
		mysql -u root -p$(sudo cat /etc/yunohost/mysql) -e "CREATE USER 'save_script'@'localhost' IDENTIFIED BY 'CXefyn508XDtXD5X' ; GRANT SELECT, LOCK TABLES ON *.* TO 'save_script'@'localhost' ; FLUSH PRIVILEGES ; SHOW GRANTS FOR 'save_script'@'localhost' ;"

		# Pause
		read -p "Appuyer sur une touche pour continuer..."

		# Installation des applications à synchroniser
		echo "Installation de radicale"
		sudo yunohost --verbose app install https://github.com/YunoHost-Apps/radicale_ynh
		# Pause
		read -p "Appuyer sur une touche pour continuer..."
		echo "Installation de rainloop"
		sudo yunohost --verbose app install https://github.com/YunoHost-Apps/rainloop_ynh
		# Pause
		read -p "Appuyer sur une touche pour continuer..."
		echo "Installation de leed"
		sudo yunohost --verbose app install https://github.com/YunoHost-Apps/leed_ynh
		# Pause
		read -p "Appuyer sur une touche pour continuer..."
		echo "Installation de teampass"
		sudo yunohost --verbose app install https://github.com/YunoHost-Apps/teampass_ynh
		# Pause
		read -p "Appuyer sur une touche pour continuer..."

		# Étape 3 terminée!
		echo "3" > etape

		# Infos
		echo "Il faut copier les scripts sur le serveur fallback depuis servus"
		echo "sudo scp -P 22911 /media/data/scripts/fallback/Scripts\ serveur\ fallback/*.sh maniack@vps279266.ovh.net:"
		echo "Fin étape 3"
		read -p "Appuyer sur une touche pour continuer..."
		exit 0
	fi
	if [ $(cat etape) == "3" ]	# Si l'étape 3 est passée, on part sur l'étape 4.
	then
		# Rend les scripts exécutable
		sudo chmod +x *.sh

		echo "Installation de 7zip et ccrypt"
		# Installe les paquets p7zip-full et ccrypt
		sudo apt-get install p7zip-full ccrypt

		# Pause
		read -p "Appuyer sur une touche pour continuer..."

		# Créer le lien symbolique pour la config ldap
# 		sudo ln -s /etc/ldap/slapd-yuno.conf /etc/ldap/slapd.conf

		# Étape 4 terminée!
		echo "4" > etape

		# Infos
		echo "La mise en place du fallback est terminée."
		echo "On peut maintenant faire un premier envoi, qui va être très long..."
		echo "Script Fallback_envoi.sh"
		echo "Après le premier envoi, il faudra faire un essai de déployement pour vérifier que tout fonctionne, et pour créer les users Yunohost"
		echo ""
		echo "Fin étape 4"
		echo ""
		echo "Avec un peu de courage, il reste encore l'étape 5 avec la mis en place du certificat."
		read -p "Appuyer sur une touche pour continuer..."
		exit 0
	fi
	if [ $(cat etape) == "4" ]	# Si l'étape 4 est passée, on part sur l'étape 5.
	then
		echo "Bascule l'IP sur le fallback pour le certificat"
		# Bascule l'ip sur le fallback
		./Bascule_DynHost_IP.sh
		# Installation du package lets-encrypt
		sudo yunohost --verbose app install https://github.com/YunoHost-Apps/letsencrypt_ynh

		# Pause
		read -p "Appuyer sur une touche pour continuer..."

		echo "Fin étape 5"
		echo "Si tout va bien, tout est terminé."
		echo "Il faut toutefois exécuter le script Bascule_DynHost_IP.sh sur servus pour récupérer la redirection du domaine."
		read -p "Appuyer sur une touche pour continuer..."

		rm etape
		sudo rm /root/etape

		exit 0
	fi
fi
