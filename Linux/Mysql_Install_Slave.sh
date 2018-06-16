#!/bin/bash
# ============================
# Script réalisé le 21/04/2017
# Auteur : Fabien MAUHOURAT
# Utilisation : Automatise la configuration du serveur esclave de msyql entre deux server linux
# Compatibilité verifié: Ubuntu 16.04 pour mysql 5.7
# version : 1.0
# ============================
# Requirements :
# 	- Definir le mot de passe de mysql du compte roor du master et de l'esclave
# 	- Puis definir l'utilisateur et le mdp du compte chargé d'effecter la réplication
# 	- Puis deifinir l'ip du serveur maitre
# 	- Definir le chemin absolue des fichier de configuration mysql (/etc/mysql/my.cnf pour Mysql 5.5 et 5.6 puis /etc/mysql/mysql.conf.d/mysqld.cnf pour mysql 5.7) 

# Fonction qui termine le programme
fin ()
{
	sed -i '/Warning/d' $log >/dev/null 2>> $log
	# Affcihage de la boite de dialog (interface graphique)
	sleep 3
	whiptail --title "Script Replication" --msgbox "L'execution du script est terminé" 8 78	
	exit 1
}
# Fonction de Restauration
restauration ()
{
	echo -e "\n\e[92m######### Restauration en cours\e[0m\n" | tee -a $log

	mysql -u root --password=$rootpass -e "DROP DATABASE IF EXISTS bdd_vehicules" >/dev/null 2>> $log
	echo "Suppression de la base de données reussi" | tee -a $log
	
	service mysql stop >/dev/null 2>> $log
	rm $confmysql >/dev/null 2>> $log
	mv ${confmysql}.back $confmysql >/dev/null 2>> $log
	service mysql start >/dev/null 2>> $log
	echo "Restauration du fichier mysql.cnf reussi" | tee -a $log

	if [ "$bdd"="${DIR}/bdd_vehiculesmaitre.sql" ]; then
		rm $bdd >/dev/null 2>> $log
		echo -e "Suppression du script de base de données $bdd reussi\n" | tee -a $log
	fi
	
	echo -e "\n\e[92m######## Restauration terminée avec succés\e[0m\n" | tee -a $log
	fin
}
# Fonction d'Installation de mysql
installmysql ()
{
	if [ ! -z $rootpass ];
	then
		echo -e "\n\e[92m######## Installation de mysql\e[0m\n" | tee -a $log

		# Utilisation de debconf pour réaliser l'installation silencieuse ( spécifier le mot de passe)
		export DEBIAN_FRONTEND="noninteractive"
		debconf-set-selections <<< "mysql-server mysql-server/root_password password $rootpass"
		debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $rootpass"

		# Mise a jour de la liste des packets puis installation du packet mysql
		apt-get update >/dev/null 2>> $log
		apt-get install -y mysql-server >/dev/null 2>> $log
		if [[ $? -ne 0 ]] ; then
			echo "L'installation de mysql ne s'est pas terminé correctement" | tee -a $log
			fin
		else
			echo "Mysql server s'est installé corectement" | tee -a $log
			echo
		fi
		
	else
		echo "Mysql serveur n'est pas installé" | tee -a $log
		echo "Le mot de passe mysql est vide" | tee -a $log
		exit 1
	fi
}

echo -e "\n***********************************************"
echo -e "******* Configuration serveur esclave *********"
echo -e "***********************************************\n"

# Configuration des variables
# DIR correspond au chemin absolue du script exécuté
DIR=$(cd `dirname ${0}`; pwd)
id=$(hostname)
ipmaitre="192.168.75.162"
masterpass=toor
rootpass=admin
slaveuser=slave
slavepass=toor
confmysql=/etc/mysql/mysql.conf.d/mysqld.cnf
# Le fichier rapport est composé du mot rapport suivit du nom du pc tronqué à esclave_8 : rapport.esclave_8
log=${DIR}/rapport.${id:5,13}.log
bdd=${DIR}/bdd_vehicules.sql

echo -e "\nConfiguration de la réplication du poste `hostname` le `date`\n" > $log 2>/dev/null

# Verifie si le packet mysql est installé
if [ ! -f /etc/mysql/my.cnf ];
then
	installmysql
else
	echo -e "Le packet Mysql est déjà installé" | tee -a $log
	echo
fi

