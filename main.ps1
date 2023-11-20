param(
    [string]$action = "help"
)


function print_help{
    Write-Host ""
    Write-Host "########################################"
    Write-Host "### WindowsServer 2019 config script ###"
    Write-Host "########################################"
    Write-Host ""
    Write-Host "Arguments:"
    Write-Host "-action [help | basic_config | adds_setup]"
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

Switch ($action){
    "help"{print_help}
    "basic_config"{basic_config}
    "adds_setup"{adds_setup}
    default{print_help}
}
