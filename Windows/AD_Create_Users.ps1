<#

.Synopsis
   Permet la création des ou, des groupes et des utilisateur du domaine BORA.nc

.DESCRIPTION
   Permet de crée les Unité d'organisation et les groupes respectifs suivantes :
        - Direction
        - Autres Services
            - Accueil
            - Conciergerie
            - Parkings
            - Restauration
            - Spa
            - Nettoyage
        - Services informatique
   Permet de créer les utilisateur à partir de fichier csv !

.EXAMPLE
   ./Nom du script

.INPUTS
   Pas d'entrée en pipe possible

.OUTPUTS
   
.NOTES
    NAME:    Ad ppe Deploi
    AUTHOR:    Fabien Mauhourat

    VERSION HISTORY:

    1.5     2017.06.04
            Initial Version

.FUNCTIONALITY
   Création des users,groups et OU

#>

Param(
    $VerbosePreference
)

function Create-Aduser { 
    Param( 
        $compte_func,$groups_func,$ou_func,$domaine_func,$expire_func
    )
    $Error.clear()
    $splatting = @{
        Name = $compte_func.Name
        SamAccountName = $compte_func.SAMAccountName
        GivenName = $compte_func.Surname
        Surname = $compte_func.GivenName
        DisplayName = $compte_func.Name
        Path = "$ou_func,$domaine_func"
    }
    Write-Debug "Création du compte utilisateur $compte_func.Name"
    New-ADUser @splatting -AccountPassword (ConvertTo-SecureString "Admin2017" -AsPlainText -Force) -Enabled $true -ChangePasswordAtLogon $true -PasswordNeverExpires $expire_func
    Write-Debug "Ajout du compte $compte_func.Name au groupe $groups_func"
    Add-ADGroupMember $groups_func $compte_func.SAMAccountName

    Write-Verbose "Utilisateur a bien été crée : $($compte_func.Name)"
    Write-Verbose "Utilisateur a bien été ajouté au groupe : $groups_func"
}

write-output "##############################################################################################"
write-output "################## Script Création des utilisateurs dans l'active directory ##################"
write-output "##############################################################################################"

# Déclaration des variables
[cmdletbinding()]
$ErrorActionPreference='Stop'
#$VerbosePreference = "continue"
$domaine ="DC=bora,DC=nc"
$dom=(Get-ADDomain  | select DistinguishedName)
$ouracine = "Direction","Service informatique","Autres services"
$ouservices = "Accueil","Conciergerie","Parkings","Restauration","Spa","Nettoyage"
$groups = "Direction","Service informatique","Autres services"
#$adusers = Get-ADUser -Filter SAMAccountName

if ( ![bool]((whoami /all) -match "S-1-16-12288") ) {
    Write-Error "Le script doit s'éxecuter en tant qu'administrateur !"
}

if( !($dom.DistinguishedName).Equals($domaine) )
{
	Write-Error "Le domaine $domaine n'existe pas !"
}
else {
	Write-Verbose "Le domaine $domaine existe !"
}

write-output "`n"
Write-Host "#####  Vérifier si les ou existe. #####" -foregroundcolor green
write-output "`n"

Foreach($valeur in $ouracine)
{
	$Path = "OU=$valeur,$domaine"
	if(![adsi]::Exists("LDAP://$Path"))
	{
		write-output "Création de l'ou : $valeur"
		NEW-ADOrganizationalUnit $valeur –path "$domaine"
	}
	else {
		write-output "L'ou $valeur existe déjà !"
	}
}

Foreach($valeur in $ouservices)
{
	$Path = "OU=$valeur,OU=Autres services,$domaine"
	if(![adsi]::Exists("LDAP://$Path"))
	{
		write-output "Création de l'ou : $valeur"
		NEW-ADOrganizationalUnit $valeur –path "OU=Autres services,$domaine"
	}
	else {
		write-output "L'ou $valeur existe déjà !"
	}
}

write-output "`n"
Write-Host "#####  Vérifier si les groupes existe. #####" -foregroundcolor green
write-output "`n"

