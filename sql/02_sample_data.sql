-- ============================================================
-- AML Transaction Monitoring System
-- File: 02_sample_data.sql
-- Purpose: Loads detection thresholds and sample transactions.
--          Patterns are built in deliberately so each detection
--          method fires on the right accounts.
--
-- Subjects and their built-in patterns:
--
--   Tom McAllister    (flower shop)  SUSPICIOUS
--     — Normal for 12 months then sudden spike this month
--     — Four deposits across three different branches
--     — All deposits just under $10,000
--     — Prior wire transfer to Netherlands
--     — Cash withdrawals following deposits
--     — Triggers: velocity, structuring, multi-branch,
--                 peer group, withdrawal-after-deposit,
--                 geographic risk
--
--   Bénédicte Noël   (gas station)  SUSPICIOUS
--     — Every month deposits just under $10,000
--     — Pattern is consistent so own-history looks normal
--     — But far above what other retail accounts deposit
--     — Triggers: structuring, peer group anomaly
--
--   Robert Kline      (personal)     SUSPICIOUS
--     — No activity for 6 months then large deposit this month
--     — Deposit is a round number
--     — Triggers: dormant account activation, round numbers
--
--   Maria Santos      (restaurant)   NORMAL — peer baseline
--   James Okafor      (restaurant)   NORMAL — peer baseline
--   Linda Park        (restaurant)   NORMAL — slightly elevated
--   Miguel Torres     (restaurant)   NORMAL — peer baseline
--   Grace Nwosu       (restaurant)   NORMAL — peer baseline
--   Carlos Rivera     (flower shop)  NORMAL — peer baseline
--   Amy Chen          (flower shop)  NORMAL — peer baseline
--   David Osei        (flower shop)  NORMAL — peer baseline
--   Sarah Kim         (flower shop)  NORMAL — peer baseline
--
-- More peer group members = more stable statistics.
-- With only 3 accounts per group one outlier distorts the
-- average. With 5 accounts per group the math is reliable.
-- ============================================================


-- ============================================================
-- PART 1: DETECTION THRESHOLDS
-- ============================================================
-- These numbers are the settings the detection engine uses.
-- Changing a number here changes how the system behaves
-- without touching any detection query.
-- Each threshold has a regulatory basis explaining why
-- that specific number was chosen.

INSERT INTO alert_parameters
    (rule_name, description, threshold_value, threshold_unit,
     regulatory_basis, effective_date, last_reviewed, reviewed_by)
