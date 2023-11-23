param(
    [string]$action = "help"
)

$users = Import-Csv -Path "./formated_users.csv" -Delimiter ";"

##### BEGIN UTILITIES #####
function print_help{
    Write-Host ""
    Write-Host "########################################"
    Write-Host "### WindowsServer 2019 config script ###"
    Write-Host "########################################"
    Write-Host ""
    Write-Host "Arguments:"
    Write-Host "-action [help | basic_config | adds_setup | populate_adds]"
    Write-Host ""
}

function Read-Host-Trim{
    param(
        [string]$msg
    )
    $in = Read-Host $msg
    return $in.Trim()
}

function Read-Host-Trim-ToLower{
    param(
        [string]$msg
    )
    $in = Read-Host-Trim $msg
    return $in.ToLower()
}

function generate_password{
    param($size)
    $password = get_random_characters -length $($size - 3) -characters 'abcdefghiklmnoprstuvwxyz'
    $password += get_random_characters -length 1 -characters 'ABCDEFGHKLMNOPRSTUVWXYZ'
    $password += get_random_characters -length 1 -characters '1234567890'
    $password += get_random_characters -length 1 -characters '!"§$%&/()=?}][{@#*+'
    return $password
}
##### END UTILITIES #####



##### BEGIN NETOWRK CONFIG #####
function network_config{
    $ip_string = Read-Host-Trim "Ip address"
    $ip_address = [System.Net.IPAddress]::Parse($ip_string)

    $subnet_mask_string = Read-Host-Trim "Subnet mask"
    $subnet_mask = [Byte]$subnet_mask_string

    $default_gateway_string = Read-Host-Trim "Default gateway"
    $default_gateway_address = [System.Net.IPAddress]::Parse($default_gateway_string)

    Write-Host ""
    # Display interfaces for the user to choose from
    Get-NetIPInterface
    Write-Host ""
    $interface_alias = Read-Host-Trim "Interface alias"

    New-NetIPAddress -IPAddress $ip_address -PrefixLength $subnet_mask -DefaultGateway $default_gateway_address -InterfaceAlias $interface_alias -ErrorAction Stop | Out-Null
    Write-Host "IP address successfully set to ${ip_address}, subnet ${subnet_mask}, default gateway ${default_gateway_address}" -ForegroundColor Green
}

function rdp_config{
    $choice = Read-Host-Trim-ToLower "Would you like to enable RDP? (yes/no)"
    if ($choice -eq "yes"){
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0 -ErrorAction Stop
        Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction Stop
        Write-Host "RDP Successfully enabled" -ForegroundColor Green
    } elseif ($choice -eq "no"){
        Write-Host "RDP remains disabled" -ForegroundColor Green
    } else{
        throw "Invalid choice, please choose between 'yes' and 'no'"
    }
}

function basic_config{
    Write-Host "Starting network configuration"
    Try{
        network_config
    } Catch{
        Write-Warning -Message "Failed to apply network settings.`nError: ${_}"
        Break;
    }

    Write-Host "Starting RDP configuration"
    Try{
        rdp_config
    } Catch{
        Write-Warning -Message "Failed to apply rdp settings.`nError: ${_}"
        Break;
    }

    Write-Host "Basic config finished" -ForegroundColor Green
    Write-Host "Rebooting in 15 seconds, press CTRL+C to cancel"
    Sleep 15
    Try{
        Restart-Computer -ComputerName $env:COMPUTERNAME -ErrorAction Stop
        Write-Host "Rebooting now" -ForegroundColor Green
    } Catch{
        Write-Warning -Message "Failed to reboot.`nError: ${_.Exception.Message}"
        Break;
    }
}
##### END NETWORK CONFIG #####



##### BEGIN ADDS SETUP #####
function adds_install{
    Install-WindowsFeature -name AD-Domain-Services -IncludeManagementTools -ErrorAction Stop
    Write-Host "Active Directory Domain Services installed" -ForegroundColor Green
}

function adds_config{
    $domain_name = Read-Host-Trim-ToLower "Domain name"
    Install-ADDSForest -DomainName $domain_name -InstallDNS -ErrorAction Stop -NoRebootOnCompletion
}

function adds_setup{
    Write-Host "Starting ADDS install"
    Try{
        adds_install
    } Catch{
        Write-Warning -Message "Failed to install Active Directory Domain Services.`nError: ${_}"
        Break;
    }

    Try{
        adds_config
    } Catch{
        Write-Warning -Message "Failed to configure Active directory Domain Services.`nError: ${_}"
    }
}
##### END ADDS SETUP ######



