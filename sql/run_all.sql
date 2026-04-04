-- ============================================================
-- AML Transaction Monitoring System
-- File: run_all.sql
-- Purpose: Runs all five files in the correct order.
--
-- Usage:
--   sudo -u postgres createdb aml_monitoring
--   sudo -u postgres psql -d aml_monitoring -f run_all.sql
-- ============================================================

\echo ''
\echo '════════════════════════════════════════════════════════'
\echo 'AML Transaction Monitoring System'
\echo 'Starting full setup...'
\echo '════════════════════════════════════════════════════════'

\echo ''
\echo 'Step 1 of 5: Creating schema...'
\ir sql/01_schema.sql

\echo ''
\echo 'Step 2 of 5: Loading detection thresholds and data...'
\ir sql/02_sample_data.sql

\echo ''
\echo 'Step 3 of 5: Running 13 detection methods...'
\ir sql/03_detection_engine.sql

\echo ''
\echo 'Step 4 of 5: Running combined alert dashboard...'
\ir sql/04_alert_dashboard.sql

\echo ''
\echo 'Step 5 of 5: Running case lifecycle layer...'
\ir sql/05_case_lifecycle.sql

\echo ''
\echo '════════════════════════════════════════════════════════'
\echo 'Complete.'
\echo ''
\echo 'Detection layer:  13 methods, combined alert dashboard'
\echo 'Lifecycle layer:  alerts, cases, notes, dispositions,'
\echo '                  audit log, 7 operational queries'
\echo '════════════════════════════════════════════════════════'
