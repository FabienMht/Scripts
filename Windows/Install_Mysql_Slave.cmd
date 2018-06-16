@echo off
rem ============================
rem Script realise le 21/04/2017
rem Auteur : Fabien MAUHOURAT
rem Utilisation : Automatise la configuration du serveur esclave de msyql sur Windows
rem Compatibilite verifie: W7,W8.1,W10 pour mysql 5.6
rem version : 1.0
rem ============================

rem Requirements :
rem 	- Definir le mot de passe de mysql du compte roor du master et de l'esclave
rem 	- Puis definir l'utilisateur et le mdp du compte charge d'effectuer la replication
rem 	- Puis definir l'ip du serveur maitre
rem 	- Definir le chemin absolue du fichier de configuration mysql

echo/
echo ***********************************************
echo ******* Configuration serveur esclave *********
echo ***********************************************
echo/

rem Test des droits d'administrateur
net session >nul 2>&1
if errorlevel 1 (
	echo Il faut lance le script en mode administrateur : Reportez vous au lisez-moi.txt
	echo/
	pause
	exit 1
)

REM Configuration des variables
set id=%computername:~-1%
set ipmaitre=192.168.75.162
set masterpass=toor
set rootpass=admin
set slaveuser=slave
set slavepass=toor
set confmysql="C:\ProgramData\MySQL\MySQL Server 5.6\my.ini"
REM Le fichier rapport est compose du mot rapport suivit du nom du pc tronque a esclave_8 : rapport.esclave_8.log
set log=%~dp0rapport.%computername:~5,13%.log
set bdd=%~dp0bdd_vehicules.sql

echo Configuration de la replication du poste %computername% le %date% a %time% > %log% & echo/ >> %log%

rem Test utilisateur et mdp mysql
mysql -u root --password=%rootpass% -e "show databases;" >nul 2>&1
if errorlevel 1 (
	echo Le mdp du compte root de mysql ne correspond pas & echo Le mdp du compte root de mysql ne correspond pas >> %log%
	echo/ & echo/ >> %log%
	echo Le script ne s'est pas termine correctement & echo Le script ne s'est pas termine correctement >> %log%
	goto fin
)

rem Test si le fichier de configuration de mysql existe
if not exist %confmysql% (
	echo Le fichier %confmysql% est introuvable >> %log%
	echo Une erreur de configuration est presente contacter votre administrateur
	echo/ & echo/ >> %log%
	echo Le script ne s'est pas termine correctement & echo Le script ne s'est pas termine correctement >> %log%
	goto fin
)

rem Test Connexion au serveur maitre
echo ######### Test de connexion avec le serveur maitre & echo ######### Test de connexion avec le serveur maitre >> %log%
echo/

ping -n 1 %ipmaitre% | find "TTL=" >nul

if errorlevel 1 (
	echo Le serveur maitre n'est pas joinable & echo Le serveur maitre n'est pas joinable avec l'ip %ipmaitre% >> %log%
) else (
	REM Recuperation de la base de donnees sur le serveur esclave
	echo Serveur maitre est joinable & echo Le serveur maitre est joinable avec l'ip %ipmaitre% >> %log%
	mysqldump -h %ipmaitre% -u root --password=%masterpass% bdd_vehicules > %~dp0bdd_vehiculesmaitre.sql 2>>%log%
	if errorlevel 0 (
		set bdd=%~dp0bdd_vehiculesmaitre.sql
		echo La derniere version de la base de donnees a ete telecharge & echo La derniere version de la base de donnees a ete telecharge depuis %ipmaitre% >> %log%
	) else (
		echo La derniere version de la base de donnees n'a pas pu etre telecharge & echo La derniere version de la base de donnees n'a pas pu etre telecharge depuis %ipmaitre% >> %log%
	)
)

rem Test si le fichier de creation de la base de donnees existe
if not exist %bdd% (
	echo/ & echo/ >> %log%
	echo Le fichier sql de creation la base de donnees n'existe pas & echo Le fichier sql %bdd% de creation de la base de donnees n'existe pas >> %log%
	echo/ & echo Reportez vous au lisez-moi.txt
	echo/ & echo/ >> %log%
	echo Le script ne s'est pas termine correctement & echo Le script ne s'est pas termine correctement >> %log%
	goto fin
)

rem Sauvegarde du fichier my.ini
echo/ & echo/ >> %log%
echo ######### Sauvegarde des fichiers en cours & echo ######### Sauvegarde des fichiers en cours >> %log%
echo/

REM Copy du fichier my.ini
copy %confmysql% %confmysql%.back >nul

echo Sauvegarde des fichiers reussis & echo Sauvegarde du fichier %confmysql% reussis >> %log%

