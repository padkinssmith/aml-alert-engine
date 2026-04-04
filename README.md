# AML Transaction Monitoring System
### A portfolio project demonstrating applied AML compliance knowledge for investment advisers

---

## What This Is

A working AML transaction monitoring system built for the RIA (Registered Investment Adviser) sector.

It runs on PostgreSQL and detects six suspicious activity patterns across a simulated firm of 500 clients, 25 advisors, and 4,700+ transactions.

This project was built to demonstrate applied knowledge of FinCEN's 2024 AML/CFT rule for investment advisers, which extends Bank Secrecy Act obligations to RIAs for the first time.

---

## Why It Exists

FinCEN's final rule published in August 2024 requires investment advisers to implement AML programs by January 1, 2026. Most small and mid-size RIAs have no monitoring infrastructure in place.

This project models what a practical monitoring system looks like for that environment — from schema design through detection logic to SAR-ready alert output.

---

## What the System Detects

Six detection rules run against the transaction data. Each rule targets a real pattern used in AML typologies for the securities sector.

| Rule | What It Catches | Risk Tier | Alerts Generated |
|------|----------------|-----------|-----------------|
| RAPID_REDEMPTION | Large deposit redeemed via international wire within 60 days of account opening | CRITICAL | 1 |
| HIGH_RISK_WIRE | Outbound wire to OFAC-sanctioned or FATF grey-list country | CRITICAL | 2 |
| STRUCTURING | Three or more deposits between $9,000–$9,999 within a 3-day window | HIGH | 1 |
| DORMANT_REACTIVATION | Account dormant 365+ days reactivated with large wire in and out | HIGH | 1 |
| SOURCE_OF_WEALTH_MISMATCH | Single deposit exceeds 3x client's stated expected annual activity | HIGH | 1 |
| ADVISOR_CONCENTRATION | Advisor has 15%+ of clients with open suspicious activity alerts | HIGH | 12 |

---

## Verified Output

System was run against the full synthetic dataset on April 1, 2026.

```
rule_triggered           | risk_tier | alert_count | avg_score
-------------------------+-----------+-------------+-----------
HIGH_RISK_WIRE           | CRITICAL  |           2 |        90
RAPID_REDEMPTION         | CRITICAL  |           1 |        85
STRUCTURING              | HIGH      |           1 |        80
DORMANT_REACTIVATION     | HIGH      |           1 |        78
SOURCE_OF_WEALTH_MISMATCH| HIGH      |           1 |        75
ADVISOR_CONCENTRATION    | HIGH      |          12 |        70
(6 rows)
```

All 6 rules fired on their intended targets. Two false positives (a documented research grant wire and an SEC-registered fund) were correctly excluded.

---

## Database Design

9 tables covering the full AML program lifecycle.

- `advisors` — 25 advisors across multiple states and AUM tiers
- `clients` — 500 clients with risk tiers, source of wealth, expected activity, PEP flags
- `transactions` — 4,700+ transactions spanning January 2022 through December 2024
- `alerts` — detection rule output with risk scores and SAR documentation fields
- `beneficial_owners` — ownership records for corporate and trust accounts
- `sanctions_screening` — OFAC, UN, EU, and FATF screening results
- `client_velocity` — rolling 30-day, 90-day, and YTD transaction totals
- `fincen_314a_log` — FinCEN Section 314(a) information request tracking
- `audit_log` — full change history across all tables

---

## Synthetic Data

The dataset includes six planted suspicious scenarios and two false positives designed to test each detection rule precisely.

Scenario clients include:
- **Dmitri Volkov** — rapid redemption via Cyprus wire
- **Yusra Al-Rashidi** — outbound wires to Iran
- **James Whitfield** — structuring deposits below CTR threshold
- **Beverly Okonkwo** — $340,000 deposit against $48,000 expected annual activity
- **Chen Wei Holdings LLC** — dormant account reactivated after 18 months
- **Marcus Webb** (advisor) — 18% flagged client concentration rate

---

## File Structure

```
osaic-aml-monitoring/
├── README.md
├── schema/
│   └── 01_schema.sql          — 9 tables, indexes, constraints
├── data/
│   ├── 01_seed_advisors.sql   — 25 advisors
│   ├── 02_seed_clients.sql    — 500 clients
│   ├── 03_seed_scenarios.sql  — planted suspicious patterns
│   └── 04_seed_normal_transactions.sql — 4,604 normal transactions
└── detection/
    └── all_detection_rules.sql — 6 detection rules + verification query
```

---

## How to Run It

**Requirements:** PostgreSQL 14+

```sql
-- 1. Create the database
createdb ria_aml

-- 2. Run files in order
psql -d ria_aml -f schema/01_schema.sql
psql -d ria_aml -f data/01_seed_advisors.sql
psql -d ria_aml -f data/02_seed_clients.sql
psql -d ria_aml -f data/03_seed_scenarios.sql
psql -d ria_aml -f data/04_seed_normal_transactions.sql
psql -d ria_aml -f detection/all_detection_rules.sql
```

---

## Regulatory Context

- FinCEN Final Rule: Anti-Money Laundering/Countering the Financing of Terrorism for Investment Advisers (August 2024)
- Bank Secrecy Act — 31 U.S.C. § 5318
- FATF Guidance on Risk-Based Approach for the Securities Sector
- OFAC SDN List screening requirements

---

## About This Project

Built by Pam Adkins-Smith as a portfolio demonstration of applied AML knowledge in the RIA sector.

LinkedIn: https://www.linkedin.com/in/pamadkinssmith

---

> **Disclaimer:** This is an analytical portfolio project. All firm names, client names, and data are entirely fictional. This is not a production compliance system and does not constitute legal or compliance advice.
