-- ============================================================
-- AML Transaction Monitoring System
-- File: 05_case_lifecycle.sql
-- Purpose: Alert persistence, case management, disposition
--          tracking, and audit logging.
--
-- This layer represents what analysts actually do every day.
-- Detection fires an alert. Everything after that lives here.
--
-- Tables built in this file:
--   alert_parameters     — defined in 01_schema.sql, populated in 02_sample_data.sql
--   alerts               — persisted alerts from detection engine
--   cases                — one case per alert accepted for review
--   case_notes           — analyst narrative documentation
--   dispositions         — final outcome of each case
--   audit_log            — every action timestamped and logged
--
-- Operational queries in this file:
--   1. Alert queue       — what an analyst opens every morning
--   2. SLA aging         — alerts and cases approaching deadline
--   3. Case dashboard    — supervisor view of all open work
--   4. Disposition summary — management reporting
--   5. Analyst workload  — caseload per analyst
--   6. SAR referral log  — all cases escalated to SAR filing
-- ============================================================


-- ============================================================
-- ============================================================
-- NOTE: alert_parameters table is defined in 01_schema.sql
-- and populated with detection thresholds in 02_sample_data.sql.
-- The detection engine reads from it throughout.
-- This file uses those thresholds but does not redefine them.
-- ============================================================

-- ============================================================
-- SECTION 1: ALERTS TABLE
-- ============================================================
CREATE TABLE alerts (
    alert_id          SERIAL PRIMARY KEY,
    account_id        INT           REFERENCES bank_accounts(account_id),
    alert_date        DATE          NOT NULL DEFAULT CURRENT_DATE,
    alert_month       DATE          NOT NULL, -- the month being flagged
    detection_rule    VARCHAR(100)  NOT NULL, -- which rule fired
    alert_tier        VARCHAR(20)   NOT NULL, -- HIGH ALERT, FLAG, WATCH
    risk_score        INT           NOT NULL DEFAULT 0,
    velocity_z_score  NUMERIC(8,2),
    peer_z_score      NUMERIC(8,2),
    current_month_amt NUMERIC(14,2),
    prior_12mo_avg    NUMERIC(14,2),
    flags_triggered   TEXT,         -- plain English summary
    status            VARCHAR(30)   NOT NULL DEFAULT 'open',
                                    -- open, under_review, closed, escalated
    assigned_to       VARCHAR(100),
    assigned_date     DATE,
    created_at        TIMESTAMPTZ   DEFAULT NOW(),
    updated_at        TIMESTAMPTZ   DEFAULT NOW()
);

COMMENT ON TABLE alerts IS
'Persisted alerts from the detection engine. Every alert has a lifecycle:
open → under_review → closed or escalated. SLA is tracked from alert_date.
Status open = not yet reviewed. under_review = case opened. closed = cleared
or dispositioned. escalated = referred to senior analyst or law enforcement.';

COMMENT ON COLUMN alerts.alert_month IS
'The calendar month the alert covers. Distinct from alert_date which is
when the alert was generated. Alert may be generated on the 3rd of the
month for activity in the prior month.';

CREATE INDEX idx_alerts_status       ON alerts (status);
CREATE INDEX idx_alerts_account_date ON alerts (account_id, alert_date);
CREATE INDEX idx_alerts_tier         ON alerts (alert_tier);
CREATE INDEX idx_alerts_assigned     ON alerts (assigned_to);


-- ============================================================
-- SECTION 3: CASES TABLE
-- ============================================================
-- One case per alert that moves beyond initial review.
-- Not every alert becomes a case. An analyst can clear an
-- alert without opening a case if the activity has an
-- obvious legitimate explanation.
--
-- When an alert is accepted for investigation, a case is
-- opened here and the alert status updates to under_review.
-- ============================================================

CREATE TABLE cases (
    case_id           SERIAL PRIMARY KEY,
    alert_id          INT           REFERENCES alerts(alert_id),
    case_reference    VARCHAR(50)   NOT NULL UNIQUE,
                                    -- human-readable reference e.g. CASE-2025-001
    subject_id        INT           REFERENCES subjects(subject_id),
    opened_date       DATE          NOT NULL DEFAULT CURRENT_DATE,
    due_date          DATE,         -- calculated from case_sla_days parameter
    assigned_analyst  VARCHAR(100)  NOT NULL,
    supervisor        VARCHAR(100),
    status            VARCHAR(30)   NOT NULL DEFAULT 'open',
                                    -- open, under_review, pending_sar,
                                    -- pending_escalation, closed
    priority          VARCHAR(20)   DEFAULT 'standard',
                                    -- standard, high, critical
    hypothesis        TEXT,         -- analyst's working theory
    typology          VARCHAR(100), -- matched FATF typology
    typology_reference TEXT,        -- FATF report citation
    pep_involved      BOOLEAN       DEFAULT FALSE,
    sanctions_hit     BOOLEAN       DEFAULT FALSE,
    geographic_risk   VARCHAR(20)   DEFAULT 'low',
                                    -- low, medium, high, critical
    closed_date       DATE,
    closed_by         VARCHAR(100),
    created_at        TIMESTAMPTZ   DEFAULT NOW(),
    updated_at        TIMESTAMPTZ   DEFAULT NOW()
);

