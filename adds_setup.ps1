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
