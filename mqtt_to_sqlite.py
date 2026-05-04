import os
import sqlite3
from datetime import datetime

import paho.mqtt.client as mqtt


MQTT_BROKER = os.getenv("MQTT_BROKER", "127.0.0.1")
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))
MQTT_TOPIC = os.getenv("MQTT_TOPIC", "capteur/#")
DB_PATH = os.getenv("DB_PATH", "sensor_data.db")


def init_db(db_path: str) -> None:
    conn = sqlite3.connect(db_path)
    try:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS measurements (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                topic TEXT NOT NULL,
                value_text TEXT NOT NULL,
                value_real REAL,
                received_at TEXT NOT NULL
            )
            """
        )
        conn.commit()
    finally:
        conn.close()


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
    received_at = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    numeric_value = to_float_or_none(payload)

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute(
            """
            INSERT INTO measurements(topic, value_text, value_real, received_at)
            VALUES (?, ?, ?, ?)
            """,
            (msg.topic, payload, numeric_value, received_at),
        )
        conn.commit()
    finally:
        conn.close()

    print(f"[{received_at}] {msg.topic} -> {payload}")


def main() -> None:
    init_db(DB_PATH)

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    client.on_connect = on_connect
    client.on_message = on_message

    print("Demarrage du logger MQTT vers SQLite...")
    client.connect(MQTT_BROKER, MQTT_PORT, 60)
    client.loop_forever()


if __name__ == "__main__":
    main()
