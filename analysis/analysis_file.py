import pandas as pd

df = pd.read_csv(r"C:\Users\William Ordiales\OneDrive\Documentos\iese_case\gestor_eventos_event_registration_sample_vf.csv",sep=",")

df.shape

df.columns

df.dtypes

df.head(5)

df.isna().sum()

df[df["phone"].isna()]
df[df["attendee_email"].isna()]
df[df["company"].isna()]

df["registration_status"].unique()

df["event_name"].unique()


len(df["registration_id"].unique())
len(df["event_id"].unique())
len(df["event_date"].unique())
df["event_id"].unique()

df[["registration_id","registered_at"]].drop_duplicates().shape
df[["registration_id","updated_at"]].drop_duplicates().shape
df[["registration_id","_LOADED_AT"]].drop_duplicates().shape
df.drop_duplicates().shape


df[["registration_id","_LOADED_AT","registered_at","_LOADED_AT"]].drop_duplicates().shape


repeats = df["registration_id"].value_counts()
repeats[repeats > 1]

repeated_ids = repeats[repeats > 1].index
df[df["registration_id"].isin(repeated_ids)].sort_values(["registration_id", "_LOADED_AT"])[
    ["registration_id", "registration_status", "updated_at", "_LOADED_AT", "_BATCH_ID"]
]


