param(
    [string]$Ssid,
    [string]$Password,
    [string]$ServerIp,
    [int]$MqttPort = 1883,
    [switch]$SkipUpload,
    [switch]$OpenMonitor
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$firmwarePath = Join-Path $projectRoot "src\main.cpp"

function Read-RequiredValue {
    param(
        [string]$Prompt,
        [string]$CurrentValue
    )

    $message = $Prompt
    if ($CurrentValue) {
        $message = "$Prompt [$CurrentValue]"
    }

    $value = Read-Host $message
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $CurrentValue
    }

    return $value.Trim()
}

if (-not $Ssid) {
    $Ssid = Read-RequiredValue -Prompt "Nom du WiFi" -CurrentValue "EPSI-Lab"
}

if (-not $Password) {
    $Password = Read-RequiredValue -Prompt "Mot de passe du WiFi" -CurrentValue ""
}

if (-not $ServerIp) {
    $ServerIp = Read-RequiredValue -Prompt "IP ou DNS du serveur MQTT distant" -CurrentValue "192.168.1.96"
}

if (-not $MqttPort) {
    $MqttPort = 1883
}

if ([string]::IsNullOrWhiteSpace($Ssid)) {
    throw "Le WiFi est obligatoire."
}

if ([string]::IsNullOrWhiteSpace($Password)) {
    throw "Le mot de passe WiFi est obligatoire."
}

if ([string]::IsNullOrWhiteSpace($ServerIp)) {
    throw "L'adresse du serveur MQTT est obligatoire."
}

$firmware = Get-Content -Path $firmwarePath -Raw
$updatedFirmware = $firmware
$updatedFirmware = [regex]::Replace($updatedFirmware, 'const char\* ssid = ".*?";', ('const char* ssid = "{0}";' -f $Ssid))
$updatedFirmware = [regex]::Replace($updatedFirmware, 'const char\* password = ".*?";', ('const char* password = "{0}";' -f $Password))
$updatedFirmware = [regex]::Replace($updatedFirmware, 'const char\* mqtt_server = ".*?";', ('const char* mqtt_server = "{0}";' -f $ServerIp))
$updatedFirmware = [regex]::Replace($updatedFirmware, 'const int mqtt_port = \d+;', ('const int mqtt_port = {0};' -f $MqttPort))

if ($updatedFirmware -eq $firmware) {
    Write-Host "Aucune modification detectee dans main.cpp" -ForegroundColor Yellow
} else {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($firmwarePath, $updatedFirmware, $utf8NoBom)
    Write-Host "main.cpp mis a jour" -ForegroundColor Green
}

if ($SkipUpload) {
    Write-Host "Flash ignore a la demande" -ForegroundColor Yellow
    exit 0
}

Write-Host "Compilation et flash en cours..." -ForegroundColor Cyan
& py -m platformio run -t upload
if ($LASTEXITCODE -ne 0) {
    throw "Le flash PlatformIO a echoue."
}

Write-Host "Flash termine" -ForegroundColor Green

if ($OpenMonitor) {
    Write-Host "Ouverture du moniteur serie..." -ForegroundColor Cyan
    & py -m platformio device monitor -b 115200
}