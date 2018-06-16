#!/bin/bash

# ------------------------------------------------------------------
#			Definition des fonctions
# ------------------------------------------------------------------

# Fonction qui verifie la configuration
function check_conf () {

  # Chargement du fichier de configuration du script
  CONFIG_script=./config_users_check.conf
  
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
  if [ -z "$LDAP_User" ];then
    echo "Le nom de l utilisateur LDAP n est pas definie : LDAP_User"
    exit 1 
  fi
  if [ -z "$LDAP_Pass" ];then
    echo "Le mot de passe du compte $(echo $LDAP_User | cut -d'=' -f 2 | cut -d',' -f 1) est vide"
    exit 1
  fi
  if [ -z "$LDAP_Host" ];then
    echo "Le serveur LDAP n est pas specifier : LDAP_Pass"
    exit 1
  fi
  if [ -z "$LDAP_DN" ];then
    echo "Le DN de l utilisateur LDAP n est pas specifie : LDAP_DN"
    exit 1
  fi
  if [ -z "$mysql_get_users" ];then
    echo "La requete mysql qui recupere les utilisateurs n est pas specifier : mysql_get_users"
    exit 1
  fi
  if [ -z "$mysql_get_group" ];then
    echo "La requete mysql qui recupere les utilisateurs n est pas specifier : mysql_get_group"
    exit 1
  fi
  if [ -z "$gestioip_local_user" ];then
    echo "L utilisateur local de gestioip n est pas specifie : gestioip_local_user"
    exit 1
  fi

  # Test de connexion a la base de donnees de gestioip
  mysql --defaults-extra-file=$DB_config_file -e "use gestioip;"
  if [ $? -ne 0 ]
  then
    echo
    echo "La base n existe pas ou l hote n est pas joingnable !"
    echo "Verifier le fichier de configuration de mysql : $DB_config_file !"
    exit 1
  fi
  
  # Test de connexion au controleur de domaine via LDAP
  ldapsearch -H ldaps://$LDAP_Host:636 -xb "" -s base "objectclass=*" -o nettimeout=5 >/dev/null
  if [ $? -ne 0 ]
  then
    echo
    echo "Connexion AD impossible !"
    echo "Verifier le fichier de configuration du script : $CONFIG_script"
    exit 1
  fi

  # Affichage de la configuration (serveurs,utilisateurs...)
  echo "  *  Le check de configuration n a pas trouve d erreurs!"
  echo
  echo "******** La configuration est la suivante : *********"
  echo
  echo "Le fichier de configuration du script : $CONFIG_script"
  echo "Le serveur IPAM : $(hostname)"
  echo "Le serveur LDAP : $LDAP_Host"
  echo "L utilisateur LDAP : $(echo $LDAP_User | cut -d'=' -f 2 | cut -d',' -f 1)"
  echo "Le DN de l OU de base pour la recherche :"
  echo "    * $LDAP_DN"
  echo "Le fichier de configuration mysql : $DB_config_file"
  IFS=$'\n'
  for i in $(cat "$DB_config_file" | grep 'host\|port\|user')
  do
    echo "    * $i"
  done
  IFS=${IFS_back}
  echo
  
}

function create_user () {

  # Si l utilisateur n existe pas alors il est ajouter a la base de gestioip
  if [ $test_user -ne 1 ]
  then
    # Appel de la fonction "groups_ldap" pour retourner le groupe correspondant de l unite d organisation dans gestioip
    groups_ldap "$ldap_group"
    groups_gestioip

    mysql --defaults-extra-file=$DB_config_file -e "INSERT INTO gestioip.gip_users (name,group_id,comment) VALUES ('$ldap_user','$gestio_group_id','');"

    if [ $? -ne 0 ];then
      echo "Erreur sur la requete mysql d ajout de l utilisateur $ldap_user : fonction create_user !"
      exit 1
    else
      echo -n " - $ldap_user : "
      echo "[Creation]"
      echo "   * Groupe : $group_name"
      compteur_ldap_add=$(($compteur_ldap_add+ 1))
    fi
  fi
}

function delete_user () {

  # L utilisateur est supprime s il n existe plus dans l AD
  if [ $test_user -ne 1 ]
  then
    mysql --defaults-extra-file=$DB_config_file -e "DELETE FROM gestioip.gip_users WHERE name='$mysql_user';"

    if [ $? -ne 0 ];then
      echo "Erreur sur la requete mysql de suppression de l utilisateur $mysql_user : fonction delete_user !"
      exit 1 
    else
      echo -n " - $mysql_user : "
      echo "[Suppression]"
      compteur_gestioip_supp=$(($compteur_gestioip_supp+ 1))
    fi
  fi
}

