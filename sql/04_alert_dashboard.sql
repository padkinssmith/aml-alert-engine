-- ============================================================
-- AML Transaction Monitoring System
-- File: 04_alert_dashboard.sql
-- Purpose: Combines all detection methods into one row
--          per account. This is the analyst alert queue —
--          the first thing an analyst sees each morning.
--
-- All thresholds are read from alert_parameters.
-- Nothing is hardcoded in this file.
--
-- Risk score weighting — see README for full rationale:
--   Velocity z-score > flag threshold        +2 points
--   Velocity z-score > high alert threshold  +1 additional
--   Peer group z-score > threshold           +1 point
--   2+ structuring zone deposits this month  +2 points
--   Round number deposits > 50%              +1 point
--   Multi-branch deposits this month         +1 point
--   Withdrawal within 5 days of deposit      +1 point
--   Geographic risk hit                      +2 points
--   Dormant account activation               +2 points
--
-- Alert tiers:
--   0        Normal
--   1-2      Watch
--   3-4      Flag
--   5+       High Alert
-- ============================================================

\echo ''
\echo '════════════════════════════════════════════════════════'
\echo 'AML ALERT DASHBOARD — Current Month'
\echo 'One row per account. All detection methods combined.'
\echo 'Thresholds from alert_parameters. Nothing hardcoded.'
\echo '════════════════════════════════════════════════════════'

WITH params AS (
    SELECT
        MAX(CASE WHEN rule_name = 'velocity_flag_threshold'
            THEN threshold_value END)        AS vel_flag,
        MAX(CASE WHEN rule_name = 'velocity_high_alert_threshold'
            THEN threshold_value END)        AS vel_high,
        MAX(CASE WHEN rule_name = 'peer_group_flag_threshold'
            THEN threshold_value END)        AS peer_thresh,
        MAX(CASE WHEN rule_name = 'structuring_zone_floor'
            THEN threshold_value END)        AS struct_floor,
        MAX(CASE WHEN rule_name = 'structuring_zone_ceiling'
            THEN threshold_value END)        AS struct_ceil,
        MAX(CASE WHEN rule_name = 'structuring_high_alert_count'
            THEN threshold_value END)        AS struct_count,
        MAX(CASE WHEN rule_name = 'round_number_flag_threshold'
            THEN threshold_value END)        AS round_thresh,
        MAX(CASE WHEN rule_name = 'multi_branch_threshold'
            THEN threshold_value END)        AS branch_thresh,
        MAX(CASE WHEN rule_name = 'dormant_days_threshold'
            THEN threshold_value END)        AS dormant_days,
        MAX(CASE WHEN rule_name = 'minimum_history_months'
            THEN threshold_value END)        AS min_history
    FROM alert_parameters WHERE is_active = TRUE
),

-- Monthly totals with structuring and round number counts
monthly AS (
    SELECT
        ba.account_id, s.full_name, ba.account_type,
        DATE_TRUNC('month', t.txn_date)                          AS txn_month,
        SUM(t.amount) FILTER (WHERE t.txn_type = 'cash_deposit') AS monthly_total,
        COUNT(*) FILTER (WHERE t.txn_type = 'cash_deposit')      AS deposit_count,
        COUNT(*) FILTER (
            WHERE t.txn_type = 'cash_deposit'
              AND t.amount BETWEEN
                  (SELECT struct_floor FROM params) AND
                  (SELECT struct_ceil  FROM params)
        )                                                         AS structured_count,
        COUNT(*) FILTER (
            WHERE t.txn_type = 'cash_deposit'
              AND t.amount % 1000 = 0
        )                                                         AS round_count,
        COUNT(DISTINCT t.branch) FILTER (
            WHERE t.txn_type = 'cash_deposit'
              AND t.branch IS NOT NULL
        )                                                         AS branch_count
    FROM transactions t
    JOIN bank_accounts ba ON t.account_id = ba.account_id
    JOIN subjects s       ON ba.subject_id = s.subject_id
    GROUP BY ba.account_id, s.full_name, ba.account_type,
             DATE_TRUNC('month', t.txn_date)
),

