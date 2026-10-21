import os
import psycopg

DATA_DIR = os.path.dirname(os.path.abspath(__file__))

password = input("Postgres password: ")

conn = psycopg.connect(
    host="localhost", port=5432,
    dbname="siem_project", user="postgres", password=password,
)

with conn:
    with conn.cursor() as cur:
        cur.execute("TRUNCATE fact_auth_events")

        with open(os.path.join(DATA_DIR, "auth_events_raw.csv"), encoding="utf-8") as f:
            with cur.copy(
                "COPY fact_auth_events (event_id, event_time, user_id, location_id, "
                "device_id, ip_address, status, mfa_status) "
                "FROM STDIN WITH (FORMAT csv, HEADER true)"
            ) as copy:
                while chunk := f.read(65536):
                    copy.write(chunk)

        cur.execute("SELECT COUNT(*) FROM fact_auth_events")
        print("fact_auth_events rows loaded:", cur.fetchone()[0])