# Retourne le groupe de l'utilisateur en fonction de l unite d organisation
function groups_ldap () {

  # Prend comme argument l unite d organisation de l utilisateur
  case "$1" in
    "basd")
      gestio_group_id=1
      ;;
    "bn2")
      gestio_group_id=2
      ;;
    *)
      gestio_group_id=3
      ;;
  esac
}

function groups_gestioip () {

  # Permet de retourner le nom du groupe en fonction de l id
  for gestioip_group_name in $req_get_group
  do
    group_id=$(echo $gestioip_group_name | cut -d';' -f 1)  
    group_name=$(echo $gestioip_group_name | cut -d';' -f 2)
    if [ $group_id = $gestio_group_id ];then
      break
    fi 
  done
}

function compare_gestioip () {

  # Verifie si l utilisateur dans la base de gestioip existe toujours dans l AD
  if [ "$mysql_user" = "$ldap_user" ]  
  then
    groups_ldap "$ldap_group"

    # Puis verifie s il appartient au bon groupe
    if [ $gestio_group_id = $mysql_group ];
    then
      test_user=1
    fi
    break
  fi
}

function compare_ldap () {

  # Verifie si l utilisateur de l AD est present dans gestioip  
  if [ "$mysql_user" = "$ldap_user" ]
  then
    test_user=1
    break
  fi
}

function recup_ldap_user_group () {

  # Recupere dans des variables le nom d'utilisateur et l unite d organisation de l AD
  ldap_group=$(echo $ldap_user | cut -d';' -f 1)
  ldap_user=$(echo $ldap_user | cut -d';' -f 2)
  ldap_user=${ldap_user,,}
  ldap_group=${ldap_group,,}

  # Verifie si les variables sont definies
  if [ -z "$ldap_group" ];then
    echo "La variable ldap_group n est pas definie !"
    exit 1
  fi
  if [ -z "$ldap_user" ];then
    echo "La variable ldap_user n est pas definie ! "
    exit 1
  fi
}

function recup_mysql_user_group () {

  # Recupere dans des variables le nom d'utilisateur et le groupe de gestioip
  mysql_group=$(echo $mysql_user | cut -d';' -f 2)  
  mysql_user=$(echo $mysql_user | cut -d';' -f 1)
  mysql_user=${mysql_user,,}

  # Verifie si les variables sont definies
  if [ -z "$mysql_group" ];then
    echo "La variable mysql_group n est pas definie !"
    exit 1
  fi
  if [ -z "$mysql_user" ];then
    echo "La variable mysql_user n est pas definie !"
    exit 1
  fi

  # Exclue l utilisateur local de gestioip des traitements
  if [ "$mysql_user" = "$gestioip_local_user"  ]
  then
        continue
  fi
}

function test_exist_user () {

  # Test si la variable de l utilisateur est definie
  if [ -z "$1"  ]
  then
	echo "Utilisateur vide"
	continue
  fi

}

function get_users () {

  # Requete mysql qui recupere les utilisateurs dans gestioip
  req_get_user=$(mysql --defaults-extra-file=$DB_config_file -s -N -e "$mysql_get_users")
  
  if [ $? -ne 0 ];then
    echo "Erreur dans la requete mysql de recuperation des utilisateurs : req_get_user,mysql_get_users"
    exit 1
  fi

}

# ------------------------------------------------------------------
#			Programme Principal
# ------------------------------------------------------------------

echo
echo "***************************************************************************"
echo "***** Script qui synchronise les utilisateurs entre l ad et gestioip ******"
echo "***************************************************************************"
echo

# -------------- Declaration des variables --------------
# -------------------------------------------------------

IFS_back=${IFS}
# Recupere les utilisateurs et leur groupes correspondant dans gestioip
mysql_get_users="select concat_ws(';',name,group_id) from gestioip.gip_users"
# Requete qui recupere le nom des group de gestioip
mysql_get_group="select concat_ws(';',id,name) from gestioip.gip_user_groups;"


# ---------- Verification de la configuration -----------
# -------------------------------------------------------

echo "************** Check de la configuration *************"
echo
# Appel la fonction qui check la configuration
check_conf


