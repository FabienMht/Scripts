#!/bin/bash

# ------------------------------------------------------------------
#			Definition des fonctions
# ------------------------------------------------------------------

# Fonction qui verifie la configuration
function check_conf () {

  # Chargement du fichier de configuration du script
  CONFIG_script="./config_mysql_recovery.conf"
  
  if [ -e "$CONFIG_script" ];then
    source "$CONFIG_script"
  else
    echo "Le fichier de configuration du script definie par CONFIG_script est manquant !"
    exit 1
  fi

  # Test si les variables du fichier de configuration sont definies
  if [ ! -e $DB_config_file ]
  then
    echo "Le fichier de configuration de mysql n existe pas : $DB_config_file"
    exit 1
  fi
  if [ -z "$MYSQL_Backup_folder" ];then
    echo "Le chemin du dossier de sauvegarde de mysql n est pas definie : MYSQL_Backup_folder"
    exit 1 
  fi
  
  # Verification parametre SSH
  if [ -z "$ssh_user" ];then
    echo "L utilisateur ssh n est pas specifier : ssh_user"
    exit 1
  fi
  if [ -z "$ssh_host" ];then
    echo "Le serveur ssh n est pas specifier : ssh_host"
    exit 1
  fi
  if [ -z "$ssh_public_key" ];then
    echo "Le chemin de la cle public n est pas specifier : ssh_public_key"
    exit 1
  fi
  if [ -z "$ssh_path_tmp" ];then
    echo "Le repertoire temporaire du client n est pas specifier : ssh_path_tmp"
    exit 1
  fi
  if [ -z "$ssh_port" ];then
    echo "Le port ssh n est pas specifier : ssh_port"
    exit 1
  fi

  # Test de connexion a la base de donnees de gestioip
  mysql --defaults-extra-file=$DB_config_file -e "show databases;" >/dev/null
  if [ $? -ne 0 ]
  then
    echo
    echo "La base n existe pas ou l hote n est pas joingnable !"
    echo "Verifier le fichier de configuration de mysql : $DB_config_file !"
    exit 1
  fi

  # Test de connectivite SSH
  ssh -i $ssh_public_key -p $ssh_port $ssh_user@$ssh_host "date" >/dev/null

  if [ $? -ne 0 ];
  then
    echo
    echo "Le serveur ssh ou l hote n est pas joingnable !"
    echo "Verifier le fichier de configuration de mysql : $CONFIG_script !"
    exit 1
  fi

  # Affichage de la configuration (serveurs,utilisateurs...)
  echo "  *  Le check de configuration n a pas trouve d erreurs!"
  echo
  echo "******** La configuration est la suivante : *********"
  echo
  echo "Le fichier de configuration du script : $CONFIG_script"
  echo "Le serveur Backup : $(hostname)"
  echo "Le serveur Mysql : $MYSQL_Host"
  echo "Le chemin du dossier de backup : $MYSQL_Backup_folder"
  echo "Le fichier de configuration mysql : $DB_config_file"
  IFS=$'\n'
  for i in $(cat "$DB_config_file" | grep 'host\|port\|user')
  do
    echo "    * $i"
  done
  IFS=${IFS_back}

  # Creation du fichier de log  
  echo "La sauvegarde des base de donnes a commencer le $(date)" >> ./mysql-recover.log
}

function mysql-import () {

	# Dump de la table
	ssh -i $ssh_public_key -p $ssh_port $ssh_user@$ssh_host "mysqldump --defaults-extra-file=$DB_config_file --databases $database_name > $ssh_path_tmp/$backup_name/backup.sql" >/dev/null
	
	# Supression  de la table
	mysql --defaults-extra-file=$DB_config_file -e "DROP DATABASE IF EXISTS $database_name" >/dev/null
	
	if [ $? -ne 0 ];then
		echo "Erreur lors de la suppression de la base de donnee $database_name !"
		delete_tmp
		exit 1
	fi

	# Import de la table

	ssh -i $ssh_public_key -p $ssh_port $ssh_user@$ssh_host "mysql --defaults-extra-file=$DB_config_file < $ssh_path_tmp/$backup_name/$database_backup" >/dev/null
	
	if [ $? -ne 0 ];then
		echo "Erreur lors de l importation de la base $database_name"
		ssh -i $ssh_public_key -p $ssh_port $ssh_user@$ssh_host "mysql --defaults-extra-file=$DB_config_file < $ssh_path_tmp/$backup_name/backup.sql" >/dev/null
		delete_tmp
		exit 1
	fi

	# Suppression du backup de la base
	ssh -i $ssh_public_key -p $ssh_port $ssh_user@$ssh_host "rm $ssh_path_tmp/$backup_name/backup.sql" >/dev/null
	
	# Affichage statistique
	echo
	echo "***** Recap Import ******"
	echo "Import de la base : $database_backup [OK]"

}

