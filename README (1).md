# AML Transaction Monitoring System

Transaction monitoring systems generate alerts. Analysts work those alerts.
Most analysts learn the system before they understand the logic behind it —
which means early decisions rely on the tool rather than on judgment.

This project builds that judgment first. Every detection method here mirrors
what enterprise platforms like Actimize and Oracle FCCM do under the hood,
written in plain SQL so the reasoning is fully visible.

The goal is straightforward: demonstrate that working an alert queue
on day one is informed by understanding what triggered the flag,
not just that one exists.

---

## How This Connects to Actimize and Oracle FCCM

Actimize and Oracle FCCM are the two most widely used enterprise
transaction monitoring platforms in US banking. Here is specifically
how this project maps to what those systems do.

**What enterprise platforms do:**
1. Ingest transaction data from core banking systems
2. Run detection rules against that data on a scheduled basis
3. Score each account against configured thresholds
4. Generate alerts ranked by risk and surface them in an analyst queue
5. Track each alert through investigation to disposition

**What this project builds:**

| Enterprise Platform Component | This Project |
|---|---|
| Transaction data ingestion | transactions table in 01_schema.sql |
| Configurable detection thresholds | alert_parameters table — no hardcoded values |
| Detection rules running against data | 13 detection methods in 03_detection_engine.sql |
| Risk scoring and alert ranking | Combined dashboard in 04_alert_dashboard.sql |
| Alert queue with SLA tracking | Operational queries in 05_case_lifecycle.sql |
| Case investigation and disposition | cases, case_notes, dispositions tables |
| Audit trail | audit_log table — seven year retention |

Understanding this mapping is what lets an analyst walk into an Actimize
environment and know immediately which alert type they are looking at
and why the system fired it.

---

## Scope

**What this system covers:**

- Cash deposit monitoring across all detection methods
- Cash withdrawal detection for rapid movement patterns
- Multi-branch deposit activity
- Peer group comparison by business type
- Geographic risk via counterparty country
- Dormant account activation
- Full alert-to-disposition case lifecycle
- Configurable thresholds managed by compliance officers
- Complete audit trail

**What this system does not cover:**

- Sanctions screening (OFAC SDN list). In a real institution this runs
  as a separate real-time check at the point of transaction, not as a
  batch detection method.
- Currency Transaction Report (CTR) filing. CTRs are filed automatically
  for individual transactions above $10,000. The structuring detection
  in this system catches deliberate avoidance of that threshold.
  CTR filing itself is a separate automated process.
- Wire transfer monitoring beyond the geographic risk detection included here.
  Full wire analysis would require correspondent bank chain data.
- Check deposit monitoring.
- ACH transaction monitoring.

These are documented gaps, not oversights. A complete enterprise system
addresses all of them. This project focuses on the cash monitoring
layer which is where structuring and velocity-based laundering
patterns are most commonly detected.

---

## Detection Methods

Thirteen detection methods covering the most common alert types
an analyst works in a cash monitoring queue.

| # | Method | What It Flags | Regulatory Basis |
|---|---|---|---|
| 1 | Standard Deviation | Accounts too consistent or too variable | BSA 31 U.S.C. 5318(g) |
| 2 | Z-Score Per Transaction | Individual deposits far above account average | 31 CFR 1020.320 |
| 3 | Moving Average Trend | Short-term pattern breaking from long-term baseline | BSA 31 U.S.C. 5318(g) |
| 4 | Peer Group Benchmarking | Accounts far above similar business types | 31 CFR 1010.230 CDD Rule |
| 5 | Main Monthly Flag | Current month vs 12-month baseline | 31 CFR 1020.320 |
| 6 | Structuring — Monthly | Multiple deposits near $10,000 in one month | 31 U.S.C. 5324 |
| 7 | Structuring — Weekly | Same pattern within any 7-day window | 31 U.S.C. 5324 |
| 8 | Multi-Branch Deposits | Same account using different branches | 31 U.S.C. 5324 |
| 9 | Velocity Change | Month-over-month deposit jumps | BSA 31 U.S.C. 5318(g) |
| 10 | Round Number Analysis | Too many exact dollar amounts | FATF Cash Typology Report |
| 11 | Withdrawal After Deposit | Cash in then out within 5 days | BSA 31 U.S.C. 5318(g) |
| 12 | Geographic Risk | Transactions linked to high-risk countries | OFAC / FATF |
| 13 | Dormant Account Activation | Quiet accounts that suddenly become active | BSA 31 U.S.C. 5318(g) |