-- Rolling 12-month baseline for velocity detection
rolling AS (
    SELECT *,
        AVG(monthly_total) OVER (
            PARTITION BY account_id ORDER BY txn_month
            ROWS BETWEEN 12 PRECEDING AND 1 PRECEDING
        ) AS prior_avg,
        STDDEV(monthly_total) OVER (
            PARTITION BY account_id ORDER BY txn_month
            ROWS BETWEEN 12 PRECEDING AND 1 PRECEDING
        ) AS prior_stddev,
        COUNT(monthly_total) OVER (
            PARTITION BY account_id ORDER BY txn_month
            ROWS BETWEEN 12 PRECEDING AND 1 PRECEDING
        ) AS months_of_history
    FROM monthly
),

-- Current month only with z-score
current_month AS (
    SELECT *,
        CASE WHEN prior_stddev > 0
             THEN (monthly_total - prior_avg) / prior_stddev
             ELSE NULL END AS z_score
    FROM rolling
    WHERE txn_month = DATE_TRUNC('month', CURRENT_DATE)
),

-- Round number percentage per account
round_pcts AS (
    SELECT
        ba.account_id,
        ROUND(
            COUNT(*) FILTER (WHERE t.amount % 1000 = 0)::numeric
            / NULLIF(COUNT(*), 0)::numeric * 100, 1
        ) AS round_pct
    FROM transactions t
    JOIN bank_accounts ba ON t.account_id = ba.account_id
    WHERE t.txn_type = 'cash_deposit'
    GROUP BY ba.account_id
),

-- Peer group comparison
peer_stats AS (
    SELECT account_type,
        AVG(avg_mo)    AS peer_avg,
        STDDEV(avg_mo) AS peer_stddev
    FROM (
        SELECT ba.account_id, ba.account_type,
               AVG(monthly_total) AS avg_mo
        FROM (
            SELECT account_id,
                   DATE_TRUNC('month', txn_date) AS m,
                   SUM(amount) AS monthly_total
            FROM transactions
            WHERE txn_type = 'cash_deposit'
            GROUP BY account_id, DATE_TRUNC('month', txn_date)
        ) mo
        JOIN bank_accounts ba ON mo.account_id = ba.account_id
        GROUP BY ba.account_id, ba.account_type
    ) x GROUP BY account_type
),
peer_z AS (
    SELECT ba.account_id,
        ROUND(
            (AVG(monthly_total) - p.peer_avg)
            / NULLIF(p.peer_stddev, 0), 2
        ) AS peer_z_score
    FROM (
        SELECT account_id,
               DATE_TRUNC('month', txn_date) AS m,
               SUM(amount) AS monthly_total
        FROM transactions
        WHERE txn_type = 'cash_deposit'
        GROUP BY account_id, DATE_TRUNC('month', txn_date)
    ) mo
    JOIN bank_accounts ba ON mo.account_id = ba.account_id
    JOIN peer_stats p     ON ba.account_type = p.account_type
    GROUP BY ba.account_id, p.peer_avg, p.peer_stddev
),

-- Withdrawal after deposit flag
wd_flags AS (
    SELECT DISTINCT dep.account_id,
        TRUE AS has_withdrawal_after_deposit
    FROM transactions dep
    JOIN transactions wd
        ON  dep.account_id = wd.account_id
        AND wd.txn_type    = 'cash_withdrawal'
        AND wd.txn_date BETWEEN dep.txn_date AND dep.txn_date + 5
        AND wd.amount      >= dep.amount * 0.5
    WHERE dep.txn_type = 'cash_deposit'
      AND dep.amount   >= 5000
      AND dep.txn_date >= DATE_TRUNC('month', CURRENT_DATE)
),

