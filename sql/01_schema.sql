-- ============================================================
-- AML Transaction Monitoring System
-- File: 01_schema.sql
-- Purpose: Creates all tables needed by the system.
--          Run this first before any other file.
-- ============================================================


-- Clean up if re-running
DROP TABLE IF EXISTS audit_log          CASCADE;
DROP TABLE IF EXISTS dispositions       CASCADE;
DROP TABLE IF EXISTS case_notes         CASCADE;
DROP TABLE IF EXISTS cases              CASCADE;
DROP TABLE IF EXISTS alerts             CASCADE;
DROP TABLE IF EXISTS alert_parameters   CASCADE;
DROP TABLE IF EXISTS transactions       CASCADE;
DROP TABLE IF EXISTS bank_accounts      CASCADE;
DROP TABLE IF EXISTS subjects           CASCADE;


-- ── alert_parameters ─────────────────────────────────────────
-- Stores every detection threshold in one place.
-- When a compliance officer wants to change a threshold they
-- update this table. They do not need to touch any SQL query.
-- The detection engine reads from this table at run time.
--
-- Why this matters: in a real bank, thresholds are reviewed
-- and adjusted regularly. Hardcoding numbers into queries
-- means a compliance officer cannot tune the system without
-- a developer. This table removes that dependency.

CREATE TABLE alert_parameters (
    param_id         SERIAL       PRIMARY KEY,
    rule_name        VARCHAR(100) NOT NULL UNIQUE,
    description      TEXT,
    threshold_value  NUMERIC      NOT NULL,
    threshold_unit   VARCHAR(50),
    -- regulatory_basis: the specific law or guidance
    -- that requires or supports this detection rule.
    -- Every threshold must have a regulatory basis.
    regulatory_basis TEXT,
    effective_date   DATE         NOT NULL DEFAULT CURRENT_DATE,
    last_reviewed    DATE,
    reviewed_by      VARCHAR(100),
    is_active        BOOLEAN      DEFAULT TRUE,
    notes            TEXT
);

COMMENT ON TABLE alert_parameters IS
'Detection thresholds managed by compliance officers.
The detection engine reads from this table so thresholds
can be changed without modifying SQL.
All changes should be logged in audit_log.
Review frequency: quarterly per BSA program requirements.';


-- ── subjects ─────────────────────────────────────────────────
-- One row per person or business being monitored.
-- account_type groups accounts for peer comparison.
-- A flower shop is compared to other flower shops,
-- not to restaurants.

CREATE TABLE subjects (
    subject_id    SERIAL       PRIMARY KEY,
    full_name     VARCHAR(100) NOT NULL,
    alias         VARCHAR(100),
    date_of_birth DATE,
    nationality   VARCHAR(50),
    occupation    VARCHAR(100),
    address       TEXT,
    id_number     VARCHAR(50),
    -- pep_status: Politically Exposed Person.
    -- A PEP is someone who holds or held a government position.
    -- PEPs get extra scrutiny because their position gave them
    -- access to public funds.
    pep_status    BOOLEAN      DEFAULT FALSE,
    -- risk_rating: overall risk level assigned to this subject.
    -- high risk subjects have lower alert thresholds.
    risk_rating   VARCHAR(20)  DEFAULT 'standard',
    account_type  VARCHAR(50),
    created_at    TIMESTAMPTZ  DEFAULT NOW()
);

COMMENT ON COLUMN subjects.account_type IS
'Business category used for peer group comparison.
Examples: business_retail, business_restaurant, personal.
Accounts are only compared to others in the same category.';


-- ── bank_accounts ────────────────────────────────────────────
-- One row per bank account.
-- One subject can have multiple accounts at multiple banks.
-- Each account is analyzed separately.

CREATE TABLE bank_accounts (
    account_id     SERIAL       PRIMARY KEY,
    subject_id     INT          REFERENCES subjects(subject_id),
    bank_name      VARCHAR(100) NOT NULL,
    account_number VARCHAR(50)  NOT NULL,
    account_type   VARCHAR(50),
    currency       VARCHAR(10)  DEFAULT 'USD',
    opened_date    DATE,
    status         VARCHAR(20)  DEFAULT 'active',
    created_at     TIMESTAMPTZ  DEFAULT NOW()
);


