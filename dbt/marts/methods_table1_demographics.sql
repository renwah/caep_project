{{ config(materialized='view') }}

-- Methods table 1: gender, race, age-at-entry, disability and citizenship counts
-- across the analysis sample. Source: console_7.sql (table1).

with total_uni as (

    select * from {{ ref('methods_demographic_base') }} where first_college_group IN ('CONFIRMED CC - 6 LEVELS', 'CONFIRMED CC - A/B', 'CONFIRMED CC - E/F')

),
noncred_only_uni as (
        select * from total_uni
        where always_noncredit_esl
),
credit_only_uni as (
        select * from total_uni
        where always_credit_esl
),
both_uni as (
        select * from total_uni
        where both_credit_noncredit_esl
),
total_tbl as (
{{ demographics_table('total_uni') }}
),
noncred_only_tbl as (
{{ demographics_table('noncred_only_uni') }}
),
credit_only_tbl as (
{{ demographics_table('credit_only_uni') }}
),
both_tbl as (
{{ demographics_table('both_uni') }}
)
select * from total_tbl
UNION ALL
select * from noncred_only_tbl
UNION ALL
select * from credit_only_tbl
UNION ALL
select * from both_tbl