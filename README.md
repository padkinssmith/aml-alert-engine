# AML Alert Engine

Built by Pam Adkins-Smith — an experienced financial services analyst
actively transitioning into AML and financial crimes analysis.

---

## Why I Built This

I have spent twenty years as an analyst and six years working directly
in financial services. I am now studying AML seriously and targeting
financial crimes analyst roles.

I built this project for one reason: I did not want to arrive on day one
asking someone to explain what an alert means and why it fired.

So I built the detection logic myself. From scratch. In SQL.

Every method in this system mirrors what enterprise transaction monitoring
platforms do under the hood. Building it taught me not just what the
alerts are, but why they exist, what regulation requires them, and what
an analyst should be looking for when one fires.

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

Detection is the first part of the job. This system also tracks
everything that comes after.

When an alert fires it is saved and assigned to an analyst. The analyst
opens an investigation, writes notes as they work through each source,
and records how their theory about the account changes as new evidence
comes in. At the end they record a final decision: clear it, monitor it,
refer it, or file a Suspicious Activity Report with FinCEN.

Every action taken is logged with a timestamp. Nothing disappears.
The full history of every case is preserved.

---

## What This Says About Me as a Candidate

I did not take a course and list the skill. I built the system and
learned why it works the way it does.

I understand what fires a velocity alert and why the threshold is set
where it is. I understand why comparing an account to similar businesses
catches things that comparing it to its own history misses. I understand
what structuring is, why it is its own federal crime separate from the
underlying activity, and what the deposit pattern looks like in the data.

I also understand that the system is only as good as the analyst working
the queue. This project gave me the foundation to be that analyst from
day one rather than spending the first months learning what I could have
learned before I started.

---

## For Technical Reviewers

The SQL files in this repository contain the full detection logic,
sample data with suspicious patterns built in, and the complete
case lifecycle layer. Anyone who wants to see exactly how any of
this works can open the files and read the code. Every query is
commented in plain English explaining what it does and why.

---

## The Files

```
run_all.sql              — runs everything in one command
01_schema.sql            — the database structure
02_sample_data.sql       — sample accounts with patterns built in
03_detection_engine.sql  — 13 detection methods
04_alert_dashboard.sql   — combined alert queue output
05_case_lifecycle.sql    — alert tracking, cases, and dispositions
```

---

## Running It

Requires PostgreSQL 13 or higher.

```bash
sudo -u postgres createdb aml_monitoring
sudo -u postgres psql -d aml_monitoring -f run_all.sql
```

---

## Author

Pam Adkins-Smith
Financial Services Analyst | Transitioning into AML and Financial Crimes Analysis
20 years analytical experience | 6 years financial services

LinkedIn: linkedin.com/in/pamadkinssmith
GitHub: github.com/padkinssmith