---

## Why Peer Group Comparison Matters

Most systems flag accounts against their own history. That catches
sudden changes. But it misses accounts that have always been high.

An account depositing $9,000 every month for a year will never
trigger a velocity alert. Its own history looks perfectly consistent.
But if every other flower shop deposits $2,800 per month, that account
is depositing more than three times the peer average — a major anomaly
that own-history analysis completely misses.

This system runs both. Velocity z-scores catch sudden changes.
Peer group z-scores catch sustained anomalies.

---

## Case Lifecycle Layer

Detection fires an alert. The case lifecycle layer tracks everything
that happens next. This is the other 95 percent of the analyst's job.

| Table | Purpose |
|---|---|
| alert_parameters | Detection thresholds managed by compliance officers without touching SQL |
| alerts | Every alert saved with status and SLA countdown |
| cases | One investigation per accepted alert |
| case_notes | Analyst notes by investigation stage |
| dispositions | Final outcome including SAR filing detail |
| audit_log | Every action logged — 7 year retention per 31 CFR 1010.430 |

**Operational queries:**

- Alert queue — morning view sorted by tier and SLA countdown
- SLA aging — everything approaching or past deadline
- Case dashboard — supervisor view of all open work
- Disposition summary — management and BSA officer reporting
- Analyst workload — caseload per analyst
- SAR filing log — all formal reports with evidence summary
- Full case timeline — complete audit trail for one case

---

## Detection Threshold Rationale

Every threshold in the system is stored in the alert_parameters table.
Nothing is hardcoded in the detection queries.
Here is why each key threshold was set where it is.

**Velocity flag at 2.0 standard deviations:**
At 2.0 standard deviations, roughly 5 percent of normal observations
fall above the threshold by chance. This produces a manageable false
positive rate while capturing meaningful anomalies. Consistent with
peer institution benchmarks and FFIEC examination guidance.

**Velocity high alert at 3.0 standard deviations:**
At 3.0 standard deviations, fewer than 0.3 percent of normal observations
fall above the threshold by chance. Activity at this level has a very
low probability of a legitimate explanation and warrants immediate review.

**12-month baseline window:**
One year captures a full seasonal cycle. A shorter window may flag
legitimate seasonal peaks as anomalies. A longer window dilutes the
signal from a genuine change in behavior. Consistent with industry
practice and FinCEN guidance on pattern-based detection.

**3-month minimum history:**
Fewer than three data points produces an unreliable average and
standard deviation. Accounts below this threshold are flagged for
manual review rather than statistical analysis.

**Structuring floor at $8,000:**
The CTR threshold is $10,000. The zone is set at $8,000 to catch
deposits deliberately kept $1,000 to $2,000 below the limit,
which is the most common structuring pattern per FinCEN advisory
FIN-2010-A001.

**Dormant threshold at 90 days:**
Ninety days is the standard industry threshold for defining dormancy,
consistent with federal examination guidance and peer institution practice.

---

## Risk Score Weighting

The combined alert dashboard scores every account across all detection
methods and rolls them into a single risk score. Here is how each
indicator is weighted and why.

| Indicator | Points | Reason for Weight |
|---|---|---|
| Velocity z-score above flag threshold | +2 | Primary alert indicator — most significant single signal |
| Velocity z-score above high alert threshold | +1 additional | Severity multiplier |
| Peer group z-score above threshold | +1 | Secondary indicator — reinforces velocity signal |
| 3+ structuring zone deposits this month | +2 | Structuring is itself a federal crime — high weight |
| Multi-branch deposits this month | +1 | Reinforces structuring pattern |
| Withdrawal within 5 days of deposit | +1 | Layering indicator |
| Geographic risk hit | +2 | Sanctions and FATF risk — immediate escalation consideration |
| Round number rate above 50% | +1 | Supporting indicator |
| Dormant account activation | +2 | Recognized typology — account may have been held for a scheme |