COMMENT ON TABLE cases IS
'Investigation cases linked to alerts. A case tracks the full investigation
lifecycle from opening through disposition. Due date is calculated from
the case_sla_days parameter. Priority escalates automatically when PEP
involvement or sanctions hits are confirmed.';

CREATE INDEX idx_cases_status    ON cases (status);
CREATE INDEX idx_cases_analyst   ON cases (assigned_analyst);
CREATE INDEX idx_cases_subject   ON cases (subject_id);
CREATE INDEX idx_cases_due_date  ON cases (due_date);
CREATE INDEX idx_cases_reference ON cases (case_reference);


-- ============================================================
-- SECTION 4: CASE NOTES TABLE
-- ============================================================
-- Analyst narrative notes attached to a case.
-- Every significant finding, decision, and action taken
-- during the investigation is documented here.
--
-- This is the investigative record. It is what a supervisor
-- reviews, what an examiner evaluates, and what supports a
-- SAR narrative if filing is required.
--
-- Note types reflect investigation stages. This mirrors
-- the collection plan and investigation methodology from
-- the broader AML framework.
-- ============================================================

CREATE TABLE case_notes (
    note_id           SERIAL PRIMARY KEY,
    case_id           INT           REFERENCES cases(case_id),
    note_date         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    analyst           VARCHAR(100)  NOT NULL,
    note_type         VARCHAR(50)   NOT NULL,
                                    -- initial_review, fiu_search,
                                    -- domestic_closed, domestic_open,
                                    -- international, financial_profile,
                                    -- hypothesis_update, escalation,
                                    -- disposition, general
    note_text         TEXT          NOT NULL,
    source_consulted  VARCHAR(200), -- which database or source this note relates to
    source_reliability VARCHAR(20), -- high, medium, low
    findings          TEXT,         -- key findings from this note's research
    new_leads         TEXT,         -- new subjects, accounts, or companies found
    hypothesis_change TEXT          -- how this finding changed the working theory
);

COMMENT ON TABLE case_notes IS
'Analyst investigation notes. Each note documents a specific research action,
finding, and its impact on the working hypothesis. Together these notes form
the investigative record that supports the disposition decision and SAR
narrative. note_type mirrors the investigation stages in the AML framework.';

CREATE INDEX idx_case_notes_case    ON case_notes (case_id);
CREATE INDEX idx_case_notes_analyst ON case_notes (analyst);
CREATE INDEX idx_case_notes_type    ON case_notes (note_type);


-- ============================================================
-- SECTION 5: DISPOSITIONS TABLE
-- ============================================================
-- Final outcome of each case.
-- Possible dispositions:
--   cleared         — activity explained, no suspicious activity
--   sar_filed       — SAR filed with FinCEN
--   referred_le     — referred to law enforcement directly
--   monitoring      — no SAR now, account placed under monitoring
--   closed_no_action — reviewed, insufficient basis for further action
--
-- SAR filing fields are included for cases where a SAR is filed.
-- SAR reference number, filing date, and the SAR amount are
-- required for program reporting and examination.
-- ============================================================

CREATE TABLE dispositions (
    disposition_id      SERIAL PRIMARY KEY,
    case_id             INT           REFERENCES cases(case_id) UNIQUE,
    disposition_date    DATE          NOT NULL DEFAULT CURRENT_DATE,
    disposition_type    VARCHAR(50)   NOT NULL,
                                      -- cleared, sar_filed, referred_le,
                                      -- monitoring, closed_no_action
    disposition_analyst VARCHAR(100)  NOT NULL,
    supervisor_approval VARCHAR(100), -- required for SAR filings
    approval_date       DATE,

    -- Final analysis fields
    final_hypothesis    TEXT,         -- what the analyst concluded
    typology_confirmed  VARCHAR(100), -- FATF typology matched
    evidence_summary    TEXT,         -- key evidence supporting the disposition
    income_declared     NUMERIC(14,2),-- from tax records if obtained
    income_gap          NUMERIC(14,2),-- unexplained wealth amount
    total_suspicious_amt NUMERIC(14,2),-- total flagged transaction amount

    -- SAR filing fields (populated only when disposition_type = sar_filed)
    sar_reference       VARCHAR(50),  -- FinCEN SAR reference number
    sar_filed_date      DATE,
    sar_amount          NUMERIC(14,2),-- amount reported in SAR
    sar_narrative_summary TEXT,       -- brief summary of SAR narrative

    -- Monitoring fields (populated when disposition_type = monitoring)
    monitoring_end_date DATE,
    monitoring_trigger  TEXT,         -- what event would trigger escalation
    monitoring_frequency VARCHAR(50), -- monthly, quarterly

    -- Law enforcement referral fields
    le_agency           VARCHAR(100),
    le_referral_date    DATE,
    le_case_number      VARCHAR(50),

    rationale           TEXT          NOT NULL, -- required for all dispositions
    created_at          TIMESTAMPTZ   DEFAULT NOW()
);