VALUES
(
    'velocity_flag_threshold',
    'Current month z-score above this value triggers a FLAG',
    2.0,
    'std_deviations',
    'BSA 31 U.S.C. 5318(g) — SAR filing required for suspicious transactions of $5,000 or more. FinCEN guidance FIN-2012-G002. Threshold of 2.0 standard deviations is consistent with peer institution benchmarks and produces a manageable false positive rate while capturing meaningful anomalies.',
    CURRENT_DATE, CURRENT_DATE, 'System Default'
),
(
    'velocity_high_alert_threshold',
    'Current month z-score above this value triggers a HIGH ALERT',
    3.0,
    'std_deviations',
    'BSA 31 U.S.C. 5318(g). Threshold of 3.0 standard deviations represents activity more than three times removed from normal variation. At this level the probability of a legitimate explanation decreases significantly and immediate review is warranted.',
    CURRENT_DATE, CURRENT_DATE, 'System Default'
),
(
    'peer_group_flag_threshold',
    'Peer group z-score above this value triggers a peer anomaly flag',
    2.0,
    'std_deviations',
    'FinCEN Customer Due Diligence Final Rule 31 CFR 1010.230. CDD requires understanding expected account activity. Peer group comparison identifies accounts operating significantly outside what is normal for their business type, supporting enhanced due diligence decisions.',
    CURRENT_DATE, CURRENT_DATE, 'System Default'
),
(
    'structuring_zone_floor',
    'Lower bound of the structuring detection zone in dollars',
    8000.00,
    'usd',
    'BSA 31 U.S.C. 5324 — structuring prohibition. CTR threshold is $10,000 under 31 CFR 1010.311. Floor set at $8,000 to catch deliberate sub-threshold activity while excluding routine small cash transactions. Zone width of $2,000 is consistent with FinCEN advisory FIN-2010-A001.',
    CURRENT_DATE, CURRENT_DATE, 'System Default'
),
(
    'structuring_zone_ceiling',
    'Upper bound of the structuring detection zone in dollars',
    9999.99,
    'usd',
    'BSA 31 U.S.C. 5324. Ceiling set at one cent below the $10,000 CTR filing threshold under 31 CFR 1010.311.',
    CURRENT_DATE, CURRENT_DATE, 'System Default'
),
(
    'structuring_high_alert_count',
    'Deposits in the structuring zone within one month that trigger HIGH ALERT',
    3.0,
    'count',
    'BSA 31 U.S.C. 5324. Three or more below-threshold deposits in a single month is a primary structuring indicator per FinCEN advisory FIN-2010-A001 and consistent with federal case law on structuring prosecution.',
    CURRENT_DATE, CURRENT_DATE, 'System Default'
),
(
    'structuring_week_count',
    'Deposits in the structuring zone within any 7-day window that trigger HIGH ALERT',
    2.0,
    'count',
    'BSA 31 U.S.C. 5324. Two or more below-threshold deposits within a single week indicates more urgent structuring behavior than monthly patterns alone capture. Weekly window analysis is a secondary detection layer.',
    CURRENT_DATE, CURRENT_DATE, 'System Default'
),
(
    'round_number_flag_threshold',
    'Percentage of round-dollar deposits above which a flag fires',
    50.0,
    'pct',
    'FATF Typology Report: Money Laundering Through Physical Transportation of Cash (2015). Round dollar amounts are a primary indicator of pre-counted criminal proceeds. Legitimate business cash transactions rarely produce exact round figures.',
    CURRENT_DATE, CURRENT_DATE, 'System Default'
),
(
    'dormant_days_threshold',
    'Days of inactivity after which an account is considered dormant',
    90.0,
    'count',
    'BSA 31 U.S.C. 5318(g). Reactivation of a dormant account is a recognized typology indicator. Ninety days is the standard industry threshold for defining dormancy, consistent with federal examination guidance.',
    CURRENT_DATE, CURRENT_DATE, 'System Default'
),
(
    'multi_branch_threshold',
    'Number of different branches in a single month that triggers a flag',
    2.0,
    'count',
    'BSA 31 U.S.C. 5324. Using multiple branches to make deposits is a documented structuring method. Transactions at two or more branches in a single month warrant review per FinCEN guidance on structuring indicators.',
    CURRENT_DATE, CURRENT_DATE, 'System Default'
),
(
    'minimum_history_months',
    'Months of history required before statistical alerts are generated',
    3.0,
    'count',
    'Internal control requirement. Statistical calculations require sufficient data to be meaningful. Fewer than three months of history produces unreliable averages and standard deviations. Accounts below this threshold are flagged for manual review instead.',
    CURRENT_DATE, CURRENT_DATE, 'System Default'
),
(
    'alert_sla_days',
    'Maximum days from alert creation to analyst first review',
    5.0,
    'count',
    'Internal SLA. FINRA Rule 3310 requires prompt review of alerts. Five calendar days is the internal standard consistent with peer institution benchmarks and supports the 30-day SAR filing window under 31 CFR 1020.320.',
    CURRENT_DATE, CURRENT_DATE, 'System Default'
),
(
    'case_sla_days',
    'Maximum days from case opening to disposition decision',
    30.0,
    'count',
    'BSA 31 CFR 1020.320(b)(3). SARs must be filed within 30 calendar days of detection, or 60 days if no suspect is identified. Internal case SLA set at 30 days to ensure timely filing.',
    CURRENT_DATE, CURRENT_DATE, 'System Default'
);


-- ============================================================
-- PART 2: SUBJECTS
-- ============================================================

INSERT INTO subjects
    (full_name, alias, occupation, account_type,
     pep_status, risk_rating)