function delete_tmp () {

	# Supression client SSH
	ssh -i $ssh_public_key -p $ssh_port $ssh_user@$ssh_host "rm -Rf /$ssh_path_tmp/$backup_name"

	if [ $(echo $backup_name | grep tar.gz) ];then
		# Supression du repertoire temporaire
		rm -Rf $path_backup/*
	fi

	# Suppression du fichier de configuration mysql
	ssh -i $ssh_public_key -p $ssh_port $ssh_user@$ssh_host "rm $DB_config_file"

	echo
	echo "Supression des fichiers temporaire : [OK]"
}

# ------------------------------------------------------------------
#			Programme Principal
# ------------------------------------------------------------------

echo
echo "***************************************************************************"
echo "***** Script qui restaure la base de données OCS GLPI et Gestioip  ********"
echo "***************************************************************************"
echo

IFS_back=${IFS}

# ---------- Verification de la configuration -----------
# -------------------------------------------------------

echo "************** Check de la configuration *************"
echo
# Appel la fonction qui check la configuration
check_conf

# -------------- Traitement --------------------
# ----------------------------------------------

echo
echo "****** Choix de la sauvegarde a importer ! **********"
echo

compteur=0
for backup_date in $(ls $MYSQL_Backup_folder | sort -r | cut -d '.' -f 1 | sed 's/backup-//g')
do
	echo "$compteur Sauvegarde du : $backup_date"	
	compteur=$(($compteur+1))
done

regex=[0-7]
choix=
# Choix de la sauvegarde
while [[ ! $choix =~ $regex ]];
do
	echo
	echo "Quel sauvegarde a restaurer : "
	read choix
done

compteur=0
for backup_date in $(ls $MYSQL_Backup_folder | sort -r)
do
	if [ $choix -eq $compteur ];then
		backup_name=$backup_date
		echo "La sauvegarde $(echo $backup_date | cut -d '.' -f 1) a ete selectionne !"
		break
	fi
	compteur=$(($compteur+1))
done

# Decompression de la sauvegarde
path_backup="$MYSQL_Backup_folder/$backup_name"

if [ $(echo $backup_name | grep tar.gz) ];then

	backup_name=$(echo $backup_date | cut -d '.' -f 1)

	tar -xzf "$path_backup" -C "/tmp/"
	if [ $? -ne 0 ];then
		echo "Erreur lors de la decompression de la sauvegarde $backup_name !"
		exit 1
	fi

	echo
	echo "Decompression de la sauvegarde $backup_name : [OK]"
	path_backup="/tmp/$backup_name"
fi 

# Copie des fichiers de sauvegarde sur le serveur de base de données
ssh -i $ssh_public_key -p $ssh_port $ssh_user@$ssh_host "mkdir -p /$ssh_path_tmp/$backup_name" >/dev/null
scp -i $ssh_public_key -P $ssh_port $path_backup/* $ssh_user@$ssh_host:/$ssh_path_tmp/$backup_name >/dev/null

if [ $? -ne 0 ];then
	echo "Erreur lors de la copie de la sauvegarde sur l hote $ssh_host !"
	rm -Rf $path_backup
	exit 1
fi

echo
echo "Copie de la sauvegarde sur l hote $ssh_host : [OK]"

# Copie du fichier de configuration de mysql
scp -i $ssh_public_key -P $ssh_port $DB_config_file $ssh_user@$ssh_host:$DB_config_file >/dev/null

if [ $? -ne 0 ];then
	echo "Erreur lors de l importation du fichier de configuration mysql !"
	delete_tmp
	exit 1
fi

# Descativation du service slave
check_slave=$(mysql --defaults-extra-file=$DB_config_file -e "show slave status;" | grep "Slave_IO_Running")

if [ ! -z "$check_slave" ];then
	mysql --defaults-extra-file=$DB_config_file -e "stop slave;"
	if [ $? -ne 0 ];then
		echo "Erreur lors de l arret du service slave !"
		delete_tmp
		exit 1
	fi
	echo
	echo "Arret du service slave : [OK]"

fi

echo
# Sauvegarde des bases de données spécifier
select database_backup in $(ls "$path_backup")
do
	database_name=$(echo $database_backup | sed 's/.sql//g')
	# Appel de la fonction qui importe la base de données !
	mysql-import

	echo
	echo "Importer une autre base de donnees ( 0 pour non et 1 pour oui) :"
	read choix_database

	if [ $choix_database -eq 0 ];then
		break
	fi
	
done

# Demarrage du service slave sur l hote mysql
if [ ! -z "$check_slave" ];then
	mysql --defaults-extra-file=$DB_config_file -e "start slave;"
	if [ $? -ne 0 ];then
		echo "Erreur lors du demarrage du service slave !"
		delete_tmp
		exit 1
	fi
	echo
	echo "Demarrer le service slave : [OK]"
fi

# Supression fichier temporaire
delete_tmp

echo
echo "Importation des bases de données : [OK]"

echo
echo "****************** Script termine avec succes ! ******************"
echo

echo "La restauration des base de donnees s est terminee avec succes !" >> ./mysql-recover.log
