#!/bin/bash

### Déclaration variable ###
ocs=0
glpi=0
agent=0
lamp=0

## Fonction aide
help()
{
echo
echo "								####### AIDE #######"
echo "./nomduscript [arguments]"
echo "-m | --mysql		Mot de passe pour mysql"
echo "-p | --phpmyadmin	Mot de passe pour phpmyadmin"
echo "-o | --ocs		Installation d'ocs inventory serveur
			Ne pas oublier de spécifier le mot de passe root pour mysql option -m"
echo "-passocs		Specifie le mot de passe pour l'utilisateur d'ocs"
echo "-g | --glpi		Installation de GLPI et du plugin OCS"
echo "-a | --agent		Installation de l'agent"
echo "-h | --help       	Afficher l'aide !"
echo
}

## Test si pas d'arguments
if [ "$1" = "" ];then
	help
	exit 1
fi
## Création répertoire temporaire
mkdir /TEMP

### Test des arguments
while [ "$1" != "" ]; do
    case $1 in
	-m | --mysql )		shift
				passmysql=$1
				;;
	-p | --phpmyadmin )	shift
				passphpmyadmin=$1
				;;
	-o | --ocs )		ocs=1
				;;
	-passocs )		shift
				passocs=$1
				;;
	-g |--glpi )		glpi=1
				;;
        -h | --help )           help
                                exit
                                ;;
	-a | --agent )		agent=1
				;;
        * )                     help
                                exit 1
    esac
    shift
done

### Installation du serveur web
echo
echo -e "\e[92mMise a jour de la liste des packets !\e[0m"
echo
apt-get update >/dev/null

if [ ! -f /etc/apache2/apache2.conf ];
then
	echo "Installation d'apache"
	apt-get install -y apache2 >/dev/null 2>&1
	echo "Installation d'apache terminé"
	echo
else
	echo "Apache est déja installé"
	echo
fi

if [ ! -f /etc/mysql/my.cnf ];
then
	if [ ! -z $passmysql ];
	then
		echo "Installation de mysql"
		export DEBIAN_FRONTEND="noninteractive"
		debconf-set-selections <<< "mysql-server mysql-server/root_password password $passmysql"
		debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $passmysql"

		apt-get install -y mysql-server >/dev/null 2>&1
		echo "Mysql server est installé"
		echo

	else
		echo "Mysql serveur n'est pas installé"
		echo "Le mot de passe mysql est vide"
		exit 1
	fi

else
	echo "Mysql est déja installé"
	echo
fi


if cat /etc/issue | grep "Ubuntu 14.*" >/dev/null;
then
	if ! dpkg -s php5 >/dev/null 2>&1;
	then
		echo "Installation de PHP pour Ubuntu 14"
		apt-get install -y php5 >/dev/null 2>&1
		echo "Php est installé"
		echo
	else
		echo "PHP est déja installé"
		echo
	fi
elif cat /etc/issue | grep "Ubuntu 16.*" >/dev/null;
then
	if ! dpkg -s php >/dev/null 2>&1;
	then
		echo "Installation de PHP pour Ubuntu 16"
		apt-get install -y php php-mbstring >/dev/null 2>&1
		echo "Php est installé"
		echo
	else
		echo "PHP est déja installé"
		echo
	fi
fi

sleep 2

############# OCSinventory-server #############
if [ $ocs -eq 1 ];
then
	if [-z $passmysql] -o [-z $passocs];
	then
		echo
		echo "Le mot de passe de l'utilisateur root de mysql ou celui d'ocs n'est pas renseigné !"
		echo
		help
		exit 1
	fi
	
	echo -e "\e[92mInstalltion d'ocsinventory server !\e[0m"
	echo
	if cat /etc/issue | grep "Ubuntu 14.*" >/dev/null;
	then
		echo "Installation des dépendances PHP pour Ubuntu 14"
		echo
		apt-get install -y php5-common libapache2-mod-php5 php5-cli php5-mysql php5-gd php5-curl php-soap libc6-dev make >/dev/null 2>&1

	elif cat /etc/issue | grep "Ubuntu 16.*" >/dev/null;
	then
		echo "Installation des dépendances PHP pour Ubuntu 16"
		echo
		apt-get install -y php-common libapache2-mod-php php-cli php-mysql php-gd php-curl php-mbstring php-soap php-xml libc6-dev make >/dev/null 2>&1
	fi

	echo "Installation des dépendances PERL"
	echo
	apt-get install -y make libxml-simple-perl libio-compress-perl libdbi-perl libdbd-mysql-perl libapache-dbi-perl libnet-ip-perl libsoap-lite-perl libxml-libxml-perl libarchive-zip-perl libapache2-mod-perl2 >/dev/null 2>&1
	export PERL_MM_USE_DEFAULT=1
	cpan -i XML::Entities >/dev/null 2>&1
	echo "Téléchargement du server OCS"
	echo
	wget -P /TEMP https://github.com/OCSInventory-NG/OCSInventory-ocsreports/releases/download/2.3.1/OCSNG_UNIX_SERVER-2.3.1.tar.gz >/dev/null 2>&1
	tar -xzf /TEMP/OCSNG_UNIX_SERVER-2.3.1.tar.gz -C /TEMP >/dev/null 2>&1
	cd /TEMP/OCSNG_UNIX_SERVER-2.3.1
	./setup.sh
	#bash /TEMP/OCSNG_UNIX_SERVER-2.3.1/setup.sh

	chown -R www-data:www-data /var/www/html
	chown -R www-data:www-data /usr/share/ocsinventory-reports/
	chown -R www-data:www-data /var/lib/ocsinventory-reports

	a2enconf ocsinventory-reports >/dev/null 2>&1
	a2enconf z-ocsinventory-server >/dev/null 2>&1
	service apache2 restart >/dev/null 2>&1

	echo
	echo "Configurer le serveur Ocs avant de continuer"
	echo "http://ip du serveur/ocsreports"
	read y
	
	echo "Changement du mot de passe mysql de l'utilisateur OCS"
	echo
	mysql -u root --password=$passmysql -e "SET password FOR 'ocs'@'localhost' = password('$passocs');"
	sed -i 's/define("PSWD_BASE","ocs");/define("PSWD_BASE","'$passocs'");/' /usr/share/ocsinventory-reports/ocsreports/dbconfig.inc.php
	sed -i 's/PerlSetVar OCS_DB_PWD ocs/PerlSetVar OCS_DB_PWD '$passocs'/' /etc/apache2/conf-available/z-ocsinventory-server.conf

	service apache2 reload >/dev/null 2>&1
	
	rm /usr/share/ocsinventory-reports/ocsreports/install.php
	
	echo "Installation du serveur est terminé"
	echo