-- ── transactions ─────────────────────────────────────────────
-- One row per transaction.
-- All detection logic runs against this table.
--
-- branch: which physical branch the transaction happened at.
-- Multiple branches used by the same account in a short period
-- is a structuring indicator.
--
-- counterparty_country: where the other party in a wire
-- transfer is located. Used for geographic risk detection.
-- High-risk countries are flagged using FATF lists.

CREATE TABLE transactions (
    txn_id               SERIAL        PRIMARY KEY,
    account_id           INT           REFERENCES bank_accounts(account_id),
    txn_date             DATE          NOT NULL,
    txn_time             TIME,
    amount               NUMERIC(14,2) NOT NULL,
    -- txn_type values: cash_deposit, cash_withdrawal,
    -- wire_in, wire_out, check_deposit
    txn_type             VARCHAR(50),
    branch               VARCHAR(100),
    counterparty         VARCHAR(100),
    counterparty_account VARCHAR(50),
    counterparty_bank    VARCHAR(100),
    counterparty_country VARCHAR(50),
    str_flag             BOOLEAN       DEFAULT FALSE,
    notes                TEXT,
    created_at           TIMESTAMPTZ   DEFAULT NOW()
);

COMMENT ON COLUMN transactions.branch IS
'Branch where the transaction took place.
Deposits split across multiple branches to stay
below reporting thresholds is a structuring indicator.
See: BSA 31 U.S.C. 5324.';

COMMENT ON COLUMN transactions.counterparty_country IS
'Country of the counterparty in wire transactions.
Used to flag transactions connected to countries on
the FATF high-risk list or under OFAC sanctions.';

COMMENT ON COLUMN transactions.txn_time IS
'Time of transaction. Transactions outside normal
business hours are a secondary alert indicator.
Required field in most enterprise AML systems.';


-- ── alerts ───────────────────────────────────────────────────
-- Saves every alert the detection engine produces.
-- Without this table alerts only exist in query output
-- and cannot be tracked, aged, or reported on.

CREATE TABLE alerts (
    alert_id          SERIAL       PRIMARY KEY,
    account_id        INT          REFERENCES bank_accounts(account_id),
    alert_date        DATE         NOT NULL DEFAULT CURRENT_DATE,
    alert_month       DATE         NOT NULL,
    detection_rule    VARCHAR(100) NOT NULL,
    alert_tier        VARCHAR(20)  NOT NULL,
    risk_score        INT          NOT NULL DEFAULT 0,
    velocity_z_score  NUMERIC(8,2),
    peer_z_score      NUMERIC(8,2),
    current_month_amt NUMERIC(14,2),
    prior_12mo_avg    NUMERIC(14,2),
    flags_triggered   TEXT,
    status            VARCHAR(30)  NOT NULL DEFAULT 'open',
    assigned_to       VARCHAR(100),
    assigned_date     DATE,
    created_at        TIMESTAMPTZ  DEFAULT NOW(),
    updated_at        TIMESTAMPTZ  DEFAULT NOW()
);

COMMENT ON COLUMN alerts.alert_month IS
'The month the alert covers.
Different from alert_date which is when the alert was created.
An alert created on the 3rd of the month may cover
activity from the prior month.';


-- ── cases ────────────────────────────────────────────────────
-- One investigation per alert that moves past initial review.
-- Not every alert becomes a case. An analyst can clear an
-- alert without a case if the activity is clearly explained.

CREATE TABLE cases (
    case_id          SERIAL       PRIMARY KEY,
    alert_id         INT          REFERENCES alerts(alert_id),
    case_reference   VARCHAR(50)  NOT NULL UNIQUE,
    subject_id       INT          REFERENCES subjects(subject_id),
    opened_date      DATE         NOT NULL DEFAULT CURRENT_DATE,
    due_date         DATE,
    assigned_analyst VARCHAR(100) NOT NULL,
    supervisor       VARCHAR(100),
    status           VARCHAR(30)  NOT NULL DEFAULT 'open',
    priority         VARCHAR(20)  DEFAULT 'standard',
    hypothesis       TEXT,
    typology         VARCHAR(100),
    typology_reference TEXT,
    pep_involved     BOOLEAN      DEFAULT FALSE,
    sanctions_hit    BOOLEAN      DEFAULT FALSE,
    geographic_risk  VARCHAR(20)  DEFAULT 'low',
    closed_date      DATE,
    closed_by        VARCHAR(100),
    created_at       TIMESTAMPTZ  DEFAULT NOW(),
    updated_at       TIMESTAMPTZ  DEFAULT NOW()
);


