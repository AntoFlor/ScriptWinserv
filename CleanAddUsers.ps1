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
        Write-Host "An error occurend while creating group $group_name.`nError: ${_}" -ForegroundColor Red
    }
}

function generate_password{
    Add-Type -AssemblyName System.Web
    $pwd = $([System.Web.Security.Membership]::GeneratePassword(20,5))
    return $pwd
}

function create_organizational_units_and_GGs_from_csv{
    # Create root department OU
    if (-not (Get-ADOrganizationalUnit -Filter "distinguishedName -eq 'OU=Departement,DC=espagne,DC=lan'")){
        New-ADOrganizationalUnit -Name "Departement" -Path "DC=espagne,DC=lan" -ErrorAction Stop
    }

    create_common_group

    foreach ($user in $users) {
        Try {
            $department = $user | Select-Object -ExpandProperty Departement
            $department = $department.Replace(" ", "_")
            $parent_ou = "OU=Departement,DC=espagne,DC=lan"

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
                    Write-Host "Created OU=$($separated[1]),$parent_ou" -ForegroundColor Green
                    create_global_group $separated[1] "OU=$($separated[1]),$parent_ou"
                    Write-Host "Created GG_$($separated[1])" -ForegroundColor Green
                    add_global_group_to_common_group "GG_$($separated[1])"
                }
                $user_path = "OU=$($separated[1]),$parent_ou"

                $parent_ou = "OU=$($separated[1]),$parent_ou"
                $new_ou = "OU=$($separated[0]),$parent_ou"
                if (-not (Get-ADOrganizationalUnit -Filter "distinguishedName -eq '$new_ou'")){
                    New-ADOrganizationalUnit -Name $separated[0] -Path $parent_ou -ErrorAction Stop
                    Write-Host "Created OU=$($separated[0]),$parent_ou" -ForegroundColor Green
                    create_global_group $separated[0] "OU=$($separated[0]),$parent_ou"
                    Write-Host "Created GG_$($separated[0])" -ForegroundColor Green
                    add_global_group_to_other_global_group "GG_$($separated[1])" "GG_$($separated[0])"
                }
                $user_path = "OU=$($separated[0]),$parent_ou"
                $global_group = "GG_$($separated[0])"
            } else{
                New-ADOrganizationalUnit -Name $department -Path $parent_ou -ErrorAction Stop
                Write-Host "Created OU=$department,$parent_ou" -ForegroundColor Green
                create_global_group $department "OU=$department,$parent_ou"
                Write-Host "Created GG_$department" -ForegroundColor Green
                add_global_group_to_common_group "GG_${department}"
                $user_path = "OU=$department,$parent_ou"
                $global_group = "GG_${department}"
            }

            create_user $user $user_path $global_group
        } Catch {
            Write-Host "An error occured while creating the following OU: $department.`nError: ${_}"  -ForegroundColor Red
        }
    }
    setup_common_group
}

function create_common_group{
     # Lecture pour tous et ecriture pour la direction
     Try{
        $common_group_name = "GG_Commun"
        New-ADGroup -Name $common_group_name -GroupScope Global -Path "OU=Departement,DC=espagne,DC=lan" -ErrorAction Stop
        Write-Host "$common_group_name was successfully created." -ForegroundColor Green
    } Catch{
        Write-Host "An error occured while creating $common_group_name.`nError: ${_}" -ForegroundColor Red
    }
}

function add_global_group_to_common_group{
    param($group_to_add)
    Try{
        $common_group_name = "GG_Commun"
        $group_to_add = Get-ADGroup $group_to_add
        $common_group = Get-ADGroup $common_group_name
        Add-ADGroupMember -Identity $common_group -Members $group_to_add
    } Catch{
        Write-Host "An error occured while adding global group to common group.`nError: ${_}" -ForegroundColor Red
    }
}

function add_global_group_to_other_global_group{
    param($parent_group, $child_group)

    Try{
        $parent_group = Get-ADGroup $parent_group
        $child_group = Get-ADGroup $child_group
        Add-ADGroupMember -Identity $parent_group -Members $child_group
    } Catch{
        Write-Host "An error occured while adding global group to other global group.`nError: ${_}" -ForegroundColor Red
    }
}

function setup_common_group{
    Try{
        $common_group_name = "GG_Commun"
        $common_group = Get-ADGroup $common_group_name
        Set-ADGroup $common_group -GroupCategory:Security
        Set-ADGroup $common_group -ManagedBy "CN=GG_Direction,OU=Direction,OU=Departement,DC=espagne,DC=lan"
    } Catch{
        Write-Host "An error occured while configuring $common_group_name.`nError: ${_}" -ForegroundColor Red
    }
}

function store_user_account_locally{
    param($user, $password)

    Try{
        "${user}:${password}" >> logins.txt
    } Catch{
        Write-Host "An error occured while saving the user locally.`nError: ${_}" -ForegroundColor Red
    }
}