COMMENT ON TABLE dispositions IS
'Final disposition of each case. Every case must have exactly one disposition
record. SAR filings require supervisor approval and populate the sar_* fields.
Income gap is calculated from the financial profile comparison and is the
primary quantitative support for SAR filings.';

CREATE INDEX idx_dispositions_type ON dispositions (disposition_type);
CREATE INDEX idx_dispositions_date ON dispositions (disposition_date);


-- ============================================================
-- SECTION 6: AUDIT LOG TABLE
-- ============================================================
-- Every action taken in the system is logged here.
-- Who did what, to which record, and when.
--
-- This is an examiner requirement. BSA program documentation
-- must demonstrate that the compliance function is operating
-- as designed and that actions are being taken by authorized
-- personnel. The audit log is the proof.
-- ============================================================

CREATE TABLE audit_log (
    log_id            SERIAL PRIMARY KEY,
    log_timestamp     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    analyst           VARCHAR(100)  NOT NULL,
    action_type       VARCHAR(50)   NOT NULL,
                                    -- alert_opened, alert_assigned,
                                    -- case_opened, note_added,
                                    -- status_changed, disposition_set,
                                    -- parameter_changed, sar_filed
    table_affected    VARCHAR(50)   NOT NULL,
    record_id         INT           NOT NULL,
    old_value         TEXT,         -- previous state if updating
    new_value         TEXT,         -- new state
    notes             TEXT          -- free text explanation of action
);

COMMENT ON TABLE audit_log IS
'Immutable audit trail of all system actions. Supports BSA examination
requirements for program documentation. Records should never be deleted
or modified. Retention period: seven years per BSA record retention rules
under 31 CFR § 1010.430.';

CREATE INDEX idx_audit_timestamp ON audit_log (log_timestamp);
CREATE INDEX idx_audit_analyst   ON audit_log (analyst);
CREATE INDEX idx_audit_action    ON audit_log (action_type);


-- ============================================================
-- SECTION 7: SAMPLE LIFECYCLE DATA
-- ============================================================
-- Populates the lifecycle tables with realistic case data
-- based on the detection engine output.
--
-- Two complete case lifecycles:
--   CASE-2025-001  Tom McAllister   — HIGH ALERT → SAR filed
--   CASE-2025-002  Bénédicte Noël  — FLAG → monitoring
--
-- Plus one alert that was cleared without a case.
-- ============================================================

-- ── Alerts ───────────────────────────────────────────────────

INSERT INTO alerts (
    account_id, alert_date, alert_month, detection_rule,
    alert_tier, risk_score, velocity_z_score, peer_z_score,
    current_month_amt, prior_12mo_avg, flags_triggered,
    status, assigned_to, assigned_date
) VALUES
(
    1,
    CURRENT_DATE,
    DATE_TRUNC('month', CURRENT_DATE),
    'combined_detection',
    'HIGH ALERT',
    6,
    8.42,
    3.21,
    39450.00,
    2987.00,
    'VELOCITY HIGH ALERT | ABOVE PEER GROUP | STRUCTURING PATTERN',
    'under_review',
    'P. Adkins-Smith',
    CURRENT_DATE - 2
),
(
    2,
    CURRENT_DATE,
    DATE_TRUNC('month', CURRENT_DATE),
    'combined_detection',
    'FLAG',
    3,
    0.31,
    2.87,
    9340.00,
    9180.00,
    'ABOVE PEER GROUP | STRUCTURING PATTERN',
    'under_review',
    'P. Adkins-Smith',
    CURRENT_DATE - 2
),
(
    5,
    CURRENT_DATE - 35,
    DATE_TRUNC('month', CURRENT_DATE - 35),
    'velocity_zscore',
    'WATCH',
    1,
    1.62,
    1.12,
    13200.00,
    11340.00,
    'WATCH: 1.5 std deviations above 12-month average',
    'closed',
    'P. Adkins-Smith',
    CURRENT_DATE - 34
);


-- ── Cases ────────────────────────────────────────────────────