##### BEGIN CSV READING #####
function create_global_group{
    param(
        [string]$department,
        [string]$path
    )

    $group_name = "GG_${department}"
    Try{
        New-ADGroup -Name $group_name -GroupScope Global -Path $path -ErrorAction Stop
        Write-Host "Created $group_name" -ForegroundColor Green
    } Catch{
        Write-Host "An error occurend while creating group $group_name.`nError: ${_}" -ForegroundColor Red
    }
}

function create_local_group{
    param(
        [string]$department,
        [string]$path
    )

    $group_name = "GL_${department}"
    Try{
        New-ADGroup -Name $group_name -GroupScope DomainLocal -Path $path -ErrorAction Stop
        Write-Host "Created $group_name" -ForegroundColor Green
    } Catch{
        Write-Host "An error occurend while creating local group $group_name.`nError: ${_}" -ForegroundColor Red
    }
}

function get_random_characters($length, $characters) { 
    $random = 1..$length | ForEach-Object { Get-Random -Maximum $characters.length } 
    $private:ofs="" 
    return [String]$characters[$random]
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
                    create_local_group "$($separated[1])_R" "OU=$($separated[1]),$parent_ou"
                    create_local_group "$($separated[1])_RW" "OU=$($separated[1]),$parent_ou"

                    add_global_group_to_common_group "GG_$($separated[1])"
                    add_group_to_other_group "GL_$($separated[1])_R" "GG_$($separated[1])"
                    add_group_to_other_group "GL_$($separated[1])_RW" "GG_$($separated[1])"
                }
                $user_path = "OU=$($separated[1]),$parent_ou"

                $parent_ou = "OU=$($separated[1]),$parent_ou"
                $new_ou = "OU=$($separated[0]),$parent_ou"
                if (-not (Get-ADOrganizationalUnit -Filter "distinguishedName -eq '$new_ou'")){
                    New-ADOrganizationalUnit -Name $separated[0] -Path $parent_ou -ErrorAction Stop
                    Write-Host "Created OU=$($separated[0]),$parent_ou" -ForegroundColor Green

                    create_global_group $separated[0] "OU=$($separated[0]),$parent_ou"
                    create_local_group "$($separated[0])_R" "OU=$($separated[0]),$parent_ou"
                    create_local_group "$($separated[0])_RW" "OU=$($separated[0]),$parent_ou"

                    add_group_to_other_group "GG_$($separated[1])" "GG_$($separated[0])"
                    add_group_to_other_group "GL_$($separated[0])_R" "GG_$($separated[0])"
                    add_group_to_other_group "GL_$($separated[0])_RW" "GG_$($separated[0])"
                }
                $user_path = "OU=$($separated[0]),$parent_ou"
                $global_group = "GG_$($separated[0])"
            } else{
                New-ADOrganizationalUnit -Name $department -Path $parent_ou -ErrorAction Stop
                Write-Host "Created OU=$department,$parent_ou" -ForegroundColor Green

                create_global_group $department "OU=$department,$parent_ou"
                add_global_group_to_common_group "GG_${department}"

                create_local_group "${department}_R" "OU=$department,$parent_ou"
                create_local_group "${department}_RW" "OU=$department,$parent_ou"

                add_group_to_other_group "GL_${department}_R" "GG_${department}"
                add_group_to_other_group "GL_${department}_RW" "GG_${department}"
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
     Try{
        $common_group_name = "GG_Commun"
        New-ADGroup -Name $common_group_name -GroupScope Global -Path "OU=Departement,DC=espagne,DC=lan" -ErrorAction Stop
        Write-Host "$common_group_name was successfully created." -ForegroundColor Green
    } Catch{
        Write-Host "An error occured while creating $common_group_name.`nError: ${_}" -ForegroundColor Red
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

function add_group_to_other_group{
    param($parent_group, $child_group)

    Try{
        $parent_group = Get-ADGroup $parent_group
        $child_group = Get-ADGroup $child_group
        Add-ADGroupMember -Identity $parent_group -Members $child_group
    } Catch{
        Write-Host "An error occured while adding global group to other global group.`nError: ${_}" -ForegroundColor Red
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
    $phone = $user | Select-Object -ExpandProperty N_Interne
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
    if ($path -eq "OU=Direction,OU=Departement,DC=espagne,DC=lan"){
        $password = generate_password 15
    } else{
        $password = generate_password 7
    }
    
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
			Set-ADUser -Identity $samAccountName -Replace @{'ipPhone'=$phone}
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
}
##### END CSV READING #####



Switch ($action){
    "help"{print_help}
    "basic_config"{basic_config}
    "adds_setup"{adds_setup}
    "populate_adds"{create_organizational_units_and_GGs_from_csv}
    default{print_help}
}
