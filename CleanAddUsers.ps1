$users = Import-Csv -Path "./users.csv" -Delimiter ";"

# TODO: remove accents in csv
function create_organizational_units_from_csv{
    $departments = $users | Select-Object -ExpandProperty Departement
    foreach ($department in $departments) {
        try {
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
                }

                $parent_ou = "OU=$($separated[1]),$parent_ou"
                $new_ou = "OU=$($separated[0]),$parent_ou"
                if (-not (Get-ADOrganizationalUnit -Filter "distinguishedName -eq '$new_ou'")){
                    New-ADOrganizationalUnit -Name $separated[0] -Path $parent_ou -ErrorAction Stop
                    Write-Host "Created OU=$($separated[0]),$parent_ou"
                }
            } else{
                New-ADOrganizationalUnit -Name $department -Path $parent_ou -ErrorAction Stop
                Write-Host "Created OU=$department,$parent_ou"
            }
        } catch {
            Write-Host "Erreur lors de la creation de l'OU $department.`nError: ${_}"
        }
    }
}
