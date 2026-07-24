{{ config(materialized='view') }}

-- Methods table 3: financial aid, special admit, English/Math enrollment,
-- starting ESL level and degree attainment. Source: console_7.sql (table3).

with db as (

    select * from {{ ref('methods_demographic_base') }}

)

select
    count(*)                                                                as total,
    count(*) filter (where pell_grant_recipient)                            as pell_grant_recipient,
    count(*) filter (where not pell_grant_recipient)                        as not_pell_grant_recipient,
    count(*) filter (where eops_recipient)                                  as eops_recipient,
    count(*) filter (where not eops_recipient)                              as not_eops_recipient,
    count(*) filter (where special_admit_dual_enrollment)                   as special_admit_dual_enrollment,
    count(*) filter (where not special_admit_dual_enrollment)               as not_special_admit_dual_enrollment,
    count(*) filter (where english_or_math_enrollment)                      as english_or_math_enrollment,
    count(*) filter (where not english_or_math_enrollment)                  as not_english_or_math_enrollment,
    count(*) filter (where first_cb21_level = 'A')                          as starting_level_esl_a,
    count(*) filter (where first_cb21_level = 'B')                          as starting_level_esl_b,
    count(*) filter (where first_cb21_level = 'C')                          as starting_level_esl_c,
    count(*) filter (where first_cb21_level = 'D')                          as starting_level_esl_d,
    count(*) filter (where first_cb21_level = 'E')                          as starting_level_esl_e,
    count(*) filter (where first_cb21_level = 'F')                          as starting_level_esl_f,
    count(*) filter (where first_cb21_level = 'G')                          as starting_level_esl_g,
    count(*) filter (where first_cb21_level = 'H')                          as starting_level_esl_h,
    count(*) filter (where first_cb21_level = 'Y')                          as starting_level_esl_y_credit,
    count(*) filter (where first_cb21_level is null)                        as starting_level_esl_unknown,
    count(*) filter (where earned_degree_3_year)                            as earned_degree_3_year,
    count(*) filter (where not earned_degree_3_year)                        as not_earned_degree_3_year
from db
