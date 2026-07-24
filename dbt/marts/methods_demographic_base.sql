{{ config(materialized='table') }}

-- methods_demographic_base: one row per student in the analysis sample, with the
-- recoded analysis features used by the methods tables. This is the reusable
-- base that methods_table1 / _table2 / _table3 aggregate over.
--
-- Source: console_7.sql ("methods tables 1-3", the `demographic_base` CTE).
-- Sample filter: first_term_enrolled between 175 and 234.
--
-- The pure-placeholder columns from the source (ever_developmental_english,
-- ever_developmental_math, transferred_4_year_college,
-- completed_transfer_level_english_3_6_year, full_time_student,
-- limited_english_proficiency — all hardcoded 'V2'/'TODO'/'DROP?') are omitted
-- since they carry no data and no summary table uses them.

with students as (

    select * from {{ ref('students_cohort_info') }}
    where first_term_enrolled between 175 and 234

)

select
    maskedsb00,
    uuid,

    -- demographics
    age_at_first_term,
    gender,
    latin_american::bool                as latin_american,
    black::bool                         as black,
    aapi::bool                          as aapi,
    white::bool                         as white,
    indigenous_american::bool           as indigenous_american,
    no_data::bool                       as unknown_race,
    (
        (latin_american::bool::int + black::bool::int + aapi::bool::int
         + indigenous_american::bool::int + white::bool::int) >= 2
    )                                   as two_or_more_races,
    case when hispanic_non_hispanic = 'Y' then true else false end as hispanic_non_hispanic,
    citizenship_earliest,
    highest_ed,
    special_admit_dual_enrollment,
    case when pell_grant_recipient then true else false end as pell_grant_recipient,



    case when english_or_math_enrollment then true else false end as english_or_math_enrollment,

    -- degree earned within 3-year (6-term) and 6-year (12-term) windows
    case when earliest_degree_term <= term_in_6  then true else false end as earned_degree_3_year,
    case when earliest_degree_term <= term_in_12 then true else false end as earned_degree_6_year,

    case when eops_recipient then true else false end as eops_recipient,
    case when primary_disability is not null then true else false end as has_disability,

    sb14_student_ed_goal,
    case sb14_student_ed_goal
        when 'A' then 'Obtain an associate degree and transfer to a four-year institution'
        when 'B' then 'Transfer to a 4-year institution without an associate degree'
        when 'C' then 'Transfer to a 4-year institution without an associate degree'
        when 'E' then 'Earn a vocational certificate without transfer'
        when 'F' then 'Discover / formulate career interests, plans, goals'
        when 'G' then 'Prepare for a new career (acquire job skills)'
        when 'H' then 'Advance in current job / career (update job skills)'
        when 'I' then 'Maintain certificate or license (e.g. Nursing, Real Estate)'
        when 'J' then 'Educational development (intellectual, cultural)'
        when 'K' then 'Improve basic skills in English, reading or math'
        when 'L' then 'Complete credits for high school diploma or GED'
        when 'M' then 'Undecided on goal'
        when 'N' then 'To move from noncredit coursework to credit coursework'
        when 'O' then '4-year college student taking courses to meet 4-year college requirements'
    end                                 as goal_at_enrollment,

    -- ESL credit/non-credit categories
    ever_credit_esl,
    always_noncredit_esl,
    always_credit_esl,
    both_credit_noncredit_esl,

    -- cohort + completion
    cohort,
    first_academic_year,
    first_cb21_level,
    first_cb21_level_adj,
    first_college_name_adj,
    first_college_group_adj

from students
