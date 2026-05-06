import os
import threading
from time import sleep
from datetime import datetime, timezone

import paho.mqtt.client as mqtt
import psycopg


MQTT_BROKER = os.getenv("MQTT_BROKER", "127.0.0.1")
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))
MQTT_TOPIC = os.getenv("MQTT_TOPIC", "capteur/#")
DB_HOST = os.getenv("DB_HOST", "127.0.0.1")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME", "sensors")
DB_USER = os.getenv("DB_USER", "user")
DB_PASSWORD = os.getenv("DB_PASSWORD", "password")
DATABASE_URL = os.getenv("DATABASE_URL")
INSERT_INTERVAL_SECONDS = int(os.getenv("INSERT_INTERVAL_SECONDS", "3"))
TEMPERATURE_TOPIC = os.getenv("TEMPERATURE_TOPIC", "capteur/temperature")
HUMIDITY_TOPIC = os.getenv("HUMIDITY_TOPIC", "capteur/humidite")
SENSOR_ID = os.getenv("SENSOR_ID", "ESP8266_DHT11")


latest_measurements = {
    "temperature": None,
    "humidity": None,
}
latest_measurements_lock = threading.Lock()


def get_db_connection():
    if DATABASE_URL:
        return psycopg.connect(DATABASE_URL)

    return psycopg.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
    )


def init_db() -> None:
    with get_db_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                CREATE TABLE IF NOT EXISTS climate_readings (
                    id BIGSERIAL PRIMARY KEY,
                    sensor_id TEXT NOT NULL,
                    temperature_c DOUBLE PRECISION,
                    humidity_pct DOUBLE PRECISION,
                    temperature_raw TEXT,
                    humidity_raw TEXT,
                    temperature_received_at TIMESTAMPTZ,
                    humidity_received_at TIMESTAMPTZ,
                    recorded_at TIMESTAMPTZ NOT NULL,
                    mqtt_broker TEXT NOT NULL
                )
                """
            )
        conn.commit()


def to_float_or_none(value: str):
    try:
        return float(value)
    except ValueError:
        return None


def on_connect(client, userdata, flags, reason_code, properties=None):
    if reason_code == 0:
        print(f"Connecte au broker MQTT {MQTT_BROKER}:{MQTT_PORT}")
        client.subscribe(MQTT_TOPIC)
        print(f"Abonnement au topic: {MQTT_TOPIC}")
    else:
        print(f"Echec connexion MQTT, code={reason_code}")


def on_message(client, userdata, msg):
    payload = msg.payload.decode("utf-8", errors="replace").strip()
    numeric_value = to_float_or_none(payload)
    received_at = datetime.now(timezone.utc)

    if msg.topic == TEMPERATURE_TOPIC:
        metric = "temperature"
    elif msg.topic == HUMIDITY_TOPIC:
        metric = "humidity"
    else:
        return

    with latest_measurements_lock:
        latest_measurements[metric] = {
            "raw": payload,
            "value": numeric_value,
            "received_at": received_at,
            "topic": msg.topic,
        }

    print(f"[{received_at.isoformat()}] cache {msg.topic} -> {payload}")


def insert_snapshot() -> None:
    with latest_measurements_lock:
        temperature = latest_measurements["temperature"]
        humidity = latest_measurements["humidity"]

        if temperature is None or humidity is None:
            return

        snapshot = {
            "temperature": dict(temperature),
            "humidity": dict(humidity),
        }

    recorded_at = datetime.now(timezone.utc)

    with get_db_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO climate_readings(
                    sensor_id,
                    temperature_c,
                    humidity_pct,
                    temperature_raw,
                    humidity_raw,
                    temperature_received_at,
                    humidity_received_at,
                    recorded_at,
                    mqtt_broker
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    SENSOR_ID,
                    snapshot["temperature"]["value"],
                    snapshot["humidity"]["value"],
                    snapshot["temperature"]["raw"],
                    snapshot["humidity"]["raw"],
                    snapshot["temperature"]["received_at"],
                    snapshot["humidity"]["received_at"],
                    recorded_at,
                    MQTT_BROKER,
                ),
            )
        conn.commit()

    print(
        f"[{recorded_at.isoformat()}] enregistre snapshot temp={snapshot['temperature']['raw']} hum={snapshot['humidity']['raw']}"
    )


def periodic_writer() -> None:
    while True:
        sleep(INSERT_INTERVAL_SECONDS)
        insert_snapshot()


def main() -> None:
    init_db()

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    client.on_connect = on_connect
    client.on_message = on_message

    writer_thread = threading.Thread(target=periodic_writer, daemon=True)
    writer_thread.start()

    print(
        f"Demarrage du logger MQTT vers PostgreSQL (ecriture toutes les {INSERT_INTERVAL_SECONDS}s)..."
    )
    client.connect(MQTT_BROKER, MQTT_PORT, 60)
    client.loop_forever()


if __name__ == "__main__":
    main()
