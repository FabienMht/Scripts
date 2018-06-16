#!/bin/bash

# ------------------------------------------------------------------
#			Definition des fonctions
# ------------------------------------------------------------------

# Fonction qui verifie la configuration
function check_conf () {

  # Chargement du fichier de configuration du script
  CONFIG_script="./config_mysql_backup.conf"
  
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
  if [ -z "$Database" ];then
    echo "Les abse de donnes a sauvegarder n est pas specifier : Database"
    exit 1
  fi
  if [ -z "$Rotation" ];then
    echo "La rotation des sauvegardes n est pas specifier : Database"
    exit 1
  fi
  if [ ! -d "$MYSQL_Backup_folder" ];then
    mkdir "$MYSQL_Backup_folder"
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
  if [ -z "$ssh_port" ];then
    echo "Le port ssh n est pas specifier : ssh_port"
    exit 1
  fi
  if [ -z "$ssh_path_tmp" ];then
    echo "Le repertoire temporaire du client n est pas specifier : ssh_path_tmp"
    exit 1
  fi
  if [ -z "$ssh_public_key" ];then
    echo "Le chemin de la cle public n est pas specifier : ssh_public_key"
    exit 1
  fi

  # Test de connexion a la base de donnees de gestioip
  mysql --defaults-extra-file=$DB_config_file -e "show databases;" >/dev/null

  if [ $? -ne 0 ]
  then
    echo
    echo "La connexion au serveur mysql a echoue !"
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
  echo "Le chemin du dossier de backup : $MYSQL_Backup_folder"
  echo "Le fichier de configuration mysql : $DB_config_file"
  IFS=$'\n'
  for i in $(cat "$DB_config_file" | grep 'host\|port\|user')
  do
    echo "    * $i"
  done
  IFS=${IFS_back}
 
  # Creation du fichier de log
  echo "La sauvegarde des base de donnes a commencer le $(date)" >> ./mysql-backup.log
  echo
}

function mysql-dump () {

	# Dump de la base
	ssh -i $ssh_public_key -p $ssh_port $ssh_user@$ssh_host "mysqldump --defaults-extra-file=$DB_config_file --databases $database_backup > $ssh_path_tmp/$database_backup.sql"
	
	if [ $? -ne 0 ];then
		echo "La base $database_backup n a pas pu etre exporte !"
		delete_tmp
		exit 1
	fi

	# Copie des fichiers de sauvegarde sur le serveur de base de donnees
	scp  -i $ssh_public_key -P $ssh_port $ssh_user@$ssh_host:$ssh_path_tmp/$database_backup.sql $folder_backup_date >/dev/null

	if [ $? -ne 0 ];then
		echo "La base $database_backup n a pas pu etre copier sur l hote $hostname !"
		delete_tmp
		exit 1
	fi

	# Suppression du dump
	ssh -i $ssh_public_key -p $ssh_port $ssh_user@$ssh_host "rm $ssh_path_tmp/$database_backup.sql"

	# Affichage statistique
	echo
	echo "***** Recap Export ******"
	echo "Export de la base $database_backup : [OK]"
	echo "Taille de la base : $(ls -hsal "$folder_backup_date" | grep $database_backup | cut -d '-' -f "1")"

}

function delete_tmp () {
	
	# Supprime du fichier de configuration de mysql sur le serveur
	ssh -i $ssh_public_key -p $ssh_port $ssh_user@$ssh_host "rm $DB_config_file"

	# Supprime le dossier de sauvegarde actuelle
	rm -Rf $folder_backup_date

}

# ------------------------------------------------------------------
#			Programme Principal
# ------------------------------------------------------------------

echo
echo "***************************************************************************"
echo "***** Script qui Sauvegarde la base de données OCS GLPI et Gestioip  ******"
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

echo "***** Sauvegarde des bases de données ******"

folder_backup_date="$MYSQL_Backup_folder"/backup-$(date +"%y-%m-%d")

# Creation du dossier avec la date du jour
if [ ! -d "$folder_backup_date" ];then

  mkdir "$folder_backup_date"
  if [ $? -ne 0 ];then
	echo "Erreur lors de la creation du dossier $folder_backup_date !"
	exit 1
  fi
  echo
  echo "Creation du dossier $folder_backup_date : [OK]"
fi

# Copie du fichier de configuration de mysql sur le serveur
scp -i $ssh_public_key -P $ssh_port $DB_config_file $ssh_user@$ssh_host:$DB_config_file >/dev/null

if [ $? -ne 0 ];then
	echo "La base $database_backup n a pas pu etre exportee !"
	exit 1
fi

# Lock les tables en lecture
echo
echo "Protection des tables en ecriture activer : [OK]"
mysql --defaults-extra-file=$DB_config_file -e "flush tables with read lock;" >/dev/null

# Sauvegarde des bases de données spécifier
for database_backup in ${Database[*]}
do
	# Appel de la fonction qui dump la base de données !
	mysql-dump

done

# Delock les tables en lecture
echo
echo "Protection des tables en ecriture desactiver : [OK]"
mysql --defaults-extra-file=$DB_config_file -e "unlock tables;" >/dev/null

echo
echo "Base de donnes sauvegarder [OK]"
echo

echo "********** Rotation des Logs **********"

# Archive les backup precedant et supprime ceux trop ancien !
for folder_backup in $(ls "$MYSQL_Backup_folder");
do
	# Calcul la difference de la date actuelle avec celle de la sauvegarde
	date_folder=$(echo $folder_backup | sed 's/backup-//g' | sed 's/.tar.gz//g')
	path_folder=$MYSQL_Backup_folder/$folder_backup
	diff_date=$(($(($(date "+%s") - $(date -d "$date_folder" "+%s"))) / 86400))

	# Supprime les sauvegardes dont la date est superieure a la rotation
	if [ $diff_date -gt $Rotation ];then

		rm -Rf $path_folder

		if [ $? -ne 0 ];then
			echo "La sauvegarde du $date_folder n a pas pu etre suprrime !"
			exit 1
		fi
		
		echo	
		echo "Sauvegarde $date_folder suprrime : [OK]"
		continue
	fi

	# Archive les sauvegardes dont la date est inferieure a la rotation suaf celle du jour
	if [ $diff_date -ne 0 ];then

		if [ ! $(echo $path_folder | grep tar.gz) ];then

			tar -czf $path_folder.tar.gz $path_folder

			if [ $? -ne 0 ];then
				echo "L archivage du $date_folder a echoue !"
				exit 1
			fi
			
			rm -Rf $path_folder	
			
			if [ $? -ne 0 ];then
				echo "La suppression du $date_folder echoue !"
				exit 1
			fi

			echo
			echo "Archivage $date_folder : [OK]"
			continue
		fi
	fi
done

echo
echo "Rotation des logs [OK]"

echo
echo "****** Script termine avec succes ! *******"
echo

echo "La sauvegarde des bases ----- ${Database[*]} ---- s est terminee avec succes !" >>./mysql-backup.log
