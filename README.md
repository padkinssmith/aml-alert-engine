# AML Alert Engine

**Pam Adkins-Smith** — Financial Services Analyst transitioning into AML
and Financial Crimes Analysis

[LinkedIn](https://linkedin.com/in/pamadkinssmith) |
[GitHub](https://github.com/padkinssmith)

---

## Why I Built This

I have twenty years of experience as an analyst and six years working
directly in financial services. I am now studying AML seriously and
targeting financial crimes analyst roles.

I built this project because I wanted to understand how transaction
monitoring actually works before sitting down to use it on the job.

So I built the detection logic from scratch in SQL. Every method in
this system mirrors what enterprise transaction monitoring platforms
do under the hood. Building it taught me not just what the alerts are,
but why they exist, what regulation requires them, and what an analyst
should be looking for when one fires.

---

## What This System Does

It watches bank accounts for suspicious activity.

When something looks wrong it scores the account, generates an alert,
and tracks that alert through the full investigation process — from
the first flag all the way through to the final decision.

It covers the patterns analysts encounter most often in a cash
monitoring queue:

- A customer whose deposits suddenly spike far above their own history
- A business depositing far more cash than any similar business in the area
- Deposits made just under the $10,000 reporting limit, month after month
- The same account using different bank branches to make deposits
- Cash deposited then quickly withdrawn a few days later
- An account that sat dormant for months then suddenly became active
- Transactions connected to countries flagged as high risk

When multiple patterns fire on the same account at the same time,
the system combines them into a single risk score and surfaces that
account at the top of the alert queue.

---

## What Happens After the Alert Fires

Detection is only the first part of the job. This system also tracks
everything that comes after.

When an alert fires it is saved and assigned to an analyst. The analyst
opens an investigation, writes notes as they work through each source,
and records how their working theory changes as new evidence comes in.
At the end they record a final decision: clear it, monitor it, refer it,
or file a Suspicious Activity Report with FinCEN.

Every action taken is logged with a timestamp. The full history of every
case is preserved. Nothing disappears.

---

## What This Says About Me as a Candidate

Building this system meant making decisions that required real
understanding. Why is the structuring detection zone set at $8,000
and not $9,000? Why does comparing an account to similar businesses
catch things that comparing it to its own history misses? Why does the
case audit log need a seven-year retention period?

Every one of those decisions is documented in the code with its
regulatory basis. Answering those questions is what the study behind
this project produced.

My goal was to arrive prepared rather than spend the first months on
the job learning what I could have learned before I started.

---

## For Technical Reviewers

The SQL files contain the full detection logic, sample data with
suspicious patterns built in, and the complete case lifecycle layer.
Every query is commented in plain English explaining what it does
and why.

---

## What Is in the Repository

```
run_all.sql              — runs the entire system in one command
01_schema.sql            — the database structure
02_sample_data.sql       — sample accounts with patterns built in
03_detection_engine.sql  — 13 detection methods
04_alert_dashboard.sql   — combined alert queue output
05_case_lifecycle.sql    — alert tracking, cases, and dispositions
```

---

## Author

**Pam Adkins-Smith**
Financial Services Analyst | Transitioning into AML and Financial Crimes Analysis
20 years analytical experience | 6 years financial services

[LinkedIn](https://linkedin.com/in/pamadkinssmith) |
[GitHub](https://github.com/padkinssmith)

Open to AML Analyst, BSA Analyst, Financial Crimes Analyst, and
Compliance Analyst roles. Remote preferred.

---

## Running It

Requires PostgreSQL 13 or higher.

```bash
sudo -u postgres createdb aml_monitoring
sudo -u postgres psql -d aml_monitoring -f run_all.sql
```
