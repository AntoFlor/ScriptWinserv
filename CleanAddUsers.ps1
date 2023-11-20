$users = Import-Csv -Path "./formated_users.csv" -Delimiter ";"

function create_global_group{
    param(
        [string]$department,
        [string]$path
    )

    $group_name = "GG_${department}"
    Try{
        New-ADGroup -Name $group_name -GroupScope Global -Path $path -ErrorAction Stop
    } Catch{
        Write-Host "Erreur lors de la creation du groupe $group_name.`nError: ${_}"
    }
    
}

function create_organizational_units_and_GGs_from_csv{
    # Create root department OU
    if (-not (Get-ADOrganizationalUnit -Filter "distinguishedName -eq 'OU=departement,DC=espagne,DC=lan'")){
        New-ADOrganizationalUnit -Name "departement" -Path "DC=espagne,DC=lan" -ErrorAction Stop
    }

    $departments = $users | Select-Object -ExpandProperty Departement
    foreach ($department in $departments) {
        Try {
            $department = $department.Replace(" ", "_")
            $parent_ou = "OU=departement,DC=espagne,DC=lan"

            # Check if the OU already exists
            $new_ou = "OU=$department,$parent_ou"
            if (Get-ADOrganizationalUnit -Filter "distinguishedName -eq '$new_ou'"){
                continue
            }

            if ($department.Contains("/")){
                $separated = $department -split "/"

                $new_ou = "OU=$($separated[1]),$parent_ou"
                if (-not (Get-ADOrganizationalUnit -Filter "distinguishedName -eq '$new_ou'")){
                    New-ADOrganizationalUnit -Name $separated[1] -Path $parent_ou -ErrorAction Stop
                    Write-Host "Created OU=$($separated[1]),$parent_ou"
                    create_global_group $separated[1] "OU=$($separated[1]),$parent_ou"
                    Write-Host "Created GG_$($separated[1])"
                }

                $parent_ou = "OU=$($separated[1]),$parent_ou"
                $new_ou = "OU=$($separated[0]),$parent_ou"
                if (-not (Get-ADOrganizationalUnit -Filter "distinguishedName -eq '$new_ou'")){
                    New-ADOrganizationalUnit -Name $separated[0] -Path $parent_ou -ErrorAction Stop
                    Write-Host "Created OU=$($separated[0]),$parent_ou"
                    create_global_group $separated[0] "OU=$($separated[0]),$parent_ou"
                    Write-Host "Created GG_$($separated[0])"
                }
            } else{
                New-ADOrganizationalUnit -Name $department -Path $parent_ou -ErrorAction Stop
                Write-Host "Created OU=$department,$parent_ou"
                create_global_group $department "OU=$department,$parent_ou"
                Write-Host "Created GG_$department"
            }
        } Catch {
            Write-Host "Erreur lors de la creation de l'OU $department.`nError: ${_}"
        }
    }
}

function create_common_group{
    # Lecture pour tous et ecriture pour la direction
     Try {
        $common_group_name = "Commun"
        New-ADGroup -Name $common_group_name -GroupScope Global -Path "OU=Departement,DC=espagne,DC=lan" -ErrorAction Stop
        $common_group = Get-ADGroup $common_group_name
        Set-ADGroup $common_group -GroupCategory:Security
        Set-ADGroup $common_group -ManagedBy "CN=GG_Direction,OU=Direction,OU=Departement,DC=espagne,DC=lan"
        #Set-ADGroup $common_group -GroupScope:DomainLocal
        Write-Host "Groupe $common_group_name cree avec succes."
    } Catch{
        Write-Host "Erreur lors de la creation du groupe $common_group_name.`nError: ${_}"
    }
}

function create_users{
    foreach ($user in $users) {
        if ($null -eq $user.Prenom -or $null -eq $user.Nom) {
            Write-Host "Les propriÃ©tÃ©s Prenom ou Nom sont nulles. Utilisateur ignorÃ©."
            continue
        }

        $samAccountName = "espagne\" + $user.Prenom.ToLower()
        $logonName = $user.Prenom.ToLower() + "." + $user.Nom.ToLower() + "@es.lan"

        if ($samAccountName.Length -gt 20) {
            $firstNameInitial = $user.Prenom.Substring(0, 1)
            $samAccountName2 = "espagne\" + $firstNameInitial + "." + $user.Nom
            $logonName = $firstNameInitial + "." + $user.Nom + "es.lan"

            # Demander Ã  l'utilisateur d'Ã©crire manuellement le samAccountName2 si nÃ©cessaire
            if ($samAccountName2.Length -gt 20) {
                $samAccountName2Input = Read-Host "Le samAccountName2 est trop long. Entrez manuellement :"
                if ($samAccountName2Input) {
                    $samAccountName2 = $samAccountName2Input
                }
            }
        }

        # Demander Ã  l'utilisateur d'Ã©crire manuellement le logonName
        $logonNameInput = Read-Host "Entrez le logonName manuellement :"
        if ($logonNameInput) {
            $logonName = $logonNameInput
        }
        $userParams = @{
            SamAccountName    = $samAccountName2
            UserPrincipalName = $logonName
            Name              = $user.Nom
            Surname           = $user.Prenom
            Department        = $user.Departement
            Path              = "OU=" + $user.Departement + ",DC=espagne,DC=lan"
        }

        try {
            New-ADUser @userParams -ErrorAction Stop
            Write-Host "Utilisateur $($user.Prenom) $($user.Nom) crÃ©Ã© avec succÃ¨s."
        } catch {
            Write-Host "Erreur lors de la crÃ©ation de l'utilisateur $($user.Prenom) $($user.Nom) : $_"
        }

        # Ajouter l'utilisateur au groupe de son dÃ©partement
        $group = Get-ADGroup -Filter { Name -eq ($user.Department + " Group") }
        try {
            Add-ADGroupMember -Identity $group -Members $samAccountName -ErrorAction Stop
            Write-Host "Utilisateur $($user.DisplayName) ajoutÃ© au groupe $($group.Name) avec succÃ¨s."
        } catch {
            Write-Host "Erreur lors de l'ajout de l'utilisateur $($user.DisplayName) au groupe $($group.Name) : $_"
        }


    # Ajouter l'utilisateur au groupe "Commun"
        try {
            Add-ADGroupMember -Identity $commonGroup -Members $samAccountName -ErrorAction Stop
            Write-Host "Utilisateur $($user.DisplayName) ajoutÃ© au groupe Commun avec succÃ¨s."
        } catch {
            Write-Host "Erreur lors de l'ajout de l'utilisateur $($user.DisplayName) au groupe Commun : $_"
        }

        # CrÃ©er un dossier partagÃ© pour l'utilisateur dans le format "D:\Shared\<Department>\<Username>"
        $folderPath = "D:\Shared\" + $user.Department + "\" + $samAccountName
        try {
            New-Item -ItemType Directory -Path $folderPath -ErrorAction Stop
            Write-Host "Dossier partagÃ© $($folderPath) crÃ©Ã© avec succÃ¨s."
        } catch {
            Write-Host "Erreur lors de la crÃ©ation du dossier partagÃ© $($folderPath) : $_"
        }
    }
}