VALUES
    -- Suspicious subjects
    ('Tom McAllister',  'Tomas MacAllister', 'Flower Shop Owner', 'business_retail',      FALSE, 'high'),
    ('Bénédicte Noël', NULL,                'Gas Station Owner', 'business_retail',      FALSE, 'standard'),
    ('Robert Kline',    NULL,                'Consultant',        'personal',             FALSE, 'standard'),
    -- Normal restaurant peer group (5 accounts = stable statistics)
    ('Maria Santos',    NULL,                'Restaurant Owner',  'business_restaurant',  FALSE, 'standard'),
    ('James Okafor',    NULL,                'Restaurant Owner',  'business_restaurant',  FALSE, 'standard'),
    ('Linda Park',      NULL,                'Restaurant Owner',  'business_restaurant',  FALSE, 'standard'),
    ('Miguel Torres',   NULL,                'Restaurant Owner',  'business_restaurant',  FALSE, 'standard'),
    ('Grace Nwosu',     NULL,                'Restaurant Owner',  'business_restaurant',  FALSE, 'standard'),
    -- Normal flower shop peer group (5 accounts = stable statistics)
    ('Carlos Rivera',   NULL,                'Flower Shop Owner', 'business_retail',      FALSE, 'standard'),
    ('Amy Chen',        NULL,                'Flower Shop Owner', 'business_retail',      FALSE, 'standard'),
    ('David Osei',      NULL,                'Flower Shop Owner', 'business_retail',      FALSE, 'standard'),
    ('Sarah Kim',       NULL,                'Flower Shop Owner', 'business_retail',      FALSE, 'standard');


-- ============================================================
-- PART 3: BANK ACCOUNTS
-- ============================================================

INSERT INTO bank_accounts
    (subject_id, bank_name, account_number, account_type)
VALUES
    (1,  'Citibank', 'ACC-TM-001', 'business_retail'),
    (2,  'BNP',      'ACC-BN-002', 'business_retail'),
    (3,  'Wells',    'ACC-RK-003', 'personal'),
    (4,  'HSBC',     'ACC-MS-004', 'business_restaurant'),
    (5,  'Citibank', 'ACC-JO-005', 'business_restaurant'),
    (6,  'HSBC',     'ACC-LP-006', 'business_restaurant'),
    (7,  'Chase',    'ACC-MT-007', 'business_restaurant'),
    (8,  'Wells',    'ACC-GN-008', 'business_restaurant'),
    (9,  'Citibank', 'ACC-CR-009', 'business_retail'),
    (10, 'HSBC',     'ACC-AC-010', 'business_retail'),
    (11, 'Chase',    'ACC-DO-011', 'business_retail'),
    (12, 'Wells',    'ACC-SK-012', 'business_retail');


-- ============================================================
-- PART 4: TRANSACTIONS
-- ============================================================


-- ── Tom McAllister (account 1) ───────────────────────────────
-- 12 months of normal deposits around $3,000 per month.
-- Then this month: four large deposits across three branches,
-- each just under $10,000.
-- Plus a prior wire to the Netherlands.
-- Plus cash withdrawals following deposits.

-- Normal history: 12 prior months
INSERT INTO transactions
    (account_id, txn_date, amount, txn_type, branch, str_flag, notes)
SELECT
    1,
    (DATE_TRUNC('month', CURRENT_DATE)
        - (n || ' months')::interval)::date + (random()*20)::int,
    ROUND((2800 + random()*400)::numeric, 2),
    'cash_deposit',
    'Main Street Branch',
    FALSE,
    'Regular monthly flower shop deposit'
FROM generate_series(1, 12) AS n;

-- This month: four suspicious deposits across three branches
INSERT INTO transactions
    (account_id, txn_date, amount, txn_type,
     branch, str_flag, notes)
VALUES
(1, DATE_TRUNC('month', CURRENT_DATE)::date + 2,
    9800.00, 'cash_deposit',
    'Main Street Branch',   TRUE, 'Large cash deposit'),