INSERT INTO cases (
    alert_id, case_reference, subject_id,
    opened_date, due_date, assigned_analyst, supervisor,
    status, priority, hypothesis, typology, typology_reference,
    pep_involved, geographic_risk
) VALUES
(
    1,
    'CASE-2025-001',
    1,
    CURRENT_DATE - 2,
    CURRENT_DATE + 28,
    'P. Adkins-Smith',
    'J. Williams',
    'pending_sar',
    'high',
    'Subject may be using a legitimate retail business as a front to deposit cash from an undisclosed source. Current month deposits of $39,450 represent a 1,220% increase over the 12-month average of $2,987. Four deposits were clustered between $9,500 and $9,900, consistent with deliberate structuring to avoid CTR reporting.',
    'Cash-Intensive Business Front / Structuring',
    'FATF Report: Money Laundering Through the Physical Transportation of Cash (October 2015). FATF Typologies on Trade-Based Money Laundering (2006).',
    FALSE,
    'low'
),
(
    2,
    'CASE-2025-002',
    2,
    CURRENT_DATE - 2,
    CURRENT_DATE + 28,
    'P. Adkins-Smith',
    'J. Williams',
    'open',
    'standard',
    'Subject deposits consistently near but below the CTR threshold. Pattern has persisted across multiple months suggesting awareness of reporting requirements. Business type does not typically generate this volume relative to peer accounts.',
    'Structuring',
    'BSA 31 U.S.C. § 5324. FATF Typology: Structuring / Smurfing.',
    FALSE,
    'low'
);


-- ── Case Notes ───────────────────────────────────────────────

INSERT INTO case_notes (
    case_id, note_date, analyst, note_type,
    note_text, source_consulted, source_reliability,
    findings, new_leads, hypothesis_change
) VALUES
(
    1,
    NOW() - '2 days'::interval,
    'P. Adkins-Smith',
    'initial_review',
    'Alert reviewed. Subject Tom McAllister holds business account ACC-TM-001 at Citibank under company name Forest Flowers. Current month shows four cash deposits totaling $39,450, ranging from $9,500 to $9,900. Prior 12-month average is $2,987 per month. Velocity z-score of 8.42 is significantly above the 3.0 high alert threshold. Peer group z-score of 3.21 indicates deposits are well above comparable retail accounts. Case opened for full investigation.',
    'Internal alert dashboard — detection engine output',
    'high',
    'Four current-month deposits all within structuring zone ($8,000-$9,999). Z-score of 8.42 indicates highly anomalous velocity. Peer group z-score of 3.21 confirms anomaly is not explained by business type.',
    'Company name Forest Flowers identified for company registry check. Alias Tomas MacAllister noted in subject record.',
    'Initial hypothesis: subject is using a retail business front to deposit cash from an undisclosed source. Structuring pattern suggests awareness of CTR threshold.'
),
(
    1,
    NOW() - '1 day'::interval,
    'P. Adkins-Smith',
    'fiu_search',
    'FIU database searched for Tom McAllister, Tomas MacAllister, and account number ACC-TM-001. No prior STRs found under the exact name. However, two prior reports found linked to the identification number on file: STR-2017-45176 (series of smaller cash deposits totaling $2,530) and STR-2018-19176 (large cash deposit of $17,500 under account linked to Indigo Carpets). Additional account identified: HSBC account number 8746489 linked to company Indigo Carpets. International transaction identified: prior wire to Tulips United B.V., Netherlands, account ABN AMRO 43889478.',
    'FIU internal database',
    'high',
    'Subject has prior STR history. Two prior reports identified. Second company Indigo Carpets identified with separate HSBC account. International wire to Netherlands-based entity identified.',
    'Indigo Carpets — second company requiring registry check. Tulips United B.V. Netherlands — international entity requiring FIU NL contact. HSBC account 8746489 — separate account requiring bank records request.',
    'Hypothesis updated: subject operates multiple business entities and has prior suspicious activity history. The current activity is not isolated. The Netherlands connection raises geographic risk. Hypothesis now includes possible layering through multiple domestic entities with an international component.'
),
(
    1,
    NOW() - '12 hours'::interval,
    'P. Adkins-Smith',
    'domestic_closed',
    'Company registry checked for Forest Flowers and Indigo Carpets. Forest Flowers: company number 3700459, incorporated 22 February 2017, subject is sole shareholder and director (100% ownership). Indigo Carpets: company number 295647, incorporated 11 November 1999, subject holds 50% and is director. Second director identified: Jamie E. Quevedo, address Nezahualcoyotl 109 Piso 8, 77520 Cancun, Q. Roo, Mexico. Both companies share the same registered address. Tax authority records received: declared annual income 2021 $51,000, 2022 $55,000, 2023 $54,000. All income attributed to Forest Flowers. Registration office confirmed subject owns property at 14 Ocean Drive valued at approximately $1,200,000 acquired February 2015. Vehicle registry: 2018 Land Rover Range Rover, estimated original price $110,000.',
    'Company registry, tax authority, registration office, vehicle registry',
    'high',
    'Declared annual income approximately $54,000. Property value $1,200,000. Vehicle value $110,000. Current month suspicious deposits alone total $39,450. Income gap is significant. Second director Jamie E. Quevedo is Mexico-based, elevating geographic risk.',
    'Jamie E. Quevedo — new subject for FIU search and international source check. Mexico address — FATF assessment of Mexico to be reviewed.',
    'Income gap confirmed. $54,000 declared income cannot support $1.2M property, $110K vehicle, and current deposit pattern. Hypothesis strengthened: funds are likely from an undisclosed illegal source. Geographic risk elevated to medium due to Mexico-based co-director.'
),
(
    2,
    NOW() - '1 day'::interval,
    'P. Adkins-Smith',
    'initial_review',
    'Alert reviewed. Subject Bénédicte Noël holds business account ACC-BN-002 at BNP under company TOTAL Store Marseille. Monthly deposits consistently range between $9,100 and $9,800 across all 13 months of available history. Own-history z-score is low (0.31) because the pattern is consistent. However, peer group z-score of 2.87 indicates deposits are significantly above comparable business_retail accounts. STR filed by BNP Paris branch. Subject home address is Marseille, approximately 800km from reporting branch.',
    'Internal alert dashboard, STR review',
    'high',
    'Structuring pattern consistent across all 13 months, not just current month. Geographic discrepancy: STR filed in Paris, subject lives in Marseille. Peer group anomaly confirmed.',
    'BNP Paris branch — why was account opened at a branch 800km from subject address? Requires clarification from reporting institution.',
    'Structuring pattern appears deliberate and long-running, not a one-time anomaly. Consistent below-threshold deposits suggest ongoing awareness of CTR requirements. Hypothesis: subject has been structuring for at minimum 13 months.'
);


