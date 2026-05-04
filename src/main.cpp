#include <ESP8266WiFi.h>
#include <PubSubClient.h>
#include <DHT.h>

#define DHTPIN D1
#define DHTTYPE DHT11

const char* ssid = "EPSI-Lab";
const char* password = "EPSIGrenoble";
const char* mqtt_server = "172.16.0.56"; // ⚠️ IP de TON PC

WiFiClient espClient;
PubSubClient client(espClient);
DHT dht(DHTPIN, DHTTYPE);

void setup_wifi() {
  delay(2000);

  Serial.println("\nConnexion WiFi...");
  WiFi.begin(ssid, password);

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  Serial.println("\nWiFi connecté !");
  Serial.print("IP ESP : ");
  Serial.println(WiFi.localIP());
}

void reconnect() {
  while (!client.connected()) {
    Serial.print("Connexion MQTT... ");

    if (client.connect("ESP8266_DHT11")) {
      Serial.println("OK");
    } else {
      Serial.print("FAIL, rc=");
      Serial.println(client.state());
      delay(2000);
    }
  }
}

void setup() {
  Serial.begin(115200);
  delay(2000);

  Serial.println("\n--- BOOT ESP8266 ---");

  dht.begin();

  setup_wifi();

  client.setServer(mqtt_server, 1883);
}

void loop() {

  if (!client.connected()) {
    reconnect();
  }

  client.loop();

  float h = dht.readHumidity();
  float t = dht.readTemperature();

  if (isnan(h) || isnan(t)) {
    Serial.println("Erreur DHT !");
    delay(2000);
    return;
  }

  char temp[10];
  char hum[10];

  dtostrf(t, 1, 2, temp);
  dtostrf(h, 1, 2, hum);

  Serial.print("Temp: ");
  Serial.print(temp);
  Serial.print(" | Hum: ");
  Serial.println(hum);

  client.publish("capteur/temperature", temp);
  client.publish("capteur/humidite", hum);

  delay(2000);
}