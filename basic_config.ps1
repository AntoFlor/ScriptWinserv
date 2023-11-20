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