-- ── Dispositions ─────────────────────────────────────────────

-- CASE-2025-001: SAR filed (McAllister)
INSERT INTO dispositions (
    case_id, disposition_date, disposition_type,
    disposition_analyst, supervisor_approval, approval_date,
    final_hypothesis, typology_confirmed, evidence_summary,
    income_declared, income_gap, total_suspicious_amt,
    sar_reference, sar_filed_date, sar_amount,
    sar_narrative_summary, rationale
) VALUES
(
    1,
    CURRENT_DATE + 14,
    'sar_filed',
    'P. Adkins-Smith',
    'J. Williams',
    CURRENT_DATE + 13,
    'Tom McAllister, operating through Forest Flowers and Indigo Carpets, deposited $39,450 in four structuring-pattern cash deposits during the review period. Investigation revealed declared annual income of $54,000, inconsistent with ownership of a $1.2M property, $110K vehicle, and the deposit volume identified. FIU records show two prior STRs and an undisclosed international wire to a Netherlands entity. The income gap and structuring pattern, combined with prior suspicious activity history, support a SAR filing under the cash-intensive business front and structuring typologies.',
    'Cash-Intensive Business Front / Structuring',
    '1. Velocity z-score 8.42 — current month $39,450 versus 12-month average $2,987. 2. Four deposits between $9,500 and $9,900 in single month — structuring pattern confirmed. 3. Peer group z-score 3.21 — deposits significantly above comparable retail peers. 4. Declared income $54,000 versus $1.2M property and $110K vehicle — income gap $1,256,000 in assets above declared earning capacity. 5. Two prior STRs linked to identification number. 6. International wire to Netherlands entity — international layering component identified.',
    54000.00,
    1256000.00,
    39450.00,
    'SAR-2025-00471',
    CURRENT_DATE + 14,
    39450.00,
    'Subject Tom McAllister, owner of Forest Flowers and co-director of Indigo Carpets, made four cash deposits totaling $39,450 in a single month, each below the $10,000 CTR threshold. Subject declared annual income of $54,000 but owns property valued at $1.2M and a $110,000 vehicle. FIU records reveal prior suspicious activity and an undisclosed wire to a Netherlands entity.',
    'SAR filed based on: (1) confirmed structuring pattern across four deposits, (2) significant income gap between declared income and known assets, (3) prior STR history on the same identification number, (4) international component requiring further investigation. Threshold for filing met under 31 CFR § 1020.320 — activity aggregates above $5,000 and there is a basis to suspect funds derive from illegal activity.'
);

-- Alert for cleared case (Linda Park - prior month, cleared without case)
INSERT INTO dispositions (
    case_id, disposition_date, disposition_type,
    disposition_analyst, final_hypothesis,
    evidence_summary, rationale
)
SELECT
    NULL,
    CURRENT_DATE - 30,
    'cleared',
    'P. Adkins-Smith',
    'Elevated deposits explained by seasonal restaurant volume (holiday period). No case opened.',
    'Watch-tier alert only. Deposit increase of 16% is within normal seasonal variation for restaurant accounts. Peer group z-score of 1.12 is below the flag threshold.',
    'Alert cleared without case. Deposit increase attributable to seasonal business volume. No indicators of suspicious activity identified. Alert documented and closed per policy.'
WHERE EXISTS (SELECT 1 FROM alerts WHERE account_id = 5);


-- ── Audit Log ────────────────────────────────────────────────

INSERT INTO audit_log
    (analyst, action_type, table_affected, record_id,
     old_value, new_value, notes)
