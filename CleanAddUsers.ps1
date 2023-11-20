$users = Import-Csv -Path "./users.csv" -Delimiter ";"

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

# TODO: remove accents
function create_organizational_units_and_GGs_from_csv{
    # Create root department OU
    if (-not (Get-ADOrganizationalUnit -Filter "distinguishedName -eq 'OU=departement,DC=espagne,DC=lan'")){
        New-ADOrganizationalUnit -Name "departement" -Path "DC=espagne,DC=lan" -ErrorAction Stop
    }

    $departments = $users | Select-Object -ExpandProperty Departement
    foreach ($department in $departments) {
        Try {
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