**Alert tiers from combined score:**

| Score | Tier |
|---|---|
| 0 | Normal |
| 1-2 | Watch |
| 3-4 | Flag |
| 5+ | High Alert |

---

## What This Demonstrates

**Working a transaction monitoring alert queue:**
Understanding velocity alerts, structuring patterns, peer group anomalies,
geographic risk flags, and dormant account alerts at the level of how they
are calculated — not just what they mean when they appear in a queue.

**Configurable threshold management:**
All detection thresholds live in alert_parameters. A compliance officer
can tune the system without a developer. This mirrors how real AML systems
are operated in production environments.

**BSA and FinCEN regulatory framework applied to system design:**
Every detection rule has a cited regulatory basis. Every SLA has a
cited regulatory requirement. The audit log retention period cites
31 CFR 1010.430.

**Investigation methodology:**
The case notes sample data reflects the full investigation sequence
from initial review through SAR filing, including FIU search, domestic
closed sources, financial profile, and hypothesis evolution.

**SAR filing workflow:**
Supervisor approval, FinCEN reference number, income gap documentation,
and SAR narrative summary are all captured, reflecting real filing requirements
under 31 CFR 1020.320.

**Examiner-ready documentation:**
Known limitations, regulatory citations, configurable parameters,
threshold rationale, and a complete audit trail are present because
a real AML system must survive examination, not just detect correctly.

---

## Known Limitations

- Cash deposits only in the statistical detection layer.
  Wires, ACH, and checks are not covered by the velocity and
  peer group queries.
- Peer group statistics require at least 3 accounts per group
  to be meaningful. With fewer accounts, one outlier distorts
  the calculation significantly.
- The geographic risk country list is illustrative.
  In production it would be pulled from a maintained reference
  table updated quarterly when FATF publishes new assessments.
- The system does not adjust detection thresholds automatically
  based on a subject's individual risk rating, though the
  risk_rating field is present in the subjects table for
  future implementation.
- Sanctions screening against the full OFAC SDN list is not
  included. This would run as a real-time point-of-transaction
  check in a production system.

---

## Sample Output

Running the combined alert dashboard against the sample data
produces the following alert queue:

```
account_holder   | alert_tier | risk | velocity_z | peer_z | struct | flags_triggered
-----------------+------------+------+------------+--------+--------+------------------------------------------
Tom McAllister   | HIGH ALERT |   9  |    8.42    |  3.21  |   4    | VELOCITY HIGH ALERT | STRUCTURING HIGH ALERT |
                 |            |      |            |        |        | MULTI-BRANCH DEPOSITS | WITHDRAWAL AFTER DEPOSIT |
                 |            |      |            |        |        | GEOGRAPHIC RISK HIT | ABOVE PEER GROUP
Bénédicte Noël  | FLAG       |   3  |    0.31    |  2.87  |   1    | ABOVE PEER GROUP | STRUCTURING PATTERN
Robert Kline     | FLAG       |   3  |    NULL    |  NULL  |   0    | DORMANT ACTIVATION | HIGH ROUND NUMBERS
Linda Park       | NORMAL     |   0  |    0.44    |  1.12  |   0    |
Maria Santos     | NORMAL     |   0  |   -0.29    |  0.84  |   0    |
James Okafor     | NORMAL     |   0  |    0.18    |  0.71  |   0    |
Miguel Torres    | NORMAL     |   0  |    0.22    |  0.89  |   0    |
Grace Nwosu      | NORMAL     |   0  |    0.15    |  0.95  |   0    |
Carlos Rivera    | NORMAL     |   0  |    0.31    |  0.42  |   0    |
Amy Chen         | NORMAL     |   0  |   -0.18    |  0.38  |   0    |
David Osei       | NORMAL     |   0  |    0.12    |  0.29  |   0    |
Sarah Kim        | NORMAL     |   0  |    0.08    |  0.44  |   0    |
```

