/* ============================================================
   02_analysis.sql
   Banking Fraud Detection — Analysis Queries
   ============================================================ */

/* Q1. Fraud rate and volume by merchant category
   -> which categories need tighter monitoring rules? */
DROP VIEW IF EXISTS q1_fraud_by_category;
CREATE VIEW q1_fraud_by_category AS
SELECT
    MerchantCategory,
    COUNT(*)                                   AS total_transactions,
    SUM(IsFraud)                                AS fraud_count,
    ROUND(100.0 * SUM(IsFraud) / COUNT(*), 3)   AS fraud_rate_pct,
    ROUND(AVG(Amount), 2)                       AS avg_amount
FROM cleaned_transactions
GROUP BY MerchantCategory
ORDER BY fraud_rate_pct DESC;


/* Q2. Fraud rate by hour of day
   -> is fraud clustering at odd hours (a classic tell)? */
DROP VIEW IF EXISTS q2_fraud_by_hour;
CREATE VIEW q2_fraud_by_hour AS
SELECT
    CAST(strftime('%H', TransactionDate) AS INTEGER) AS hour_of_day,
    COUNT(*)                                          AS total_transactions,
    SUM(IsFraud)                                      AS fraud_count,
    ROUND(100.0 * SUM(IsFraud) / COUNT(*), 3)         AS fraud_rate_pct
FROM cleaned_transactions
GROUP BY hour_of_day
ORDER BY hour_of_day;


/* Q3. Fraud rate by transaction amount bucket
   -> does fraud concentrate in a specific spend range? */
DROP VIEW IF EXISTS q3_fraud_by_amount_bucket;
CREATE VIEW q3_fraud_by_amount_bucket AS
WITH bucketed AS (
    SELECT *,
        CASE
            WHEN Amount < 50   THEN '1. $0-49'
            WHEN Amount < 150  THEN '2. $50-149'
            WHEN Amount < 400  THEN '3. $150-399'
            WHEN Amount < 1000 THEN '4. $400-999'
            ELSE                    '5. $1000+'
        END AS amount_bucket
    FROM cleaned_transactions
)
SELECT
    amount_bucket,
    COUNT(*)                                  AS total_transactions,
    SUM(IsFraud)                              AS fraud_count,
    ROUND(100.0 * SUM(IsFraud) / COUNT(*), 3) AS fraud_rate_pct
FROM bucketed
GROUP BY amount_bucket
ORDER BY amount_bucket;


/* Q4. Time gap between a customer's consecutive transactions (LAG window fn)
   -> flags rapid-fire transactions, a classic fraud velocity signal.
   Shows the 20 shortest gaps immediately preceding a fraud flag. */
DROP VIEW IF EXISTS q4_transaction_velocity;
CREATE VIEW q4_transaction_velocity AS
WITH ordered AS (
    SELECT
        CustomerID,
        TransactionID,
        TransactionDate,
        Amount,
        IsFraud,
        LAG(TransactionDate) OVER (
            PARTITION BY CustomerID ORDER BY TransactionDate
        ) AS prev_txn_time
    FROM cleaned_transactions
)
SELECT
    CustomerID,
    TransactionID,
    TransactionDate,
    Amount,
    IsFraud,
    prev_txn_time,
    ROUND(
        (JULIANDAY(TransactionDate) - JULIANDAY(prev_txn_time)) * 24 * 60, 1
    ) AS minutes_since_prev_txn
FROM ordered
WHERE prev_txn_time IS NOT NULL
ORDER BY minutes_since_prev_txn ASC
LIMIT 25;


/* Q5. Top outlier amounts per category (RANK window fn)
   -> the single highest-value transaction in each category,
      worth a manual review regardless of the fraud flag. */
DROP VIEW IF EXISTS q5_top_outliers_by_category;
CREATE VIEW q5_top_outliers_by_category AS
WITH ranked AS (
    SELECT
        MerchantCategory,
        TransactionID,
        CustomerID,
        Amount,
        IsFraud,
        RANK() OVER (
            PARTITION BY MerchantCategory ORDER BY Amount DESC
        ) AS amount_rank
    FROM cleaned_transactions
)
SELECT MerchantCategory, TransactionID, CustomerID, Amount, IsFraud
FROM ranked
WHERE amount_rank <= 3
ORDER BY MerchantCategory, Amount DESC;


/* Q6. Fraud rate by location
   -> geographic hotspots for targeted monitoring rules */
DROP VIEW IF EXISTS q6_fraud_by_location;
CREATE VIEW q6_fraud_by_location AS
SELECT
    Location,
    COUNT(*)                                   AS total_transactions,
    SUM(IsFraud)                                AS fraud_count,
    ROUND(100.0 * SUM(IsFraud) / COUNT(*), 3)   AS fraud_rate_pct
FROM cleaned_transactions
GROUP BY Location
ORDER BY fraud_rate_pct DESC;


/* Q7. Overall summary KPIs for the dashboard header */
DROP VIEW IF EXISTS q7_summary_kpis;
CREATE VIEW q7_summary_kpis AS
SELECT
    COUNT(*)                                        AS total_transactions,
    SUM(IsFraud)                                    AS total_fraud_cases,
    ROUND(100.0 * SUM(IsFraud) / COUNT(*), 3)       AS overall_fraud_rate_pct,
    ROUND(SUM(CASE WHEN IsFraud=1 THEN Amount ELSE 0 END), 2) AS fraud_value_at_risk,
    ROUND(AVG(Amount), 2)                           AS avg_transaction_amount
FROM cleaned_transactions;
