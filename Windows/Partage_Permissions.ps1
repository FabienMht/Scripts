<#

.Synopsis
   Permet la création des partages ainsi que des droits sur les partages !

.DESCRIPTION
   Permet de crée les partages suivantes :
        - Direction
        - Autres Services
        - Services informatique
        - Logiciels
   Permet d'appliquer les droits sur les partages !

.EXAMPLE
   ./Nom du script

.INPUTS
   Pas d'entrée en pipe possible

.OUTPUTS

.NOTES
    NAME:    Ad ppe Partageperm
    AUTHOR:    Fabien Mauhourat

    VERSION HISTORY:

    1.5     2017.06.04
            Initial Version

.FUNCTIONALITY
   Création des partages,et des droits sur les partages

#>


write-output "##################################################################"
write-output "################## Script Création des partages ##################"
write-output "##################################################################"

if ( ![bool]((whoami /all) -match "S-1-16-12288") ) {
    Write-Error "Le script doit s'éxecuter en tant qu'administrateur !"
}

# Déclaration des variables
[cmdletbinding()]
$ErrorActionPreference='Stop'
$Destination = "E:"
$dossier = "Direction","Service Informatique","Autres services","Logiciels","Sauvegarde Proxy"

write-host "`n"
write-host "Création des Dossier et application des permissions" -ForegroundColor Green
write-host "`n"

foreach ( $folders in $dossier ) {
    
    if (! (Test-Path "$Destination\$folders") ) {
        Write-Output "Création et apllication despermissionsdu dossier $folders"
        New-Item -Name "$folders" -Path "$Destination" -ItemType "directory" > $null

        if ( $folders -like "Direction" ) {
            New-SmbShare -Name "Direction" -Path $destination\$folders -FullAccess Direction,
            "Service informatique",Administrateurs -NoAccess "Autres services" > $null
            Write-Verbose "Partage du dossier $folders terminé !"

            Write-Verbose "Application des droits sur le dossier $folders"
            icacls $destination\$folders /grant:r "Direction:(OI)(CI)(F)" /T >$null
            icacls $destination\$folders /deny "Autres services:(OI)(CI)(F)" /T >$null
            icacls $destination\$folders /grant:r "Service Informatique:(OI)(CI)(F)" /T >$null
        }
        elseif ( $folders -like "Service Informatique" ) {
            New-SmbShare -Name "Service-Informatique" -Path $destination\$folders -FullAccess Direction,
            "Service informatique",Administrateurs -NoAccess Direction,"Autres services" > $null
            Write-Verbose "Partage du dossier $folders terminé !"

            Write-Verbose "Application des droits sur le dossier $folders"
            icacls $destination\$folders /deny "Direction:(OI)(CI)(F)" /T >$null
            icacls $destination\$folders /deny "Autres services:(OI)(CI)(F)" /T >$null
            icacls $destination\$folders /grant:r "Service Informatique:(OI)(CI)(F)" /T >$null
        }
        elseif ( $folders -like "Autres services" ) {
            New-SmbShare -Name "Autres-services" -Path $destination\$folders -FullAccess Direction,
            "Service informatique",Administrateurs,"Autres services" -NoAccess Direction > $null
            Write-Verbose "Partage du dossier $folders terminé !"

            Write-Verbose "Application des droits sur le dossier $folders"
            icacls $destination\$folders /deny "Direction:(OI)(CI)(F)" /T >$null
            icacls $destination\$folders /grant:r "Autres services:(OI)(CI)(F)" /T >$null
            icacls $destination\$folders /grant:r "Service Informatique:(OI)(CI)(F)" /T >$null
        }
        elseif ( $folders -like "Logiciels" ) {
            New-SmbShare -Name "Logiciels" -Path $destination\$folders -FullAccess "Service informatique",
            Administrateurs -ReadAccess Direction,"Autres services" > $null
            Write-Verbose "Partage du dossier $folders terminé !"

            Write-Verbose "Application des droits sur le dossier $folders"
            icacls $destination\$folders /grant:r "Direction:(OI)(CI)(R)" /T >$null
            icacls $destination\$folders /grant:r "Autres services:(OI)(CI)(R)" /T >$null
            icacls $destination\$folders /grant:r "Service Informatique:(OI)(CI)(F)" /T >$null
        }
        elseif ( $folders -like "Sauvegarde Proxy" ) {
            New-SmbShare -Name "Sauvegarde Proxy" -Path $destination\$folders -FullAccess "Service informatique",
            Administrateurs -NoAccess Direction,"Autres services" > $null
            Write-Verbose "Partage du dossier $folders terminé !"

            Write-Verbose "Application des droits sur le dossier $folders"
            icacls $destination\$folders /deny "Direction:(OI)(CI)(R)" /T >$null
            icacls $destination\$folders /deny "Autres services:(OI)(CI)(R)" /T >$null
            icacls $destination\$folders /grant:r "Service Informatique:(OI)(CI)(F)" /T >$null
        }
    } 
    else {
        Write-Output "Le dossier $folders existe déjà !"
    }
}

pause