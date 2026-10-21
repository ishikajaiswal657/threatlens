import pandas as pd

for f in ["dim_users.csv", "auth_events_raw.csv"]:
    df = pd.read_csv(f)
    print(f, df.shape)
    print(df.columns.tolist())
    print(df.head(2))
    print()