param(
    [ValidateSet("start-collector", "publish-demo", "all")]
    [string]$Action = "all",

    [string]$ImageName = "mspr5_iot-mqtt_collector:latest",
    [string]$CollectorContainerName = "mqtt_collector_cloud_demo",

    [string]$MqttHost = "host.docker.internal",
    [int]$MqttPort = 1884,
    [string]$MqttTopicTemperature = "capteur/temperature",
    [string]$MqttTopicHumidity = "capteur/humidite",

    [string]$DbHost = "db-brazil",
    [int]$DbPort = 5432,
    [string]$DbName = "futurekawa_brazil",
    [string]$DbUser = "futurekawa",
    [string]$DbPassword = "futurekawa_pwd",

    [int]$IdEntrepot = 1,
    [int]$InsertIntervalSeconds = 3,
    [string]$DockerNetwork = "mspr5_serveurs_default",

    [double]$Temperature = 24.5,
    [double]$Humidity = 61.0,
    [int]$Count = 1,
    [int]$PublishIntervalSeconds = 2
)

$ErrorActionPreference = "Stop"

function Invoke-Docker {
    param([string[]]$Arguments)

    & docker @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "La commande Docker a echoue: docker $($Arguments -join ' ')"
    }
}

function Build-CollectorImage {
    Write-Host "[1/3] Build de l'image collector..." -ForegroundColor Cyan
    Invoke-Docker @("build", "-t", $ImageName, ".")
}

function Start-Collector {
    Write-Host "[2/3] Demarrage du pont MQTT -> PostgreSQL..." -ForegroundColor Cyan

    $existingContainerId = ((& docker ps -aq -f "name=^$CollectorContainerName`$") | Out-String).Trim()
    if ($existingContainerId) {
        Invoke-Docker @("rm", "-f", $CollectorContainerName)
    }

    $runArgs = @(
        "run", "-d",
        "--name", $CollectorContainerName,
        "-e", "PYTHONUNBUFFERED=1",
        "-e", "MQTT_BROKER=$MqttHost",
        "-e", "MQTT_PORT=$MqttPort",
        "-e", "MQTT_TOPIC=capteur/#",
        "-e", "TEMPERATURE_TOPIC=$MqttTopicTemperature",
        "-e", "HUMIDITY_TOPIC=$MqttTopicHumidity",
        "-e", "INSERT_INTERVAL_SECONDS=$InsertIntervalSeconds",
        "-e", "DB_HOST=$DbHost",
        "-e", "DB_PORT=$DbPort",
        "-e", "DB_NAME=$DbName",
        "-e", "DB_USER=$DbUser",
        "-e", "DB_PASSWORD=$DbPassword",
        "-e", "ID_ENTREPOT=$IdEntrepot",
        $ImageName
    )

    if ($DockerNetwork) {
        $runArgs = @(
            $runArgs[0..3] + @("--network", $DockerNetwork) + $runArgs[4..($runArgs.Length - 1)]
        )
    }

    Invoke-Docker $runArgs
    Write-Host "Container lance: $CollectorContainerName" -ForegroundColor Green
    Write-Host "Logs: docker logs -f $CollectorContainerName" -ForegroundColor DarkGray
}

function Publish-DemoData {
    Write-Host "[3/3] Publication de mesures de demo..." -ForegroundColor Cyan

    for ($index = 1; $index -le $Count; $index++) {
        $tempValue = [Math]::Round($Temperature + (($index - 1) * 0.2), 2)
        $humidityValue = [Math]::Round($Humidity + (($index - 1) * 0.3), 2)

        Invoke-Docker @(
            "run", "--rm", "eclipse-mosquitto:2",
            "mosquitto_pub",
            "-h", $MqttHost,
            "-p", "$MqttPort",
            "-t", $MqttTopicTemperature,
            "-m", "$tempValue"
        )

        Invoke-Docker @(
            "run", "--rm", "eclipse-mosquitto:2",
            "mosquitto_pub",
            "-h", $MqttHost,
            "-p", "$MqttPort",
            "-t", $MqttTopicHumidity,
            "-m", "$humidityValue"
        )

        Write-Host "Mesure envoyee #$index : temp=$tempValue hum=$humidityValue" -ForegroundColor Green

        if ($index -lt $Count) {
            Start-Sleep -Seconds $PublishIntervalSeconds
        }
    }
}

switch ($Action) {
    "start-collector" {
        Build-CollectorImage
        Start-Collector
    }
    "publish-demo" {
        Publish-DemoData
    }
    "all" {
        Build-CollectorImage
        Start-Collector
        Publish-DemoData
    }
}

Write-Host "Termine." -ForegroundColor Cyan