# -------------- Traitement --------------------
# ----------------------------------------------


echo "************* Execution des requetes LDAP et Mysql *************"
echo

# Requete ldap qui recupere les utilisateurs dans l active directory
ldap_req=$(ldapsearch -H ldaps://$LDAP_Host:636 -b "$LDAP_DN" \
-s sub "objectclass=user" sAMAccountName -D "$LDAP_User" -w "$LDAP_Pass" \
| grep 'dn:\|sAMAccountName:' | cut -d':' -f 2 | cut -d, -f 2 | cut -d= -f 2 | sed 'N;s/\n /;/')

if [ $? -ne 0 ] || [ -z "$ldap_req" ];then
  echo "Erreur dans la requete ldap : ldap_req"
  exit 1
fi

# Requete mysql qui recupere le nom des groupes gestioip
req_get_group=$(mysql --defaults-extra-file=$DB_config_file -s -N -e "$mysql_get_group")

if [ $? -ne 0 ] || [ -z "$req_get_group" ];then
  echo "Erreur dans la requete mysql de recuperation des utilisateurs : req_get_group,mysql_get_group"
  exit 1
fi

# Appel la fonction get_users qui recupere les utilisateurs dans gestioip
get_users

echo "  *  Requetes terminees sans erreurs !"

# Modifie le separateur de champs (retour a la ligne)
IFS=$'\n'


# -------- Traitement (Gestioip > LDAP)---------
# ----------------------------------------------

echo
echo "*************** Supprime les utilisateurs qui n existe plus dans l AD (Gestioip > LDAP) ************"
echo

compteur_gestioip_total=0
compteur_gestioip_supp=0

# Verifier si les utilisateurs dans la base de gestioip existe toujours dans l active directory
# Si un utilisateur a ete supprime de l active directory alors il le sera aussi dans la base de gestioip
for mysql_user in $req_get_user
do
  # Appel la fonction qui verifie si la variable est definie
  test_exist_user  "mysql_user"
  
  # Recupere le groupe et l utilisateur mysql
  recup_mysql_user_group
  test_user=0
  compteur_gestioip_total=$(($compteur_gestioip_total + 1))

  for ldap_user in $ldap_req
  do

    # Appel la fonction qui verifie si la variable est definie
    test_exist_user "ldap_user"

    # Recupere le groupe et l utilisateur ldap
    recup_ldap_user_group

    # Appel de la fonction qui compare les utilisateurs    
    compare_gestioip
  done
  # Appel la fonction de supprsssion des utilisateurs
  delete_user

done

# Affichage statistique
echo
echo "***** Statistiques ******"
echo "Nombre d utilisateurs supprime : $compteur_gestioip_supp"
echo "Nombre total d utilisateurs dans gestioip: $compteur_gestioip_total"


# -------- Traitement (LDAP > Gestioip)---------
# ----------------------------------------------

echo
echo "************ Ajoute les utilisateurs manquant dans gestioip (LDAP > Gestioip)  ***********"
echo

# Appel la fonction get_users qui recupere les utilisateurs dans gestioip (changement)
get_users

compteur_ldap_total=0
compteur_ldap_add=0

# Ajoute les utilisateurs manquant dans gestioip en se basant sur l AD
# Parcours les utilisateurs de l active directory
for ldap_user in $ldap_req
do

  # Appel la fonction qui verifie si la variable est definie
  test_exist_user "ldap_user"

  # Recupere le groupe et l utilisateur ldap
  recup_ldap_user_group
  test_user=0
  compteur_ldap_total=$(($compteur_ldap_total + 1))
  # Verifie que chaque utilisateur dans l AD soit dans gestioip
  for mysql_user in $req_get_user
  do

    # Appel la fonction qui verifie si la variable est definie
    test_exist_user "mysql_user"

    # Recupere le groupe et l utilisateur mysql
    recup_mysql_user_group

    # Appel de la fonction qui compare les utilisateurs
    compare_ldap
  done
  # Appel de la focntion qui cree les utilisateurs
  create_user
done

# Affichage statistique
echo
echo "***** Statistiques ******"
echo "Nombre d utilisateurs ajoute : $compteur_ldap_add"
echo "Nombre total d utilisateurs dans l AD: $compteur_ldap_total"

# Restoration du sérarateur de champs
IFS=${IFS_back}

echo
echo "****************** Script termine avec succes !!! ******************"
echo