VALUES
(
    'P. Adkins-Smith',
    'alert_assigned',
    'alerts',
    1,
    'status: open, assigned_to: NULL',
    'status: under_review, assigned_to: P. Adkins-Smith',
    'Alert assigned to analyst following HIGH ALERT tier classification'
),
(
    'P. Adkins-Smith',
    'case_opened',
    'cases',
    1,
    NULL,
    'case_reference: CASE-2025-001, status: open',
    'Case opened from alert_id 1. McAllister HIGH ALERT.'
),
(
    'P. Adkins-Smith',
    'note_added',
    'case_notes',
    1,
    NULL,
    'note_type: initial_review',
    'Initial review note documented.'
),
(
    'P. Adkins-Smith',
    'note_added',
    'case_notes',
    2,
    NULL,
    'note_type: fiu_search',
    'FIU database search completed. Prior STRs identified.'
),
(
    'P. Adkins-Smith',
    'status_changed',
    'cases',
    1,
    'status: open',
    'status: pending_sar',
    'Case moved to pending_sar following domestic closed source review confirming income gap.'
),
(
    'P. Adkins-Smith',
    'note_added',
    'case_notes',
    3,
    NULL,
    'note_type: domestic_closed',
    'Company registry, tax, real estate, and vehicle registry results documented.'
),
(
    'J. Williams',
    'disposition_set',
    'dispositions',
    1,
    NULL,
    'disposition_type: sar_filed, sar_reference: SAR-2025-00471',
    'SAR filing approved by supervisor. Filed with FinCEN.'
),
(
    'P. Adkins-Smith',
    'alert_assigned',
    'alerts',
    2,
    'status: open, assigned_to: NULL',
    'status: under_review, assigned_to: P. Adkins-Smith',
    'Alert assigned. FLAG tier — Noël structuring pattern.'
),
(
    'P. Adkins-Smith',
    'case_opened',
    'cases',
    2,
    NULL,
    'case_reference: CASE-2025-002, status: open',
    'Case opened from alert_id 2.'
),
(
    'P. Adkins-Smith',
    'alert_assigned',
    'alerts',
    3,
    'status: open, assigned_to: NULL',
    'status: closed, assigned_to: P. Adkins-Smith',
    'Watch alert reviewed and cleared. Seasonal variation explanation accepted.'
);


-- ============================================================
-- SECTION 8: OPERATIONAL QUERIES
-- ============================================================


-- ── QUERY 1: ANALYST ALERT QUEUE ─────────────────────────────
-- What an analyst opens every morning.
-- Shows all open and under_review alerts sorted by risk and age.
-- SLA countdown tells the analyst how many days remain before
-- the alert becomes overdue.

\echo ''
\echo '── QUERY 1: Alert Queue ──────────────────────────────────'
\echo 'What an analyst sees when they open their queue each morning'

SELECT
    a.alert_id,
    s.full_name                                          AS subject,
    a.alert_tier,
    a.risk_score,
    a.flags_triggered,
    ROUND(a.current_month_amt, 2)                        AS flagged_amount,
    ROUND(a.velocity_z_score, 2)                         AS vel_z,
    ROUND(a.peer_z_score, 2)                             AS peer_z,
    a.alert_date,
    CURRENT_DATE - a.alert_date                          AS days_open,
    -- SLA countdown: how many days before this alert is overdue
    (SELECT threshold_value::int
     FROM alert_parameters
     WHERE rule_name = 'alert_sla_days')
    - (CURRENT_DATE - a.alert_date)                      AS sla_days_remaining,
    a.status,
    COALESCE(a.assigned_to, 'UNASSIGNED')                AS assigned_to,
    CASE
        WHEN (CURRENT_DATE - a.alert_date) >
             (SELECT threshold_value::int FROM alert_parameters
              WHERE rule_name = 'alert_sla_days')
        THEN 'OVERDUE'
        WHEN (CURRENT_DATE - a.alert_date) >=
             (SELECT threshold_value::int FROM alert_parameters
              WHERE rule_name = 'alert_sla_days') - 1
        THEN 'DUE TODAY'
        WHEN (CURRENT_DATE - a.alert_date) >=
             (SELECT threshold_value::int FROM alert_parameters
              WHERE rule_name = 'alert_sla_days') - 2
        THEN 'DUE TOMORROW'
        ELSE 'ON TRACK'
    END                                                  AS sla_status
FROM alerts a
JOIN bank_accounts ba ON a.account_id = ba.account_id
JOIN subjects s       ON ba.subject_id = s.subject_id
WHERE a.status IN ('open', 'under_review')
ORDER BY
    CASE a.alert_tier
        WHEN 'HIGH ALERT' THEN 1
        WHEN 'FLAG'       THEN 2
        WHEN 'WATCH'      THEN 3
        ELSE 4
    END,
    a.risk_score DESC,
    a.alert_date ASC;


-- ── QUERY 2: SLA AGING REPORT ────────────────────────────────
-- Shows all alerts and cases approaching or past their SLA.
-- This is what a supervisor reviews to prevent aged inventory.
-- Examiner test: are alerts being worked within the required
-- timeframe? This query answers that question directly.