(1, DATE_TRUNC('month', CURRENT_DATE)::date + 5,
    9500.00, 'cash_deposit',
    'Riverside Branch',     TRUE, 'Large cash deposit'),
(1, DATE_TRUNC('month', CURRENT_DATE)::date + 9,
    9750.00, 'cash_deposit',
    'Airport Road Branch',  TRUE, 'Large cash deposit'),
(1, DATE_TRUNC('month', CURRENT_DATE)::date + 14,
    9900.00, 'cash_deposit',
    'Riverside Branch',     TRUE, 'Large cash deposit');

-- Withdrawal after deposit — classic layering behavior.
-- Money comes in as cash then quickly leaves.
INSERT INTO transactions
    (account_id, txn_date, amount, txn_type, branch, notes)
VALUES
(1, DATE_TRUNC('month', CURRENT_DATE)::date + 4,
    8500.00, 'cash_withdrawal',
    'Main Street Branch',
    'Cash withdrawal two days after large deposit'),
(1, DATE_TRUNC('month', CURRENT_DATE)::date + 7,
    7200.00, 'cash_withdrawal',
    'Riverside Branch',
    'Cash withdrawal two days after large deposit');

-- Prior international wire to Netherlands
-- This shows up in the geographic risk detection
INSERT INTO transactions
    (account_id, txn_date, amount, txn_type,
     counterparty, counterparty_bank,
     counterparty_country, notes)
VALUES
(1, DATE_TRUNC('month', CURRENT_DATE)::date - 45,
    17500.00, 'wire_out',
    'Tulips United B.V.',
    'ABN AMRO',
    'NL',
    'Wire to Netherlands entity — no documented business purpose');


-- ── Bénédicte Noël (account 2) ──────────────────────────────
-- Every single month deposits just under $10,000.
-- Own-history z-score stays near zero because it is consistent.
-- But peer group z-score flags it as far above retail peers.

INSERT INTO transactions
    (account_id, txn_date, amount, txn_type, str_flag, notes)
SELECT
    2,
    (DATE_TRUNC('month', CURRENT_DATE)
        - (n || ' months')::interval)::date + (random()*20)::int,
    ROUND((9100 + random()*700)::numeric, 2),
    'cash_deposit',
    FALSE,
    'Monthly cash deposit'
FROM generate_series(0, 12) AS n;


-- ── Robert Kline (account 3) — DORMANT ACTIVATION ───────────
-- No activity for 6 months.
-- Then suddenly this month: a large round-number deposit.
-- Both the dormancy and the round number are suspicious.

INSERT INTO transactions
    (account_id, txn_date, amount, txn_type, notes)
SELECT
    3,
    (DATE_TRUNC('month', CURRENT_DATE)
        - (n || ' months')::interval)::date + (random()*20)::int,
    ROUND((800 + random()*400)::numeric, 2),
    'cash_deposit',
    'Regular small deposit'
FROM generate_series(7, 12) AS n;
-- Months 1 through 6: no transactions at all (dormant period)

-- This month: sudden large round-number deposit
INSERT INTO transactions
    (account_id, txn_date, amount, txn_type, notes)
VALUES
(3, DATE_TRUNC('month', CURRENT_DATE)::date + 3,
    15000.00, 'cash_deposit',
    'Large round-dollar deposit after 6 months of no activity');


-- ── Restaurant peer group — all normal ───────────────────────
-- Five restaurant accounts with realistic variation.
-- These establish the peer average for restaurant accounts.
-- None should trigger alerts.

-- Maria Santos
INSERT INTO transactions
    (account_id, txn_date, amount, txn_type, notes)
SELECT 4,
    (DATE_TRUNC('month', CURRENT_DATE)
        - (n || ' months')::interval)::date + (random()*20)::int,
    ROUND((8000 + random()*3000)::numeric, 2),
    'cash_deposit', 'Restaurant daily cash'
FROM generate_series(0, 12) AS n;

-- James Okafor
INSERT INTO transactions
    (account_id, txn_date, amount, txn_type, notes)