rem Configuration du serveur id
echo/ & echo/ >> %log%
echo ######### Configuration du serveur esclave en cours & echo ######### Configuration du serveur esclave en cours >> %log%
echo/

sc query mysql56 | find "RUNNING" >nul 2>&1
if errorlevel 1 (
	echo Le service mysql est deja arrete & echo Le service mysql est deja arrete >> %log%
) else (
	net stop mysql56 2>>%log% 1>nul
)
echo server-id=%id% >> %confmysql%
net start mysql56 2>>%log% 1>nul

echo Modification de la configuration du serveur esclave reussi & echo Modification du serveur-id reussi : %id% >> %log%
echo/

rem Importation de la base de donnees
echo/ >> %log%
echo ######### Importation de la base de donnees & echo ######### Importation de la base de donnees >> %log%
echo/

REM Creation de la base de donnees si elle n'existe pas puis importaion de la base
mysql -u root --password=%rootpass% -e "DROP DATABASE IF EXISTS bdd_vehicules;CREATE DATABASE IF NOT EXISTS bdd_vehicules;" >nul 2>>%log%
mysql -u root --password=%rootpass% bdd_vehicules < %bdd% >nul 2>>%log%
REM Verifictaion de la presence des donnees
mysql -u root --password=%rootpass% -e "use bdd_vehicules;select * from t_agents;" >nul 2>>%log%

REM Si la base de donnees n'a pas pu etre importer la fonction de restauration est lancee
if errorlevel 1 (
	echo La base de donnees n'a pas pu etre importer & echo La base de donnees %bdd% n'a pas pu etre importer >> %log%
	echo Contacter votre administrateur
	goto restauration
) else (
	echo La base de donnees a ete importer & echo La base de donnees %bdd% a ete importer >> %log%
)

rem Modification des parametres du master
echo/ & echo/ >> %log%
echo ######### Modification du master & echo ######### Modification du master >> %log%
echo/

REM Modification de l'ip du master ainsi que de l'utilisateur esclave et du mot de passe
mysql -u root --password=%rootpass% -e "stop slave;CHANGE MASTER TO MASTER_HOST='%ipmaitre%', MASTER_USER='%slaveuser%', MASTER_PASSWORD='%slavepass%';start slave;" >nul 2>> %log%

REM Si la configuration du master a echoue la fonction de restauration est lancee
if errorlevel 1 (
	echo La modification des parametres du master a echoue & echo La modification des parametres du master a echoue avec l'ip %ipmaitre% et l'utilisateur %slaveuser% >> %log%
	goto restauration
) else (
	echo La modification des parametres du master a reussi & echo La modification des parametres du master a reussi avec l'ip %ipmaitre% et l'utilisateur %slaveuser% >> %log%
)

rem Suppression du backup du fichier my.ini ainsi que du fichier sql de creation de la base de donnees puis le script se termine
del %confmysql%.back >nul 2>> %log%
REM Suppression des fichiers sql
del %bdd% >nul 2>> %log%
if exist %~dp0bdd_vehicules.sql (
	del %~dp0bdd_vehicules.sql >nul 2>> %log%
)

echo/ & echo/ >> %log%
echo ######## Netoyage des fichiers & echo ######## Netoyage du fichier my.ini.back ainsi que du fichier sql de creation de la base de donnees >> %log% & echo/ >> %log%
echo/
echo La configuration de la replication s'est termine avec succes & echo La configuration de la replication s'est termine avec succes >> %log%
goto fin

rem Restauration du fichier my.ini en cas d'erreur lors du script
:restauration
echo/ & echo/ >> %log%
echo ######### Restauration en cours & echo ######### Restauration en cours >> %log%
echo/

REM Supression de labase de donnees si la configuration a echoue
mysql -u root --password=%rootpass% -e "DROP DATABASE IF EXISTS bdd_vehicules" >nul 2>> %log%

REM Restauration du fichier my.ini
net stop mysql56 >nul 2>> %log%
del %confmysql% & move %confmysql%.back %confmysql% >nul 2>> %log%
net start mysql56 >nul 2>> %log%

REM Suppresion du script de base de donnees du serveur maitre
if "%bdd%"=="%~dp0bdd_vehiculesmaitre.sql" (
	del %bdd% >nul 2>> %log%
)

echo Restauration terminee avec succes & echo Restauration terminee avec succes >> %log%
echo/ & echo Le script ne s'est pas termine correctement & echo Le script ne s'est pas termine correctement >> %log%
goto fin

rem Fin du programme
:fin
REM Suppression des ligne d'avertissement de mysql du fichier rapport.log
powershell "(Get-Content '%log%') | select-string -pattern '^Warning' -notmatch | Set-Content '%log%'"
echo/
echo Appuyer sur entre pour termine le script
echo/
pause
