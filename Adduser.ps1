# Importer les données depuis le fichier CSV
$users = Import-Csv -Path ".\users.csv"

# Créer les unités d'organisation (OU) pour chaque département
$departments = $users | Select-Object -Property Department -Unique

foreach ($department in $departments) {
    $ouName = $department.Department
    New-ADOrganizationalUnit -Name $ouName -Path "DC=Espagne,DC=lan"
}

# Créer les groupes pour chaque département
foreach ($department in $departments) {
    $groupName = $department.Department + " Group"
    New-ADGroup -Name $groupName -GroupScope Global -Path "OU=" + $department.Department + ",DC=Espagne,DC=lan"
}

# Créer les utilisateurs
foreach ($user in $users) {
    $userParams = @{
        SamAccountName = $user.DisplayName
        UserPrincipalName = $user.upn + "@es.lan"
        Name = $user.DisplayName
        GivenName = $user.givenname
        Surname = $user.surname
        Department = $user.Department
        Country = $user.country
        Path = "OU=" + $user.Department + ",DC=Espagne,DC=lan"
    }

    New-ADUser @userParams

    # Ajouter l'utilisateur au groupe de son département
    $group = Get-ADGroup -Filter { Name -eq ($user.Department + " Group") }
    Add-ADGroupMember -Identity $group -Members $user.DisplayName
    
    # Créer un dossier partagé pour l'utilisateur dans le format "D:\Shared\<Department>\<Username>"
    $folderPath = "D:\Shared\" + $user.Department + "\" + $user.DisplayName
    New-Item -ItemType Directory -Path $folderPath

    }
    