SELECT 5,
    (DATE_TRUNC('month', CURRENT_DATE)
        - (n || ' months')::interval)::date + (random()*20)::int,
    ROUND((7500 + random()*2500)::numeric, 2),
    'cash_deposit', 'Restaurant cash deposit'
FROM generate_series(0, 12) AS n;

-- Linda Park — slightly above average, still normal
INSERT INTO transactions
    (account_id, txn_date, amount, txn_type, notes)
SELECT 6,
    (DATE_TRUNC('month', CURRENT_DATE)
        - (n || ' months')::interval)::date + (random()*20)::int,
    ROUND((11000 + random()*2000)::numeric, 2),
    'cash_deposit', 'Restaurant cash deposit'
FROM generate_series(0, 12) AS n;

-- Miguel Torres
INSERT INTO transactions
    (account_id, txn_date, amount, txn_type, notes)
SELECT 7,
    (DATE_TRUNC('month', CURRENT_DATE)
        - (n || ' months')::interval)::date + (random()*20)::int,
    ROUND((8500 + random()*2000)::numeric, 2),
    'cash_deposit', 'Restaurant cash deposit'
FROM generate_series(0, 12) AS n;

-- Grace Nwosu
INSERT INTO transactions
    (account_id, txn_date, amount, txn_type, notes)
SELECT 8,
    (DATE_TRUNC('month', CURRENT_DATE)
        - (n || ' months')::interval)::date + (random()*20)::int,
    ROUND((9000 + random()*1500)::numeric, 2),
    'cash_deposit', 'Restaurant cash deposit'
FROM generate_series(0, 12) AS n;


-- ── Flower shop peer group — all normal ──────────────────────
-- Four more flower shop accounts alongside McAllister.
-- These establish the peer average for retail accounts.
-- McAllister's deposits will stand out sharply against them.

-- Carlos Rivera
INSERT INTO transactions
    (account_id, txn_date, amount, txn_type, notes)
SELECT 9,
    (DATE_TRUNC('month', CURRENT_DATE)
        - (n || ' months')::interval)::date + (random()*20)::int,
    ROUND((2500 + random()*1000)::numeric, 2),
    'cash_deposit', 'Flower shop cash'
FROM generate_series(0, 12) AS n;

-- Amy Chen
INSERT INTO transactions
    (account_id, txn_date, amount, txn_type, notes)
SELECT 10,
    (DATE_TRUNC('month', CURRENT_DATE)
        - (n || ' months')::interval)::date + (random()*20)::int,
    ROUND((3000 + random()*800)::numeric, 2),
    'cash_deposit', 'Flower shop cash'
FROM generate_series(0, 12) AS n;

-- David Osei
INSERT INTO transactions
    (account_id, txn_date, amount, txn_type, notes)
SELECT 11,
    (DATE_TRUNC('month', CURRENT_DATE)
        - (n || ' months')::interval)::date + (random()*20)::int,
    ROUND((2700 + random()*600)::numeric, 2),
    'cash_deposit', 'Flower shop cash'
FROM generate_series(0, 12) AS n;

-- Sarah Kim
INSERT INTO transactions
    (account_id, txn_date, amount, txn_type, notes)
SELECT 12,
    (DATE_TRUNC('month', CURRENT_DATE)
        - (n || ' months')::interval)::date + (random()*20)::int,
    ROUND((2900 + random()*700)::numeric, 2),
    'cash_deposit', 'Flower shop cash'
FROM generate_series(0, 12) AS n;


\echo ''
\echo 'Sample data loaded.'
\echo ''
\echo 'Thresholds loaded:  13 detection parameters'
\echo 'Subjects loaded:    12 (3 suspicious, 9 normal)'
\echo 'Accounts loaded:    12'
\echo 'Peer group size:    5 restaurants, 5 flower shops'
\echo ''
\echo 'Suspicious patterns built in:'
\echo '  McAllister  — velocity spike, multi-branch, structuring,'
\echo '                withdrawal after deposit, geographic risk'
\echo '  Noel        — structuring, peer group anomaly'
\echo '  Kline       — dormant activation, round numbers'
\echo ''
\echo 'Next: run sql/03_detection_engine.sql'
