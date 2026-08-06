{{ config(materialized='view') }}

-- Methods table 2: highest level of education and educational goal at entry.
-- Source: console_7.sql (table2).
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
{{ education_table('total_uni') }}
),
noncred_only_tbl as (
{{ education_table('noncred_only_uni') }}
),
credit_only_tbl as (
{{ education_table('credit_only_uni') }}
),
both_tbl as (
{{ education_table('both_uni') }}
)
select * from total_tbl
UNION ALL
select * from noncred_only_tbl
UNION ALL
select * from credit_only_tbl
UNION ALL
select * from both_tbl