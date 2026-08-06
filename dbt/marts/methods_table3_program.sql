{{ config(materialized='view') }}

-- Methods table 3: financial aid, special admit, English/Math enrollment,
-- starting ESL level and degree attainment. Source: console_7.sql (table3).

with total_uni as (

    select * from {{ ref('methods_demographic_base') }}

),
noncred_only_uni as (
        select * from {{ ref('methods_demographic_base') }}
        where always_noncredit_esl
),
credit_only_uni as (
        select * from {{ ref('methods_demographic_base') }}
        where always_credit_esl
),
both_uni as (
        select * from {{ ref('methods_demographic_base') }}
        where both_credit_noncredit_esl
),
total_tbl as (
{{ program_table('total_uni') }}
),
noncred_only_tbl as (
{{ program_table('noncred_only_uni') }}
),
credit_only_tbl as (
{{ program_table('credit_only_uni') }}
),
both_tbl as (
{{ program_table('both_uni') }}
)
select * from total_tbl
UNION ALL
select * from noncred_only_tbl
UNION ALL
select * from credit_only_tbl
UNION ALL
select * from both_tbl