\echo ''
\echo '── QUERY 2: SLA Aging Report ─────────────────────────────'
\echo 'Alerts and cases approaching or past their SLA deadline'

WITH alert_aging AS (
    SELECT
        'ALERT'                                          AS record_type,
        a.alert_id                                       AS record_id,
        s.full_name                                      AS subject,
        a.alert_tier                                     AS priority,
        a.alert_date                                     AS opened_date,
        a.alert_date + (
            SELECT threshold_value::int
            FROM alert_parameters
            WHERE rule_name = 'alert_sla_days'
        )                                                AS due_date,
        CURRENT_DATE - a.alert_date                      AS age_days,
        a.status,
        COALESCE(a.assigned_to, 'UNASSIGNED')            AS responsible
    FROM alerts a
    JOIN bank_accounts ba ON a.account_id = ba.account_id
    JOIN subjects s       ON ba.subject_id = s.subject_id
    WHERE a.status IN ('open', 'under_review')
),
case_aging AS (
    SELECT
        'CASE'                                           AS record_type,
        c.case_id                                        AS record_id,
        s.full_name                                      AS subject,
        c.priority,
        c.opened_date,
        c.due_date,
        CURRENT_DATE - c.opened_date                     AS age_days,
        c.status,
        c.assigned_analyst                               AS responsible
    FROM cases c
    JOIN subjects s ON c.subject_id = s.subject_id
    WHERE c.status NOT IN ('closed')
)
SELECT
    record_type,
    record_id,
    subject,
    priority,
    opened_date,
    due_date,
    age_days,
    status,
    responsible,
    CASE
        WHEN CURRENT_DATE > due_date        THEN 'OVERDUE'
        WHEN CURRENT_DATE = due_date        THEN 'DUE TODAY'
        WHEN due_date - CURRENT_DATE <= 3   THEN 'DUE IN 3 DAYS'
        WHEN due_date - CURRENT_DATE <= 7   THEN 'DUE THIS WEEK'
        ELSE 'ON TRACK'
    END                                                  AS sla_status
FROM (
    SELECT * FROM alert_aging
    UNION ALL
    SELECT * FROM case_aging
) combined
ORDER BY due_date ASC, age_days DESC;


-- ── QUERY 3: CASE STATUS DASHBOARD ───────────────────────────
-- Supervisor view. Full picture of every open case with
-- investigation stage, key findings, and next action.

\echo ''
\echo '── QUERY 3: Case Status Dashboard ───────────────────────'
\echo 'Supervisor view — all open cases with investigation stage'

SELECT
    c.case_reference,
    s.full_name                                          AS subject,
    c.status,
    c.priority,
    c.assigned_analyst,
    c.opened_date,
    c.due_date,
    CURRENT_DATE - c.opened_date                         AS days_open,
    c.due_date - CURRENT_DATE                            AS days_remaining,
    c.typology,
    c.pep_involved,
    c.geographic_risk,
    -- Most recent note summary
    (SELECT note_type
     FROM case_notes cn
     WHERE cn.case_id = c.case_id
     ORDER BY note_date DESC
     LIMIT 1)                                            AS last_action_type,
    (SELECT TO_CHAR(note_date, 'Mon DD YYYY')
     FROM case_notes cn
     WHERE cn.case_id = c.case_id
     ORDER BY note_date DESC
     LIMIT 1)                                            AS last_action_date,
    -- Note count shows investigation depth
    (SELECT COUNT(*)
     FROM case_notes cn
     WHERE cn.case_id = c.case_id)                      AS total_notes,
    -- Disposition status
    CASE
        WHEN d.disposition_id IS NOT NULL
        THEN d.disposition_type
        ELSE 'pending'
    END                                                  AS disposition_status
FROM cases c
JOIN subjects s ON c.subject_id = s.subject_id
LEFT JOIN dispositions d ON c.case_id = d.case_id
ORDER BY
    CASE c.priority
        WHEN 'critical'  THEN 1
        WHEN 'high'      THEN 2
        WHEN 'standard'  THEN 3
        ELSE 4
    END,
    c.due_date ASC;


-- ── QUERY 4: DISPOSITION SUMMARY ─────────────────────────────
-- Management reporting view.
-- Shows all closed cases with outcomes, SAR amounts,
-- and analyst performance metrics.
-- This is what a BSA officer reviews monthly.

\echo ''
\echo '── QUERY 4: Disposition Summary ─────────────────────────'
\echo 'Management view — case outcomes and SAR activity'

SELECT
    c.case_reference,
    s.full_name                                          AS subject,
    c.assigned_analyst,
    c.opened_date,
    d.disposition_date,
    d.disposition_date - c.opened_date                   AS days_to_close,
    d.disposition_type,
    d.typology_confirmed,
    ROUND(d.total_suspicious_amt, 2)                     AS suspicious_amount,
    ROUND(d.income_gap, 2)                               AS income_gap,
    d.sar_reference,
    d.sar_filed_date,
    ROUND(d.sar_amount, 2)                               AS sar_amount,
    d.supervisor_approval,
    CASE
        WHEN d.disposition_type = 'sar_filed'
        THEN 'SAR filed with FinCEN'
        WHEN d.disposition_type = 'cleared'
        THEN 'Cleared — no suspicious activity'
        WHEN d.disposition_type = 'monitoring'
        THEN 'Account under monitoring'
        WHEN d.disposition_type = 'referred_le'
        THEN 'Referred to law enforcement'
        ELSE d.disposition_type
    END                                                  AS outcome_description
