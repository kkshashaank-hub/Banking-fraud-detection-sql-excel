
import sqlite3
import pandas as pd
import os

BASE = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE, "fraud.db")

if os.path.exists(DB_PATH):
    os.remove(DB_PATH)

conn = sqlite3.connect(DB_PATH)

# 1. Load raw data
raw = pd.read_csv(os.path.join(BASE, "raw_transactions.csv"))
raw.to_sql("raw_transactions", conn, index=False)
print(f"Loaded raw_transactions: {len(raw)} rows")

# 2. Run cleaning script
with open(os.path.join(BASE, "01_clean_data.sql")) as f:
    conn.executescript(f.read())
conn.commit()

cleaned_count = conn.execute("SELECT COUNT(*) FROM cleaned_transactions").fetchone()[0]
rejected_count = conn.execute("SELECT COUNT(*) FROM rejected_transactions").fetchone()[0]
print(f"Cleaned: {cleaned_count} rows | Rejected (bad data): {rejected_count} rows")

# 3. Run analysis script (creates views)
with open(os.path.join(BASE, "02_analysis.sql")) as f:
    conn.executescript(f.read())
conn.commit()

# 4. Export cleaned data + every analysis view to CSV
exports = {
    "cleaned_transactions": "cleaned_transactions.csv",
    "rejected_transactions": "rejected_transactions.csv",
    "q1_fraud_by_category": "q1_fraud_by_category.csv",
    "q2_fraud_by_hour": "q2_fraud_by_hour.csv",
    "q3_fraud_by_amount_bucket": "q3_fraud_by_amount_bucket.csv",
    "q4_transaction_velocity": "q4_transaction_velocity.csv",
    "q5_top_outliers_by_category": "q5_top_outliers_by_category.csv",
    "q6_fraud_by_location": "q6_fraud_by_location.csv",
    "q7_summary_kpis": "q7_summary_kpis.csv",
}

os.makedirs(os.path.join(BASE, "outputs"), exist_ok=True)
for table, filename in exports.items():
    df = pd.read_sql(f"SELECT * FROM {table}", conn)
    df.to_csv(os.path.join(BASE, "outputs", filename), index=False)
    print(f"Exported {table}: {len(df)} rows -> outputs/{filename}")

conn.close()
print("\nPipeline complete.")