-- ── case_notes ───────────────────────────────────────────────
-- Analyst notes written during the investigation.
-- Every action taken, every source checked, and every
-- finding is recorded here.
-- This is the written record that supports the final decision.

CREATE TABLE case_notes (
    note_id           SERIAL       PRIMARY KEY,
    case_id           INT          REFERENCES cases(case_id),
    note_date         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    analyst           VARCHAR(100) NOT NULL,
    note_type         VARCHAR(50)  NOT NULL,
    note_text         TEXT         NOT NULL,
    source_consulted  VARCHAR(200),
    source_reliability VARCHAR(20),
    findings          TEXT,
    new_leads         TEXT,
    hypothesis_change TEXT
);


-- ── dispositions ─────────────────────────────────────────────
-- The final decision on each case.
-- Every case ends in one of these outcomes:
-- cleared, sar_filed, referred_le, monitoring, closed_no_action

CREATE TABLE dispositions (
    disposition_id       SERIAL       PRIMARY KEY,
    case_id              INT          REFERENCES cases(case_id) UNIQUE,
    disposition_date     DATE         NOT NULL DEFAULT CURRENT_DATE,
    disposition_type     VARCHAR(50)  NOT NULL,
    disposition_analyst  VARCHAR(100) NOT NULL,
    supervisor_approval  VARCHAR(100),
    approval_date        DATE,
    final_hypothesis     TEXT,
    typology_confirmed   VARCHAR(100),
    evidence_summary     TEXT,
    income_declared      NUMERIC(14,2),
    income_gap           NUMERIC(14,2),
    total_suspicious_amt NUMERIC(14,2),
    sar_reference        VARCHAR(50),
    sar_filed_date       DATE,
    sar_amount           NUMERIC(14,2),
    sar_narrative_summary TEXT,
    monitoring_end_date  DATE,
    monitoring_trigger   TEXT,
    monitoring_frequency VARCHAR(50),
    le_agency            VARCHAR(100),
    le_referral_date     DATE,
    le_case_number       VARCHAR(50),
    rationale            TEXT        NOT NULL,
    created_at           TIMESTAMPTZ DEFAULT NOW()
);


-- ── audit_log ────────────────────────────────────────────────
-- Records every action taken in the system.
-- Who did it, what they did, and when.
-- Required by BSA regulations.
-- Records must be kept for seven years per 31 CFR 1010.430.
-- Nothing in this table should ever be deleted or changed.

CREATE TABLE audit_log (
    log_id         SERIAL       PRIMARY KEY,
    log_timestamp  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    analyst        VARCHAR(100) NOT NULL,
    action_type    VARCHAR(50)  NOT NULL,
    table_affected VARCHAR(50)  NOT NULL,
    record_id      INT          NOT NULL,
    old_value      TEXT,
    new_value      TEXT,
    notes          TEXT
);

COMMENT ON TABLE audit_log IS
'Permanent record of all system actions.
Retention requirement: seven years.
Regulatory basis: 31 CFR 1010.430 BSA record retention rules.
Records must never be deleted or modified.';


-- ── indexes ──────────────────────────────────────────────────
-- Indexes speed up the queries in the detection engine.
-- Without them, calculations over large datasets are slow.

CREATE INDEX idx_txn_account_date   ON transactions (account_id, txn_date);
CREATE INDEX idx_txn_type_date      ON transactions (txn_type, txn_date);
CREATE INDEX idx_txn_amount         ON transactions (amount);
CREATE INDEX idx_txn_branch         ON transactions (branch);
CREATE INDEX idx_txn_country        ON transactions (counterparty_country);
CREATE INDEX idx_acct_subject       ON bank_accounts (subject_id);
CREATE INDEX idx_alerts_status      ON alerts (status);
CREATE INDEX idx_alerts_tier        ON alerts (alert_tier);
CREATE INDEX idx_cases_status       ON cases (status);
CREATE INDEX idx_cases_analyst      ON cases (assigned_analyst);
CREATE INDEX idx_audit_timestamp    ON audit_log (log_timestamp);


\echo 'Schema created.'
\echo 'Next: run sql/02_sample_data.sql'
