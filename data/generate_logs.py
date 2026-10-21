import os
import random
from datetime import datetime, timedelta
import pandas as pd
from faker import Faker

# ---------- Settings ----------
fake = Faker()
random.seed(42)
Faker.seed(42)

NUM_USERS = 150
START_TIME = datetime(2026, 8, 1)
OUT_DIR = os.path.dirname(os.path.abspath(__file__))

# ---------- Places ----------
locations = [
    {"location_id": 1, "city": "Mumbai",    "country": "India",     "latitude": 19.0760, "longitude": 72.8777},
    {"location_id": 2, "city": "Delhi",     "country": "India",     "latitude": 28.7041, "longitude": 77.1025},
    {"location_id": 3, "city": "London",    "country": "UK",        "latitude": 51.5074, "longitude": -0.1278},
    {"location_id": 4, "city": "Frankfurt", "country": "Germany",   "latitude": 50.1109, "longitude": 8.6821},
    {"location_id": 5, "city": "New York",  "country": "USA",       "latitude": 40.7128, "longitude": -74.0060},
    {"location_id": 6, "city": "Singapore", "country": "Singapore", "latitude": 1.3521,  "longitude": 103.8198},
]

# ---------- Devices ----------
devices = [
    {"device_id": 1, "device_type": "Laptop", "os": "Windows 11", "browser": "Chrome"},
    {"device_id": 2, "device_type": "Laptop", "os": "Windows 10", "browser": "Edge"},
    {"device_id": 3, "device_type": "Laptop", "os": "macOS",      "browser": "Safari"},
    {"device_id": 4, "device_type": "Laptop", "os": "Ubuntu",     "browser": "Firefox"},
    {"device_id": 5, "device_type": "Mobile", "os": "Android",    "browser": "Chrome"},
    {"device_id": 6, "device_type": "Mobile", "os": "iOS",        "browser": "Safari"},
]

departments = ["Finance", "Engineering", "HR", "Sales", "IT Security", "Executive"]

# ---------- Employees ----------
users = []
for i in range(1, NUM_USERS + 1):
    dept = random.choice(departments)
    name = fake.name()
    users.append({
        "user_id": f"USR-{i:04d}",
        "full_name": name,
        "email": name.lower().replace(" ", ".") + "@examplecorp.com",
        "department": dept,
        "is_vip": dept in ["Executive", "IT Security"],
        "home_location_id": random.choice([1, 2]),
        "device_id": random.choice([d["device_id"] for d in devices]),
        "home_ip": fake.ipv4(),
    })

# ---------- Normal logins ----------
# 24 numbers, one per hour (0 to 23). Bigger number = more logins in that hour.
hour_weights = [1] * 7 + [4, 8, 10, 10, 9, 7, 8, 10, 10, 9, 6, 4] + [2] * 5

def random_login_time():
    day = random.randint(0, 29)
    hour = random.choices(range(24), weights=hour_weights)[0]
    return START_TIME + timedelta(
        days=day, hours=hour,
        minutes=random.randint(0, 59),
        seconds=random.randint(0, 59),
    )

records = []
for u in users:
    for _ in range(random.randint(320, 380)):
        failed = random.random() < 0.04
        records.append({
            "timestamp": random_login_time(),
            "user_id": u["user_id"],
            "location_id": u["home_location_id"],
            "device_id": u["device_id"],
            "ip_address": u["home_ip"],
            "status": "FAILED" if failed else "SUCCESS",
            "mfa_status": "NOT_PROMPTED" if failed else "APPROVED",
        })

print("Normal logins made:", len(records))

# ---------- ATTACKS ----------
# Attacker IPs come from special "example" ranges that never belong to real people.

def add_event(ts, user_id, location_id, device_id, ip, status, mfa, label):
    records.append({
        "timestamp": ts,
        "user_id": user_id,
        "location_id": location_id,
        "device_id": device_id,
        "ip_address": ip,
        "status": status,
        "mfa_status": mfa,
        "attack_label": label,
    })

# Attack 1: Impossible travel
# Victim logs in from home. 25 minutes later, the same account logs in from Frankfurt.
v1 = users[5]
t1 = START_TIME + timedelta(days=2, hours=10)
add_event(t1, v1["user_id"], v1["home_location_id"], v1["device_id"], v1["home_ip"],
          "SUCCESS", "APPROVED", "IMPOSSIBLE_TRAVEL")
add_event(t1 + timedelta(minutes=25), v1["user_id"], 4, 4, "203.0.113.45",
          "SUCCESS", "APPROVED", "IMPOSSIBLE_TRAVEL")

# Attack 2: MFA fatigue
# Attacker knows the password and spams the phone with approval requests.
# The victim says NO 8 times, then gets tired and says YES.
v2 = users[12]
t2 = START_TIME + timedelta(days=5, hours=3, minutes=15)
for i in range(8):
    add_event(t2 + timedelta(seconds=20 * i), v2["user_id"], v2["home_location_id"], 4,
              "198.51.100.23", "FAILED", "DENIED", "MFA_FATIGUE")
add_event(t2 + timedelta(seconds=200), v2["user_id"], v2["home_location_id"], 4,
          "198.51.100.23", "SUCCESS", "APPROVED", "MFA_FATIGUE")

# Attack 3: Brute force
# Attacker tries 40 wrong passwords in under 5 minutes from one IP.
v3 = users[20]
t3 = START_TIME + timedelta(days=9, hours=2, minutes=40)
for i in range(40):
    add_event(t3 + timedelta(seconds=7 * i), v3["user_id"], v3["home_location_id"], 4,
              "192.0.2.77", "FAILED", "NOT_PROMPTED", "BRUTE_FORCE")

print("Victims:", v1["user_id"], v2["user_id"], v3["user_id"])

# ---------- Finish and save ----------
events = pd.DataFrame(records).sort_values("timestamp").reset_index(drop=True)
events.insert(0, "event_id", [f"EVT-{n:06d}" for n in range(1, len(events) + 1)])

# Answer key: a secret list of the attack rows, kept in a separate file
answer_key = events[events["attack_label"].notna()][["event_id", "timestamp", "user_id", "attack_label"]]
answer_key.to_csv(os.path.join(OUT_DIR, "attack_answer_key.csv"), index=False)

# The raw log must NOT contain the label, like a real log
events = events.drop(columns=["attack_label"])

events.to_csv(os.path.join(OUT_DIR, "auth_events_raw.csv"), index=False)
pd.DataFrame(users).drop(columns=["device_id", "home_ip"]).to_csv(os.path.join(OUT_DIR, "dim_users.csv"), index=False)
pd.DataFrame(locations).to_csv(os.path.join(OUT_DIR, "dim_locations.csv"), index=False)
pd.DataFrame(devices).to_csv(os.path.join(OUT_DIR, "dim_devices.csv"), index=False)

print("Total events saved:", len(events))
print("Attack rows planted:", len(answer_key))
print(answer_key.groupby("attack_label").size())