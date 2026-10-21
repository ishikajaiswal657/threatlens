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
        cur.execute("DROP TABLE IF EXISTS attack_answer_key")
        cur.execute("""
            CREATE TABLE attack_answer_key (
                event_id     VARCHAR(12) PRIMARY KEY,
                event_time   TIMESTAMP,
                user_id      VARCHAR(10),
                attack_label VARCHAR(30)
            )
        """)

        with open(os.path.join(DATA_DIR, "attack_answer_key.csv"), encoding="utf-8") as f:
            with cur.copy(
                "COPY attack_answer_key (event_id, event_time, user_id, attack_label) "
                "FROM STDIN WITH (FORMAT csv, HEADER true)"
            ) as copy:
                while chunk := f.read(65536):
                    copy.write(chunk)

        cur.execute("SELECT attack_label, COUNT(*) FROM attack_answer_key GROUP BY attack_label ORDER BY attack_label")
        for row in cur.fetchall():
            print(row)