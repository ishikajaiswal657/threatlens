import os
import getpass
import psycopg

# The folder where this file lives, so Python always finds the CSV
DATA_DIR = os.path.dirname(os.path.abspath(__file__))

# Asks for the password when you run it
password = input("Postgres password: ")

conn = psycopg.connect(
    host="localhost", port=5432,
    dbname="siem_project", user="postgres", password=password,
)

with conn:
    with conn.cursor() as cur:
        cur.execute("TRUNCATE dim_users CASCADE")

        with open(os.path.join(DATA_DIR, "dim_users.csv"), encoding="utf-8") as f:
            with cur.copy(
                "COPY dim_users (user_id, full_name, email, department, is_vip, home_location_id) "
                "FROM STDIN WITH (FORMAT csv, HEADER true)"
            ) as copy:
                while chunk := f.read(65536):
                    copy.write(chunk)

        cur.execute("SELECT COUNT(*) FROM dim_users")
        print("dim_users rows loaded:", cur.fetchone()[0])