# Test utilisateur et mdp mysql
mysql -u root --password=$rootpass -e "show databases;" >nul 2>&1
if [[ $? -ne 0 ]] ; then
	echo "Le mdp du compte root de mysql n'est pas le bon" | tee -a $log
	fin
fi

# Test si le fichier de configuration de mysql existe
if [ ! -f $confmysql ];
then
	echo "Le fichier $confmysql n'existe pas" | tee -a $log
	fin
fi

# Test Connexion au serveur maitre
echo -e "\n\e[92m######### Test de connexion avec le serveur maitre\e[0m\n" | tee -a $log

if ping -c 2 $ipmaitre | grep ttl= >/dev/null 2>&1;
then
	# Récupération de la base de données sur le serveur esclave
	echo -e "Le serveur maitre est joinable avec l'ip $ipmaitre" | tee -a $log
	mysqldump -h $ipmaitre -u root --password=$masterpass bdd_vehicules > ${DIR}/bdd_vehiculesmaitre.sql 2>> $log
	if [[ $? -eq 0 ]] ; then
		bdd=${DIR}/bdd_vehiculesmaitre.sql
		echo "La derniere version de la base de données a été telechargé depuis $ipmaitre" | tee -a $log
	fi
else
	echo "Le serveur maitre n'est pas joinable avec l'ip $ipmaitre" | tee -a $log
fi

# Test si le fichier sql de création de la base existe
if [ ! -f $bdd ];
then
	echo "Le fichier $bdd de création de la base  n'existe pas" | tee -a $log
	fin
fi

# Suavegarde du fichier my.ini
echo -e "\n\e[92m######### Sauvegarde des fichiers en cours\e[0m\n" | tee -a $log

cp $confmysql ${confmysql}.back >/dev/null 2>> $log
echo "Sauvegarde du fichier $confmysql réussi" | tee -a $log

# Configuration du serveur id
echo -e "\n\e[92m######### Configuration du serveur esclave en cours\e[0m\n" | tee -a $log

service mysql stop >/dev/null 2>> $log
echo server-id=${id:13} >> $confmysql
service mysql start >/dev/null 2>> $log

echo "Modification du serveur-id reussi : ${id:13}" | tee -a $log

# Importation de la base de données
echo -e "\n\e[92m######### Importation de la base de donnéees\e[0m\n" | tee -a $log

if [ -f $bdd ];
then
	mysql -u root --password=$rootpass -e "DROP DATABASE IF EXISTS bdd_vehicules;
	CREATE DATABASE IF NOT EXISTS bdd_vehicules;" >/dev/null 2>>$log
	mysql -u root --password=$rootpass bdd_vehicules < $bdd >/dev/null 2>>$log
	mysql -u root --password=$rootpass -e "use bdd_vehicules;select * from t_agents;" >/dev/null 2>>$log
	
	if [[ $? -ne 0 ]] ; then
		echo "La base de données $bdd n'a pas pu être importer" | tee -a $log
		echo "Contacter votre administrateur"
		restauration
	else
		echo "La base de données $bdd a été importer avec succés" | tee -a $log
	fi
else
	echo "Le fichier sql de la base de données n'existe pas $bdd" | tee -a $log
	restauration
fi

read o

# Modification des parametres du master
echo -e "\n\e[92m######### Modification du master\e[0m\n" | tee -a $log

mysql -u root --password=$rootpass -e "stop slave;
CHANGE MASTER TO MASTER_HOST='$ipmaitre',
MASTER_USER='$slaveuser',
MASTER_PASSWORD='$slavepass';
start slave;" >/dev/null 2>> $log
#mysql -u root --password=$rootpass -e "show slave status\G;" | grep "Waiting for master" >/dev/null 2>> $log
if [[ $? -eq 0 ]];
then
	echo La modification des parametres du master a réussi | tee -a $log
else
	echo La modification des parametres du master a échoué | tee -a $log
	restauration
fi

#Suppression du backup du fichier my.ini puis le script se termine
rm ${confmysql}.back >/dev/null 2>> $log
rm $bdd >/dev/null 2>> $log
if [ -f "${DIR}/bdd_vehicules.sql" ]; then
		rm $bdd >/dev/null 2>> $log
fi
echo -e "\nNetoyage du fichier my.ini.back ainsi que du fichier sql de création de la base de données terminée" | tee -a $log

echo -e "\n\e[92m######## La configuration de la réplication s est terminé avec succés\e[0m\n" | tee -a $log
fin

