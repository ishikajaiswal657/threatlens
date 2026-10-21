# ThreatLens

A small version of what a Security Operations Center (SOC) uses to catch hacked accounts. It makes fake login data, stores it in PostgreSQL, finds three kinds of attack with SQL, and shows the results in a Power BI dashboard.

All data is simulated. I planted the attacks myself, so I know where they are.

## What it detects

| Threat | What it means | Rule used |
|---|---|---|
| IMPOSSIBLE_TRAVEL | Logins too far apart to travel between in the time given | More than 200 km apart and faster than 800 km/h |
| MFA_FATIGUE | An attacker spams approval prompts until the user taps "approve" | An approval after 5 or more denials in the previous 10 minutes |
| BRUTE_FORCE | Many wrong passwords against one account | 10 or more wrong-password failures from one IP on one user within 5 minutes |

## How it works

1. **Python** makes 150 fake users and 52,403 login events, saved as CSV files. It plants 3 attacks (51 rows).
2. **PostgreSQL** stores the data in linked tables: `dim_users`, `dim_devices`, `dim_locations` and `fact_auth_events`. SQL views find each attack using window functions (`LAG` and sliding time windows) and the haversine distance formula. A final view, `vw_fact_security_feed`, gives every login a `threat_tag` and risk points.
3. **Power BI** reads the final view and shows two pages.

## Results and limits

- I checked the views against a separate answer key. All 3 planted attacks were found, with no false alarms.
- I wrote both the attacks and the rules, so this shows the queries work as designed. It does not show how they would perform on real data.
- Normal users in this data never travel and never deny a prompt. Real data would produce false alarms that need tuning.
- I added an index on `(user_id, event_time)`. A one-user lookup went from 2.861 ms to 0.413 ms (one test run, 52,403 rows).

## Dashboard

**Overview**
- Total Logins: 52,403
- Failed Logins: 2,202
- Failed Login %: 4.2%
- Threat Events: 51 flagged login rows (from the 3 simulated attacks)
- Bar chart of threat events by type (BRUTE_FORCE 40, MFA_FATIGUE 9, IMPOSSIBLE_TRAVEL 2)

**Attack Details**
- Table of every flagged event: time, user, IP address, threat type, status and MFA result
- Slicer to filter by threat type

## Screenshots

![Overview](screenshots/overview.png)
![Attack Details](screenshots/attack-details.png)

## Tools used

Python (pandas, Faker, psycopg 3), PostgreSQL 18, pgAdmin, Power BI Desktop

## Project structure

```
threatlens/
  sql/   01_schema_setup.sql        tables, index and the four views
         02_seed_dimensions.sql     the 6 cities and 6 devices
  data/  generate_logs.py           makes the fake data (CSV files)
         load_dim_users.py          loads users into PostgreSQL
         load_fact_events.py        loads login events into PostgreSQL
         load_answer_key.py         loads the list of planted attacks (for testing only)
  bi/    threatlens.pbix            Power BI dashboard
         threatlens.pdf             PDF copy of the dashboard
  screenshots/                      dashboard pictures
```

## Run it yourself

1. Create a PostgreSQL database named `siem_project`. The scripts connect to it as user `postgres` on `localhost:5432`.
2. Run `sql/01_schema_setup.sql`, then `sql/02_seed_dimensions.sql` (for example in the pgAdmin Query Tool).
3. Install the Python packages: `pip install pandas faker "psycopg[binary]"`
4. Optional: run `python data/generate_logs.py` to recreate the CSV files. They are already in `data/`.
5. Load the data in this order, because events point to users:
   - `python data/load_dim_users.py`
   - `python data/load_fact_events.py`
   - `python data/load_answer_key.py`

   Each script asks for your PostgreSQL password when you run it, so no password is stored in the code.
6. Open `bi/threatlens.pbix` in Power BI Desktop, point it at your database and refresh.

## Notes

All data is fake. The attacker IP addresses come from reserved documentation ranges. The normal users' IP addresses are random ones made by Faker and may match real addresses. Emails use a made-up company domain, `examplecorp.com`.