FROM dispositions d
JOIN cases c       ON d.case_id = c.case_id
JOIN subjects s    ON c.subject_id = s.subject_id
ORDER BY d.disposition_date DESC;


-- ── QUERY 5: ANALYST WORKLOAD ────────────────────────────────
-- How many open alerts and cases does each analyst hold?
-- Used for workload balancing and capacity planning.

\echo ''
\echo '── QUERY 5: Analyst Workload ─────────────────────────────'
\echo 'Open alerts and cases per analyst for workload management'

SELECT
    assigned_analyst                                     AS analyst,
    COUNT(DISTINCT c.case_id)                            AS open_cases,
    COUNT(DISTINCT CASE
        WHEN c.priority = 'high'     THEN c.case_id
        WHEN c.priority = 'critical' THEN c.case_id
    END)                                                 AS high_priority_cases,
    COUNT(DISTINCT a.alert_id)                           AS open_alerts,
    MIN(c.due_date)                                      AS earliest_case_due,
    ROUND(AVG(CURRENT_DATE - c.opened_date), 0)          AS avg_case_age_days
FROM cases c
LEFT JOIN alerts a
    ON a.assigned_to = c.assigned_analyst
    AND a.status IN ('open', 'under_review')
WHERE c.status NOT IN ('closed')
GROUP BY assigned_analyst
ORDER BY open_cases DESC;


-- ── QUERY 6: SAR FILING LOG ──────────────────────────────────
-- All SAR filings with supporting data.
-- Required for BSA program reporting and examination.

\echo ''
\echo '── QUERY 6: SAR Filing Log ───────────────────────────────'
\echo 'All SAR filings — required for BSA program reporting'

SELECT
    d.sar_reference,
    d.sar_filed_date,
    c.case_reference,
    s.full_name                                          AS subject,
    ROUND(d.sar_amount, 2)                               AS sar_amount,
    d.typology_confirmed,
    ROUND(d.income_gap, 2)                               AS income_gap_documented,
    d.disposition_analyst                                AS filed_by,
    d.supervisor_approval                                AS approved_by,
    d.approval_date,
    LEFT(d.sar_narrative_summary, 200)                   AS narrative_preview
FROM dispositions d
JOIN cases c    ON d.case_id = c.case_id
JOIN subjects s ON c.subject_id = s.subject_id
WHERE d.disposition_type = 'sar_filed'
ORDER BY d.sar_filed_date DESC;


-- ── QUERY 7: FULL CASE TIMELINE ──────────────────────────────
-- Complete chronological history of every action taken
-- on a specific case. Pass the case_reference to filter.
-- This is the investigative record an examiner reviews.

\echo ''
\echo '── QUERY 7: Full Case Timeline — CASE-2025-001 ───────────'
\echo 'Complete audit trail for a single case'

SELECT
    TO_CHAR(al.log_timestamp, 'Mon DD YYYY HH24:MI') AS timestamp,
    al.analyst,
    al.action_type,
    al.table_affected,
    COALESCE(al.new_value, al.notes)                  AS action_detail
FROM audit_log al
WHERE al.record_id IN (
    SELECT alert_id FROM alerts WHERE account_id IN (
        SELECT account_id FROM bank_accounts WHERE subject_id IN (
            SELECT subject_id FROM cases WHERE case_reference = 'CASE-2025-001'
        )
    )
    UNION
    SELECT case_id FROM cases WHERE case_reference = 'CASE-2025-001'
    UNION
    SELECT note_id FROM case_notes WHERE case_id IN (
        SELECT case_id FROM cases WHERE case_reference = 'CASE-2025-001'
    )
)
ORDER BY al.log_timestamp ASC;


\echo ''
\echo '════════════════════════════════════════════════════════'
\echo 'Case lifecycle layer complete.'
\echo ''
\echo 'Tables created: alert_parameters, alerts, cases,'
\echo '                case_notes, dispositions, audit_log'
\echo ''
\echo 'Queries run:'
\echo '  1. Alert queue — open alerts sorted by risk and age'
\echo '  2. SLA aging   — alerts and cases approaching deadline'
\echo '  3. Case dashboard — supervisor view of all open work'
\echo '  4. Disposition summary — management reporting'
\echo '  5. Analyst workload — caseload per analyst'
\echo '  6. SAR filing log — all SAR filings with evidence'
\echo '  7. Case timeline — full audit trail for CASE-2025-001'
\echo '════════════════════════════════════════════════════════'