Foreach($valeur in $groups)
{
	$Path = "CN=$valeur,CN=Builtin,$domaine"
	if(![adsi]::Exists("LDAP://$Path"))
	{
		write-output "Création du groupe : $valeur"
		NEW-ADGroup –name $valeur –groupscope Global –path "CN=Builtin,$domaine"
	}
	else {
		write-output "Le groupe $groups existe déjà !"
	}
}
write-output "`n"
Write-Host "##### Recherche fichier csv. #####" -foregroundcolor green

$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
cd $scriptPath

foreach ( $file in  (dir | where {$_.name -like "*.csv"} | select Name) ) {
    $ou=$null
    $ousplit = ($file.Name).split(".",2)
    write-output "`n"
    Write-Host "Création des utilisateurs pour le service : " $ousplit[0] -foregroundcolor red
    write-output "`n"

    #if (($file -match "Accueil.csv") -or ($file -match "Conciergerie.csv") -or ($file -match "Nettoyage.csv") -or ($file -match "Parkings.csv") -or ($file -match "Restauration.csv") -or ($file -match "Spa.csv")) {
    ForEach ( $file_test in $ouservices ) {
        if ( $file_test -match $ousplit[0] ) {
            $OU="OU=" + $ousplit[0] + ",OU=Autres services"
            $groups_file = $groups[2]
            $expire = $false
        }
    }
    if ($file -match "Direction.csv") {
        $OU="OU=" + $ousplit[0]
        $groups_file = $groups[0]
        $expire = $false
	}
    elseif ($file -match "Informaticiens.csv") {
        $OU="OU=Service Informatique"
        $groups_file = $groups[1]
        $expire = $false
	}
    if ( $ou -eq $null ) {
        Write-Error "Les fichier CSV sont manquant"
        break
    }
    Write-Debug "Fichier $file.name"
    $adusers = (Get-ADUser -filter * -SearchBase "$OU,$domaine" | select samaccountname)
    $compteur = 1
    $compte_createdelete = Import-Csv $file.Name -Delimiter ','
    Write-Verbose "$adusers,$compteur,$compte_create"
    foreach ( $compte in $compte_createdelete ) {
        Write-Progress -Activity "Creation des compte utilisateurs pour : $($ousplit[0])" -CurrentOperation $compte.Name -PercentComplete (($compteur / ($compte_createdelete).count) * 100)
        $compteur++
        #if ( (@(Get-ADUser -Filter { SAMAccountName -eq $compte.SAMAccountName }).Count) -eq 0 ) {
        #if ( @(($adusers).SamAccountName -eq $compte.SAMAccountName).Count -eq 0 ) {
        if ( !(($adusers).SamAccountName -eq $compte.SAMAccountName) ) {
            #write-output "`n"
            Write-Verbose "L'utilisateur $($compte.Name) n'existe pas !"
			
            Create-Aduser -compte_func $compte -groups_func $groups_file -ou_func $OU -domaine_func $domaine -expire_func $expire

        }
		else {
            #write-output "`n"
			Write-Verbose "L'utilisateur $($compte.Name) existe déjà !"
		}
        Start-Sleep -Milliseconds 10
    }

    write-output "`n"
    Write-Host "Désactivation des utilisateurs pour le service : " $ousplit[0] -foregroundcolor red
    write-output "`n"

    $adusers = (Get-ADUser -filter * -SearchBase "$OU,$domaine" | select samaccountname)
    $compteur = 1
    $test_user=$false
    foreach ( $compte in $adusers ) {
        Write-Progress -Activity "Desactivation des compte non utiliser pour : $($ousplit[0])" -CurrentOperation $compte.samaccountname -PercentComplete (($compteur / ($adusers).count) * 100)
        $compteur++
        if ( !($compte_createdelete.SAMAccountName -eq $compte.samaccountname) ) {
                #write-output "`n"
                Write-Verbose "L'utilisateur $($compte.SAMAccountName) n'existe plus !"
			
                Write-Debug "Désactivation du compte utilisateur : $($compte.SAMAccountName)!"
                Get-ADUser $compte.samaccountname | Disable-ADAccount
                Write-Verbose "Compte $($compte.SAMAccountName) désactiver"
        }
        else {
                Write-Verbose "Compte $($compte.SAMAccountName) encore en activité"
        }
        Start-Sleep -Milliseconds 10
    }
}

pause