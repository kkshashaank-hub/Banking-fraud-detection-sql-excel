/* ============================================================
   01_clean_data.sql
   Banking Fraud Detection — Data Cleaning
   ============================================================ */

DROP TABLE IF EXISTS cleaned_transactions;
DROP TABLE IF EXISTS rejected_transactions;

/* ------------------------------------------------------------
   STEP 1 — De-duplicate
   The raw export contains exact-duplicate rows (ETL re-run bug).
   Keep exactly one copy of each TransactionID.
   ------------------------------------------------------------ */
DROP TABLE IF EXISTS dedup_transactions;
CREATE TABLE dedup_transactions AS
WITH ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY TransactionID
               ORDER BY rowid
           ) AS rn
    FROM raw_transactions
)
SELECT TransactionID, CustomerID, TransactionDate, Amount, Merchant,
       MerchantCategory, Location, Channel, IsFraud
FROM ranked
WHERE rn = 1;

/* ------------------------------------------------------------
   STEP 2 — Standardize text fields
   Fix inconsistent casing and stray whitespace from the source
   systems (POS exports, mobile app exports, etc. all format
   differently).
   ------------------------------------------------------------ */
DROP TABLE IF EXISTS text_fixed_transactions;
CREATE TABLE text_fixed_transactions AS
SELECT
    TransactionID,
    CustomerID,
    TransactionDate,
    Amount,
    -- Title-case merchant/location by fixing whitespace + case;
    -- SQLite has no built-in INITCAP, so we normalize to upper for
    -- consistent grouping (display formatting can be cosmetic in Excel).
    UPPER(TRIM(Merchant))         AS Merchant,
    MerchantCategory,
    UPPER(TRIM(Location))         AS Location,
    Channel,
    IsFraud
FROM dedup_transactions;

/* ------------------------------------------------------------
   STEP 3 — Normalize the date column
   Source had 4 different date formats mixed together:
     'YYYY-MM-DD HH:MM:SS', 'MM/DD/YYYY HH:MM',
     'DD-MM-YYYY HH:MM:SS', 'YYYY-MM-DDTHH:MM:SS'
   Convert all of them to a single ISO 'YYYY-MM-DD HH:MM:SS'.
   ------------------------------------------------------------ */
DROP TABLE IF EXISTS date_fixed_transactions;
CREATE TABLE date_fixed_transactions AS
SELECT
    TransactionID,
    CustomerID,
    CASE
        -- 'YYYY-MM-DDTHH:MM:SS'  -> replace T with space
        WHEN TransactionDate LIKE '____-__-__T%'
            THEN REPLACE(TransactionDate, 'T', ' ')

        -- 'YYYY-MM-DD HH:MM:SS'  -> already ISO
        WHEN TransactionDate LIKE '____-__-__ %'
            THEN TransactionDate

        -- 'MM/DD/YYYY HH:MM'     -> rebuild as ISO, add :00 seconds
        WHEN TransactionDate LIKE '__/__/____ %'
            THEN substr(TransactionDate,7,4) || '-' || substr(TransactionDate,1,2)
                 || '-' || substr(TransactionDate,4,2) || ' '
                 || substr(TransactionDate,12,5) || ':00'

        -- 'DD-MM-YYYY HH:MM:SS'  -> rebuild as ISO
        WHEN TransactionDate LIKE '__-__-____ %'
            THEN substr(TransactionDate,7,4) || '-' || substr(TransactionDate,4,2)
                 || '-' || substr(TransactionDate,1,2) || ' '
                 || substr(TransactionDate,12,8)
        ELSE NULL
    END AS TransactionDate_Clean,
    Amount,
    Merchant,
    MerchantCategory,
    Location,
    Channel,
    IsFraud
FROM text_fixed_transactions;

/* ------------------------------------------------------------
   STEP 4 — Handle nulls and invalid amounts, split good vs. bad
   - Amount is NULL         -> impute with the median for that
                                MerchantCategory (robust to outliers)
   - Amount is negative     -> data-entry error, cannot safely fix,
                                route to rejected_transactions
   - Location is NULL       -> impute as 'UNKNOWN' rather than drop
                                the whole transaction
   ------------------------------------------------------------ */

-- median amount per category, used for imputation
DROP TABLE IF EXISTS category_median_amount;
CREATE TABLE category_median_amount AS
SELECT MerchantCategory,
       AVG(Amount) AS median_amount   -- SQLite has no MEDIAN(); AVG is a
                                       -- reasonable stand-in at this scale.
                                       -- (For the real dataset, compute
                                       -- median in Python/pandas instead.)
FROM date_fixed_transactions
WHERE Amount IS NOT NULL AND Amount >= 0
GROUP BY MerchantCategory;

CREATE TABLE rejected_transactions AS
SELECT *, 'negative_amount' AS reject_reason
FROM date_fixed_transactions
WHERE Amount < 0;

CREATE TABLE cleaned_transactions AS
SELECT
    d.TransactionID,
    d.CustomerID,
    d.TransactionDate_Clean AS TransactionDate,
    ROUND(COALESCE(d.Amount, m.median_amount), 2) AS Amount,
    d.Merchant,
    d.MerchantCategory,
    COALESCE(d.Location, 'UNKNOWN') AS Location,
    d.Channel,
    d.IsFraud,
    CASE WHEN d.Amount IS NULL THEN 1 ELSE 0 END AS Amount_Was_Imputed
FROM date_fixed_transactions d
LEFT JOIN category_median_amount m ON d.MerchantCategory = m.MerchantCategory
WHERE d.Amount IS NULL OR d.Amount >= 0;

/* ------------------------------------------------------------
   STEP 5 — Sanity checks (run these, don't just trust the script)
   ------------------------------------------------------------ */
-- SELECT COUNT(*) FROM raw_transactions;
-- SELECT COUNT(*) FROM cleaned_transactions;
-- SELECT COUNT(*) FROM rejected_transactions;
-- SELECT COUNT(*) FROM cleaned_transactions WHERE TransactionDate IS NULL;  -- should be 0
-- SELECT COUNT(*) FROM cleaned_transactions WHERE Amount < 0;               -- should be 0