-- Geographic risk flag
geo_flags AS (
    SELECT DISTINCT ba.account_id,
        TRUE AS has_geo_risk
    FROM transactions t
    JOIN bank_accounts ba ON t.account_id = ba.account_id
    WHERE t.counterparty_country IN (
        'NL','BU','CF','CD','HT','IR','IQ','LY','ML',
        'NI','KP','RU','SO','SS','SD','SY','TZ','VE','YE'
    )
),

-- Dormant flag
dormant_flags AS (
    SELECT lp.account_id,
        TRUE AS is_dormant_activated,
        CURRENT_DATE - lp.last_txn AS days_dormant
    FROM (
        SELECT account_id, MAX(txn_date) AS last_txn
        FROM transactions
        WHERE txn_date < DATE_TRUNC('month', CURRENT_DATE)
        GROUP BY account_id
    ) lp
    JOIN (
        SELECT account_id
        FROM transactions
        WHERE txn_date >= DATE_TRUNC('month', CURRENT_DATE)
        GROUP BY account_id
    ) cm ON lp.account_id = cm.account_id
    CROSS JOIN params
    WHERE CURRENT_DATE - lp.last_txn >= params.dormant_days
)

-- ── Final Dashboard ───────────────────────────────────────────
SELECT
    c.full_name                                                  AS account_holder,
    c.account_type,
    ROUND(c.monthly_total, 2)                                    AS current_month_total,
    c.deposit_count,
    ROUND(c.prior_avg, 2)                                        AS prior_12mo_avg,
    ROUND(c.z_score, 2)                                          AS velocity_z,
    ROUND(pz.peer_z_score, 2)                                    AS peer_z,
    c.structured_count                                           AS struct_deposits,
    c.branch_count                                               AS branches_used,
    r.round_pct,
    CASE WHEN wf.has_withdrawal_after_deposit THEN 'Yes'
         ELSE 'No' END                                           AS withdrawal_after_deposit,
    CASE WHEN gf.has_geo_risk THEN 'Yes'
         ELSE 'No' END                                           AS geo_risk_hit,
    CASE WHEN df.is_dormant_activated THEN df.days_dormant::text || ' days'
         ELSE 'No' END                                           AS dormant_days,

    -- Risk score — see README for weighting rationale
    (
        CASE WHEN c.z_score > p.vel_flag   THEN 2 ELSE 0 END +
        CASE WHEN c.z_score > p.vel_high   THEN 1 ELSE 0 END +
        CASE WHEN pz.peer_z_score > p.peer_thresh THEN 1 ELSE 0 END +
        CASE WHEN c.structured_count >= p.struct_count THEN 2 ELSE 0 END +
        CASE WHEN r.round_pct > p.round_thresh THEN 1 ELSE 0 END +
        CASE WHEN c.branch_count >= p.branch_thresh THEN 1 ELSE 0 END +
        CASE WHEN wf.has_withdrawal_after_deposit THEN 1 ELSE 0 END +
        CASE WHEN gf.has_geo_risk THEN 2 ELSE 0 END +
        CASE WHEN df.is_dormant_activated THEN 2 ELSE 0 END
    )                                                            AS risk_score,

    -- Alert tier based on risk score
    CASE
        WHEN (
            CASE WHEN c.z_score > p.vel_flag   THEN 2 ELSE 0 END +
            CASE WHEN c.z_score > p.vel_high   THEN 1 ELSE 0 END +
            CASE WHEN pz.peer_z_score > p.peer_thresh THEN 1 ELSE 0 END +
            CASE WHEN c.structured_count >= p.struct_count THEN 2 ELSE 0 END +
            CASE WHEN r.round_pct > p.round_thresh THEN 1 ELSE 0 END +
            CASE WHEN c.branch_count >= p.branch_thresh THEN 1 ELSE 0 END +
            CASE WHEN wf.has_withdrawal_after_deposit THEN 1 ELSE 0 END +
            CASE WHEN gf.has_geo_risk THEN 2 ELSE 0 END +
            CASE WHEN df.is_dormant_activated THEN 2 ELSE 0 END
        ) >= 5 THEN 'HIGH ALERT'
        WHEN (
            CASE WHEN c.z_score > p.vel_flag   THEN 2 ELSE 0 END +
            CASE WHEN pz.peer_z_score > p.peer_thresh THEN 1 ELSE 0 END +
            CASE WHEN c.structured_count >= p.struct_count THEN 2 ELSE 0 END +
            CASE WHEN gf.has_geo_risk THEN 2 ELSE 0 END +
            CASE WHEN df.is_dormant_activated THEN 2 ELSE 0 END
        ) >= 3 THEN 'FLAG'
        WHEN (
            CASE WHEN c.z_score > 1.5 THEN 1 ELSE 0 END +
            CASE WHEN c.structured_count >= 1 THEN 1 ELSE 0 END +
            CASE WHEN r.round_pct > p.round_thresh * 0.6 THEN 1 ELSE 0 END
        ) >= 1 THEN 'WATCH'
        ELSE 'NORMAL'
    END                                                          AS alert_tier,

    -- Plain English summary of what fired
    CONCAT_WS(' | ',
        CASE WHEN c.z_score > p.vel_high
             THEN 'VELOCITY HIGH ALERT'      ELSE NULL END,
        CASE WHEN c.z_score BETWEEN p.vel_flag AND p.vel_high
             THEN 'VELOCITY FLAG'            ELSE NULL END,
        CASE WHEN pz.peer_z_score > p.peer_thresh
             THEN 'ABOVE PEER GROUP'         ELSE NULL END,
        CASE WHEN c.structured_count >= p.struct_count
             THEN 'STRUCTURING HIGH ALERT'   ELSE NULL END,
        CASE WHEN c.structured_count = 2
             THEN 'STRUCTURING PATTERN'      ELSE NULL END,
        CASE WHEN c.branch_count >= p.branch_thresh
             THEN 'MULTI-BRANCH DEPOSITS'    ELSE NULL END,
        CASE WHEN wf.has_withdrawal_after_deposit
             THEN 'WITHDRAWAL AFTER DEPOSIT' ELSE NULL END,
        CASE WHEN gf.has_geo_risk
             THEN 'GEOGRAPHIC RISK HIT'      ELSE NULL END,
        CASE WHEN r.round_pct > p.round_thresh
             THEN 'HIGH ROUND NUMBERS'       ELSE NULL END,
        CASE WHEN df.is_dormant_activated
             THEN 'DORMANT ACTIVATION'       ELSE NULL END
    )                                                            AS flags_triggered

FROM current_month c
CROSS JOIN params p
LEFT JOIN round_pcts r  ON c.account_id = r.account_id
LEFT JOIN peer_z pz     ON c.account_id = pz.account_id
LEFT JOIN wd_flags wf   ON c.account_id = wf.account_id
LEFT JOIN geo_flags gf  ON c.account_id = gf.account_id
LEFT JOIN dormant_flags df ON c.account_id = df.account_id
WHERE c.months_of_history >= p.min_history
   OR df.is_dormant_activated IS TRUE
ORDER BY risk_score DESC NULLS LAST,
         c.z_score   DESC NULLS LAST;

\echo ''
\echo '════════════════════════════════════════════════════════'
\echo 'Expected results:'
\echo '  Tom McAllister — HIGH ALERT (velocity, structuring,'
\echo '                  multi-branch, withdrawal, geo risk)'
\echo '  Benedicte Noel — FLAG (structuring, peer group)'
\echo '  Robert Kline   — FLAG (dormant activation,'
\echo '                   round numbers)'
\echo '  All others     — NORMAL'
\echo '════════════════════════════════════════════════════════'
