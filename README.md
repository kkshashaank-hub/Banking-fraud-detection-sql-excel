# Banking Fraud Detection — End-to-End SQL + Excel Analytics Project

## Problem Statement
Banks lose significant money to fraudulent transactions, and manually reviewing every
transaction is impossible at scale. This project builds a pipeline that cleans messy
raw transaction data with SQL, then surfaces the highest-signal fraud patterns in an
interactive Excel dashboard — the kind of first-pass triage tool a fraud analytics
team would actually use to decide where to focus manual review effort.

## A note on the data
This sandbox environment can't reach Kaggle directly, so `raw_transactions.csv` is a
**synthetic dataset** generated to mirror the real-world [Credit Card Fraud Detection
dataset on Kaggle](https://www.kaggle.com/datasets/mlg-ulb/creditcardfraud) — same
~1-2% fraud imbalance, same idea that fraud clusters at odd hours and higher amounts —
but with extra realistic messiness (duplicate rows, missing values, four different
date formats, inconsistent text casing, a handful of negative-amount data-entry
errors) so there's genuine cleaning work to demonstrate.

**To use the real dataset:** download the Kaggle CSV, rename/remap its columns to
match (`TransactionID, CustomerID, TransactionDate, Amount, Merchant,
MerchantCategory, Location, Channel, IsFraud`), drop it in as `raw_transactions.csv`,
and re-run `run_pipeline.py`. Nothing else in the SQL or Excel needs to change — that's
the point of building it this way.

## Tools & Skills Used
- **SQL (SQLite)** — data cleaning, CTEs, window functions (`ROW_NUMBER`, `LAG`, `RANK`)
- **Python** — orchestration (loading CSV → SQLite → running SQL → exporting results)
- **Excel** — live-formula dashboard (`COUNTIF`, `SUMIFS`) with 4 charts

## Project Structure
```
fraud_project/
├── raw_transactions.csv              # messy raw data (input)
├── 01_clean_data.sql                 # cleaning: dedupe, fix dates/text, handle nulls
├── 02_analysis.sql                   # 7 business-question queries (CTEs + window fns)
├── run_pipeline.py                   # loads CSV -> SQLite -> runs both SQL scripts -> exports CSVs
├── Banking_Fraud_Detection_Dashboard.xlsx   # final deliverable
└── outputs/                          # exported CSVs from each SQL query
```

## Cleaning Steps (01_clean_data.sql)
| Issue found in raw data | Fix applied |
|---|---|
| ~2% exact duplicate rows (ETL re-run bug) | `ROW_NUMBER() OVER (PARTITION BY TransactionID)`, kept first occurrence |
| 4 different date formats mixed together | Parsed each pattern with `CASE`/`substr`, normalized to ISO `YYYY-MM-DD HH:MM:SS` |
| Inconsistent text casing/whitespace in Merchant & Location | `TRIM()` + `UPPER()` for consistent grouping |
| Missing `Amount` values | Imputed with the average amount for that merchant category (documented, not silently dropped) |
| Missing `Location` values | Imputed as `'UNKNOWN'` rather than discarding the transaction |
| Negative amounts (data-entry errors) | Routed to a separate `rejected_transactions` table — flagged for manual follow-up, not silently deleted or guessed at |

**Result:** 9,180 raw rows → 8,955 clean rows + 45 rejected (bad data, kept for audit) + ~180 duplicates removed.

## Key Findings (from 02_analysis.sql)

1. **Fraud clusters heavily at odd hours.** Fraud rate is 4-5% between midnight and
   4am, versus close to 0% during normal daytime hours. This is the single strongest
   signal in the data — a time-of-day rule alone would catch a large share of fraud
   cases with very few false positives.
2. **Transfer and Travel categories carry the highest fraud rates** (1.8% and 1.5%
   respectively), noticeably above Retail and Fuel (under 1.1%). Category-specific
   review thresholds would likely outperform a flat threshold.
3. **Fraud is not concentrated in the highest-dollar transactions** — mid-range
   amounts show meaningful fraud rates too, meaning an amount-only filter would miss
   a lot of cases.
4. **Transaction velocity** (time between a customer's consecutive transactions) surfaces
   several sub-2-minute gaps worth flagging as a rule on their own, regardless of
   individual transaction amount.
5. Geographic fraud rates vary by ~30% across locations — worth a location-adjusted
   risk score rather than one global threshold.

## Business Recommendation
Combine the three strongest signals — odd-hour timing, category risk tier, and
transaction velocity — into a simple weighted risk score for real-time transaction
screening, rather than relying on amount thresholds alone, which this data shows are
a weak signal on their own.

## Dashboard
`Banking_Fraud_Detection_Dashboard.xlsx` contains:
- **Dashboard** tab — KPI cards + 4 live charts (by category, hour, amount bucket, location), all driven by `COUNTIF`/`SUMIFS` formulas over the cleaned data, so it recalculates if the underlying data changes
- **Cleaned Data** tab — the full cleaned dataset with two helper columns (Hour, AmountBucket) used by the dashboard formulas
- **Raw Data (Before Cleaning)** tab — the original messy export, for before/after comparison
- **SQL Insights (Window Fns)** tab — the LAG/RANK query outputs, sourced directly from SQL since those aren't easily replicated as plain spreadsheet formulas

