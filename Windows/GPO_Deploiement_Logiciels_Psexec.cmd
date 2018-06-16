@echo off
rem ============================
rem Script realise le 21/04/2017
rem Auteur : Fabien MAUHOURAT
rem Utilisation : Déploiement de logiciel par gpo
rem Compatibilite verifie: W10 Entreprise LTSB
rem version : 1.0
rem ============================

rem Requirements :
rem Lancer le script en administrateur

rem Déclaration des Variables
set Bora=\\bora.nc\BORA\Donnees\Logiciels
set Rapport="\\bora.nc\BORA\Donnees\Service Informatique\Rapport"
set log=%Rapport%\rapport_%computername%.log

rem Test des droits d'administrateur
net session >nul 2>&1
if errorlevel 1 (
	exit 1
)

if not exist %Rapport% (mkdir %Rapport%)

echo Configuration de du déploiement de logiciels du poste %computername% le %date% a %time% >> %log% & echo/ >> %log%

echo ******* Installation des logiciels ********* >> %log% & echo/ >> %log%

rem Installation des logiciels
if not exist "C:\Program Files\OpenOffice 4" (
	start /wait %Bora%\Apache_OpenOffice_4.1.3_Win_x86_install_fr.exe /S >nul 2>>%log%
	if errorlevel 1 (
		echo L'installation d'open office comporte une erreur >> %log% & echo/ >> %log%
		exit 1
	) else (
		echo L'installation d'open office s'est terminé correctement dans C:\Program Files\OpenOffice 4 >> %log% & echo/ >> %log%
	)
) else (
	echo Open office est déja installé sur ce poste ! >> %log% & echo/ >> %log%
)

if not exist "C:\Program Files\AVAST Software" (
	"%Bora%\avast.exe" /SP /VERYSILENT /NOSTATUS /NOTRAY /SILENT >nul 2>>%log%
	if errorlevel 1 (
		echo L'installation d'Avast comporte une erreur >> %log% & echo/ >> %log%
		exit 1
	) else (
		echo L'installation d'Avast s'est terminé correctement dans C:\Program Files\AVAST Software >> %log% & echo/ >> %log%
	)
) else (
	echo L'antivirus Avast est déja installé sur ce poste ! >> %log% & echo/ >> %log%
)

echo Le déploiement est terminé >> %log%