fi


########### Installation de l'agent #############

if [ $agent -eq 1 ];
then
	echo -e "\e[92mTelechargement et installation de d'OCS agent 2.3 !\e[0m"
	echo
	echo "Installation des dépendances"
	echo
	apt-get -y install -y dmidecode libxml-simple-perl libio-compress-perl libnet-ip-perl libwww-perl libdigest-md5-perl libnet-ssleay-perl >/dev/null 2>&1
	apt-get -y install libcrypt-ssleay-perl libnet-snmp-perl libproc-pid-file-perl libproc-daemon-perl net-tools libsys-syslog-perl pciutils smartmontools read-edid nmap >/dev/null 2>&1
	
	echo "Telechargement de l'agent"
	echo
	wget -P /TEMP https://github.com/OCSInventory-NG/UnixAgent/releases/download/2.3/Ocsinventory-Unix-Agent-2.3.tar.gz >/dev/null 2>&1
	tar -xzf /TEMP/Ocsinventory-Unix-Agent-2.3.tar.gz -C /TEMP >/dev/null 2>&1
	cd /TEMP/Ocsinventory-Unix-Agent-2.3
	echo "Installation"
	echo
	perl Makefile.PL >/dev/null 2>&1
	make >/dev/null 2>&1
	make install
	echo
	echo "Installation de l'agent terminé"
	echo
fi

########### GLPI #############
if [ $glpi -eq 1 ];
then
	echo -e "\e[92mTelechargement et installation de GLPI et du plugin OCS !\e[0m"
	echo
	if cat /etc/issue | grep "Ubuntu 14.*" >/dev/null;
	then
		echo "Installation des dépendances PHP pour Ubuntu 14"
		echo
		apt-get install -y php5-imap php5-ldap php5-curl php5-mysql php5-gd >/dev/null 2>&1
		php5enmod imap
		
	elif cat /etc/issue | grep "Ubuntu 16.*" >/dev/null;
	then
		echo "Installation des dépendances PHP pour ubuntu 16"
		echo
		apt-get install -y php-imap php-ldap php-curl php-mysql php-gd php-mbstring >/dev/null 2>&1
		phpenmod imap
	fi
	
	echo "Telechargement de GLPI"
	wget -P /TEMP https://github.com/glpi-project/glpi/releases/download/9.1.2/glpi-9.1.2.tgz >/dev/null 2>&1
	tar -xzf /TEMP/glpi-9.1.2.tgz -C /var/www/html >/dev/null
	echo "Téléchargement terminé"
	echo

	chown -R www-data:www-data /var/www/html/glpi
	
	echo "Telechargement du plugin OCS"
	wget -P /TEMP https://github.com/pluginsGLPI/ocsinventoryng/releases/download/1.3.3/glpi-ocsinventoryng-1.3.3.tar.gz >/dev/null 2>&1
	tar -xzf /TEMP/glpi-ocsinventoryng-1.3.3.tar.gz -C /var/www/html/glpi/plugins >/dev/null
	echo "Téléchargement terminé"
	echo
	
	sed -i '/^<\//i\        <Directory /var/www/html/glpi>' /etc/apache2/sites-enabled/000-default.conf
        sed -i '/^<\//i\                Options Indexes FollowSymLinks' /etc/apache2/sites-enabled/000-default.conf
        sed -i '/^<\//i\                AllowOverride limit' /etc/apache2/sites-enabled/000-default.conf
        sed -i '/^<\//i\                Require all granted' /etc/apache2/sites-enabled/000-default.conf
        sed -i '/^<\//i\        </Directory>' /etc/apache2/sites-enabled/000-default.conf
	service apache2 restart	>/dev/null 2>&1
	
	echo "Configurer GLPI avant de continuer en allant sur cette page :"
	echo "http://ip du serveur/glpi"
	read x
	rm /var/www/html/glpi/install/install.php

	echo "GLPI s'est installé correctement"
	echo
fi

if [ -d /TEMP ];
then
	rm -R /TEMP
fi
