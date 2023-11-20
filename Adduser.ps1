# Importer les données depuis le fichier CSV
$users = Import-Csv -Path ".\users.csv"

# Créer les unités d'organisation (OU) pour chaque département
$departments = $users | Select-Object -Property Department -Unique

foreach ($department in $departments) {
    $ouName = $department.Department
    try {
        New-ADOrganizationalUnit -Name $ouName -Path "DC=espagne,DC=lan" -ErrorAction Stop
    } catch {
        Write-Host "Erreur lors de la création de l'OU $ouName : $_"
    }
}

# Créer les groupes pour chaque département
foreach ($department in $departments) {
    $groupName = $department.Department + " Group"
    try {
        New-ADGroup -Name $groupName -GroupScope Global -Path "OU=" + $department.Department + ",DC=espagne,DC=lan" -ErrorAction Stop
    } catch {
        Write-Host "Erreur lors de la création du groupe $groupName : $_"
    }
}

<#  # Créer le groupe "Commun" en lecture pour tous et en écriture pour la direction
 try {
    $commonGroupName = "Commun"
    New-ADGroup -Name $commonGroupName -GroupScope Global -Path "DC=espagne,DC=lan" -ErrorAction Stop
    $commonGroup = Get-ADGroup $commonGroupName
    Set-ADGroup $commonGroup -GroupCategory:Security
    Set-ADGroup $commonGroup -ManagedBy "CN=Direction,DC=espagne,DC=lan"
    Set-ADGroup $commonGroup -Members "Everyone"
    Set-ADGroup $commonGroup -GroupScope:DomainLocal
    Write-Host "Groupe $commonGroupName créé avec succès."
} catch {
    Write-Host "Erreur lors de la création du groupe $commonGroupName : $_"
} #>

# Créer les utilisateurs
foreach ($user in $users) {
    $samAccountName = "espagne\" + $user.Prenom.ToLower()
    $logonName = $user.Prenom.ToLower() + "." + $user.Nom.ToLower() + "@es.lan"

        # Demander à l'utilisateur d'écrire manuellement le samAccountName2 si nécessaire
        if ($samAccountName2.Length -gt 20) {
            $samAccountName2Input = Read-Host "Le samAccountName2 est trop long. Entrez manuellement :"
            if ($samAccountName2Input) {
                $samAccountName2 = $samAccountName2Input
            }
        }

    # Demander à l'utilisateur d'écrire manuellement le logonName
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
        Write-Host "Utilisateur $($user.Prenom) $($user.Nom) créé avec succès."
    } catch {
        Write-Host "Erreur lors de la création de l'utilisateur $($user.Prenom) $($user.Nom) : $_"
    }

    # Ajouter l'utilisateur au groupe de son département
    $group = Get-ADGroup -Filter { Name -eq ($user.Department + " Group") }
    try {
        Add-ADGroupMember -Identity $group -Members $samAccountName -ErrorAction Stop
        Write-Host "Utilisateur $($user.DisplayName) ajouté au groupe $($group.Name) avec succès."
    } catch {
        Write-Host "Erreur lors de l'ajout de l'utilisateur $($user.DisplayName) au groupe $($group.Name) : $_"
    }

<#     # Ajouter l'utilisateur au groupe "Commun"
    try {
        Add-ADGroupMember -Identity $commonGroup -Members $samAccountName -ErrorAction Stop
        Write-Host "Utilisateur $($user.DisplayName) ajouté au groupe Commun avec succès."
    } catch {
        Write-Host "Erreur lors de l'ajout de l'utilisateur $($user.DisplayName) au groupe Commun : $_"
    }

    # Créer un dossier partagé pour l'utilisateur dans le format "D:\Shared\<Department>\<Username>"
    $folderPath = "D:\Shared\" + $user.Department + "\" + $samAccountName
    try {
        New-Item -ItemType Directory -Path $folderPath -ErrorAction Stop
        Write-Host "Dossier partagé $($folderPath) créé avec succès."
    } catch {
        Write-Host "Erreur lors de la création du dossier partagé $($folderPath) : $_"
    } #>
}