function create_user{
    param ($user, $path, $global_group)

    $firstname = $user | Select-Object -ExpandProperty Prenom
    $lastname = $user | Select-Object -ExpandProperty Nom
    $office = $user | Select-Object -ExpandProperty Bureau
    $department = $user | Select-Object -ExpandProperty Departement
    $department = $department.Replace(" ", "_")
    $separated_office = $office -split " "
    $office_number = $separated_office[1]

    $samAccountName = "$($firstname.ToLower()).$($lastname.ToLower())"
    $logonName = "${samAccountName}@espagne.lan"

    if ($samAccountName.Length -gt 20){
        # Try to shorten the samAccountName
        $firstNameInitial = $firstname.Substring(0, 1)
        $samAccountName = "${firstNameInitial}.${lastname}"

        # Check if user input is needed
        if ($samAccountName.Length -gt 20){
            $error = $true
            Write-Host "Error: samAccountName ${samAccountName} is too long!" -ForegroundColor Red
            Write-Host "Please enter a new samAccountName for user ${firstname} ${lastname}"
            while ($error){
                $samAccountNameInput = Read-Host "New samAccountName"
                if ($samAccountNameInput) {
                    $samAccountName = $samAccountNameInput
                    $samAccountName = $samAccountName.ToLower()
                    $samAccountName = $samAccountName.Replace(' ','')
                    # check if the user already exists
                    if ($(Get-ADUser -Filter "Name -like '$samAccountName'")){
                        Write-Host "Error: This user already exists!" -ForegroundColor Red
                        continue
                    } elseif ($samAccountName.Length -gt 20){
                        Write-Host "Error: samAccountName is too long!" -ForegroundColor Red
                        continue
                    }
                    $error = $false
                }
            }
        } elseif ($(Get-ADUser -Filter "Name -like '$samAccountName'")){
            $error = $true
            Write-Host "Error: User ${samAccountName} already exists!" -ForegroundColor Red
            Write-Host "Please enter a new samAccountName for user ${firstname} ${lastname}"
            while ($error){
                $samAccountNameInput = Read-Host "New samAccountName"
                if ($samAccountNameInput) {
                    $samAccountName = $samAccountNameInput
                    $samAccountName = $samAccountName.ToLower()
                    $samAccountName = $samAccountName.Replace(' ','')
                    # check if the user already exists
                    if ($(Get-ADUser -Filter "Name -like '$samAccountName'")){
                        Write-Host "Error: This user already exists!" -ForegroundColor Red
                        continue
                    } elseif ($samAccountName.Length -gt 20){
                        Write-Host "Error: samAccountName is too long!" -ForegroundColor Red
                        continue
                    }
                    $error = $false
                }
            }
        }
        $samAccountName = $samAccountName.ToLower()
        $samAccountName = $samAccountName.Replace(' ','')
        $logonName = "${samAccountName}@espagne.lan"
    }

    $password = generate_password
    
    $userParams = @{
        SamAccountName    = $samAccountName
        UserPrincipalName = $logonName
        Name              = $samAccountName
        GivenName         = $firstname
        Surname           = $lastname
        Path              = $path
        Office            = $office_number
        AccountPassword   = ConvertTo-SecureString $password -AsPlainText -Force
		Enabled           = $true
    }
    try {
        if (-not $(Get-ADUser -Filter "Name -like '$samAccountName'")){
            New-ADUser @userParams -ErrorAction Stop
            Write-Host "User ${samAccountName} successfully created." -ForegroundColor Green
            store_user_account_locally $samAccountName $password
            Write-Host "User ${samAccountName} saved locally." -ForegroundColor Green
        } else{
            Write-Host "Error: User ${samAccountName} already exists!" -ForegroundColor Red
        }
    } catch {
        write-Host "An error occured while creating new user ${firstname} ${lastname}.`nError: ${_}" -ForegroundColor Red
    }

    
    # Add user to its department global group
    $group = Get-ADGroup -Filter "Name -eq '$global_group'"
    try {
        Add-ADGroupMember -Identity $group -Members $samAccountName -ErrorAction Stop
        Write-Host "User ${samAccountName} successfully added to $global_group." -ForegroundColor Green
    } catch {
        Write-Host "An error occured while adding ${samAccountName} to $global_group`nError: ${_}" -ForegroundColor Red
    }

    <#
    # CrÃƒÂ©er un dossier partagÃƒÂ© pour l'utilisateur dans le format "D:\Shared\<Department>\<Username>"
    $folderPath = "D:\Shared\" + $Department + "\" + $samAccountName
    try {
        New-Item -ItemType Directory -Path $folderPath -ErrorAction Stop
        Write-Host "Dossier partagÃƒÂ© $($folderPath) cree© avec succes."
    } catch {
        Write-Host "Erreur lors de la crÃƒÂ©ation du dossier partagÃƒÂ© $($folderPath) : $_"
    }
    #>
    
}
#create_common_group
create_organizational_units_and_GGs_from_csv