McAllister surfaces at the top because multiple detection methods
fired simultaneously. Noël and Kline surface below with different
patterns. Normal peer group accounts produce no alerts,
confirming the detection logic discriminates correctly.

---

## Schema

```
Detection layer
  subjects            — account holders with peer group type and risk rating
  bank_accounts       — accounts linked to subjects
  transactions        — deposits, withdrawals, and wires with branch and country

Lifecycle layer
  alert_parameters    — all detection thresholds, configurable without SQL changes
  alerts              — persisted alerts with status and SLA
  cases               — investigation case management
  case_notes          — analyst narrative by investigation stage
  dispositions        — case outcomes including full SAR filing detail
  audit_log           — immutable action log, 7-year retention per 31 CFR 1010.430
```

---

## Quick Start

**Requirements:** PostgreSQL 13 or higher

**Run everything at once:**

```bash
# Create a fresh database
sudo -u postgres createdb aml_monitoring

# Run the full system
sudo -u postgres psql -d aml_monitoring -f run_all.sql
```

**Run files one at a time:**

```bash
sudo -u postgres psql -d aml_monitoring -f sql/01_schema.sql
sudo -u postgres psql -d aml_monitoring -f sql/02_sample_data.sql
sudo -u postgres psql -d aml_monitoring -f sql/03_detection_engine.sql
sudo -u postgres psql -d aml_monitoring -f sql/04_alert_dashboard.sql
sudo -u postgres psql -d aml_monitoring -f sql/05_case_lifecycle.sql
```

**PowerShell from Windows (copying to a VPS first):**

```powershell
scp -r . root@your-vps-ip:/home/aml_monitoring
ssh root@your-vps-ip
sudo -u postgres createdb aml_monitoring
sudo -u postgres psql -d aml_monitoring -f /home/aml_monitoring/run_all.sql
```

---

## Regulatory Reference

**Bank Secrecy Act (BSA):** 31 U.S.C. 5318(g) requires financial institutions
to maintain an effective AML program including transaction monitoring.

**SAR Filing:** 31 CFR 1020.320 requires SARs to be filed within 30 calendar
days of detecting a suspicious transaction of $5,000 or more.

**Structuring Prohibition:** 31 U.S.C. 5324 makes it a federal crime to
deliberately break up transactions to avoid the $10,000 CTR reporting
threshold, regardless of the source of the funds.

**CTR Filing:** 31 CFR 1010.311 requires Currency Transaction Reports for
cash transactions of $10,000 or more. Structuring to avoid this threshold
is the offense detected in methods 6, 7, and 8 of this system.

**Customer Due Diligence:** 31 CFR 1010.230 requires financial institutions
to understand expected account activity for each customer type. Peer group
benchmarking supports this requirement.

**Record Retention:** 31 CFR 1010.430 requires BSA records to be retained
for five years. The audit_log table is built for seven-year retention
as a conservative internal standard.

**FATF High-Risk Jurisdictions:** The Financial Action Task Force publishes
grey and black lists of countries with weak AML controls. The geographic
risk detection in method 12 uses these lists.
Current lists: https://www.fatf-gafi.org/en/topics/high-risk-and-other-monitored-jurisdictions.html

---

## Related Project

**AML RIA Readiness Framework** — A seven-pillar compliance scoring rubric
and PostgreSQL scoring engine built around FinCEN's 2026 investment adviser
AML deadline. Addresses the gap between current RIA compliance posture
and incoming BSA/AML requirements for registered investment advisers.

---

## Author

Pam Adkins-Smith
AML Analyst | Financial Crimes Detection | SQL | BSA Compliance

GitHub: github.com/padkinssmith
LinkedIn: linkedin.com/in/pamadkinssmith

*Add GitHub topics to this repository:
aml, anti-money-laundering, bsa, transaction-monitoring, postgresql,
sql, financial-crime, compliance, structuring-detection, fintech*
