{{ config(materialized='view') }}

-- Methods table 2: highest level of education and educational goal at entry.
-- Source: console_7.sql (table2).

with db as (

    select * from {{ ref('methods_demographic_base') }}

)

select
    count(*)                                                                     as total,
    count(*) filter (where highest_ed = '0')                                     as highest_ed_no_high_school,
    count(*) filter (where highest_ed = '2')                                     as highest_ed_adult_school,
    count(*) filter (where highest_ed = '3')                                     as highest_ed_high_school_diploma,
    count(*) filter (where highest_ed = '4')                                     as highest_ed_ged_equivalent,
    count(*) filter (where highest_ed = '5')                                     as highest_ed_chs_proficiency_certificate,
    count(*) filter (where highest_ed = '6')                                     as highest_ed_foreign_secondary_school_diploma,
    count(*) filter (where highest_ed = '7')                                     as highest_ed_associate_degree,
    count(*) filter (where highest_ed = '8')                                     as highest_ed_bachelor_or_higher_degree,
    count(*) filter (where highest_ed = 'X' or highest_ed is null)               as highest_ed_unknown,
    count(*) filter (where sb14_student_ed_goal = 'A') as "Obtain an AD and transfer to a 4-year institution",
    count(*) filter (where sb14_student_ed_goal = 'B') as "Transfer to a 4-year institution without an AD",
    count(*) filter (where sb14_student_ed_goal = 'C') as "Transfer to a 4-year institution without an associate degree",
    count(*) filter (where sb14_student_ed_goal = 'E') as "Earn a vocational certificate without transfer",
    count(*) filter (where sb14_student_ed_goal = 'F') as "Discover / formulate career interests, plans, goals",
    count(*) filter (where sb14_student_ed_goal = 'G') as "Prepare for a new career (acquire job skills)",
    count(*) filter (where sb14_student_ed_goal = 'H') as "Advance in current job / career (update job skills)",
    count(*) filter (where sb14_student_ed_goal = 'I') as "Maintain certificate or license (e.g. Nursing, Real Estate)",
    count(*) filter (where sb14_student_ed_goal = 'J') as "Educational development (intellectual, cultural)",
    count(*) filter (where sb14_student_ed_goal = 'K') as "Improve basic skills in English, reading or math",
    count(*) filter (where sb14_student_ed_goal = 'L') as "Complete credits for high school diploma or GED",
    count(*) filter (where sb14_student_ed_goal = 'M') as "Undecided on goal",
    count(*) filter (where sb14_student_ed_goal = 'N') as "To move from noncredit coursework to credit coursework",
    count(*) filter (where sb14_student_ed_goal = 'O') as "4-year college student taking courses to meet requirements"
from db
