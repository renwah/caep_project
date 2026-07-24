{{ config(materialized='view') }}

-- Methods table 1: gender, race, age-at-entry, disability and citizenship counts
-- across the analysis sample. Source: console_7.sql (table1).

with db as (

    select * from {{ ref('methods_demographic_base') }}

)

select
    count(*)                                                                        as total,
    count(*) filter (where gender = 'M')                                            as gender_m,
    count(*) filter (where gender = 'F')                                            as gender_f,
    count(*) filter (where gender not in ('M', 'F'))                                as gender_u,
    count(*) filter (where latin_american)                                          as latin_american,
    count(*) filter (where black)                                                   as black,
    count(*) filter (where aapi)                                                    as aapi,
    count(*) filter (where white)                                                   as white,
    count(*) filter (where indigenous_american)                                     as indigenous_american,
    count(*) filter (where unknown_race)                                            as unknown_race,
    count(*) filter (where two_or_more_races)                                       as two_or_more_races,
    count(*) filter (where age_at_first_term::int <= 24)                            as traditional_age_at_entry,
    count(*) filter (where age_at_first_term::int > 24)                             as over_traditional_age_at_entry,
    count(*) filter (where age_at_first_term::int < 18)                             as age_at_entry_below_18,
    count(*) filter (where age_at_first_term::int between 18 and 24)                as age_at_entry_18_24,
    count(*) filter (where age_at_first_term::int between 25 and 44)                as age_at_entry_25_44,
    count(*) filter (where age_at_first_term::int between 45 and 54)                as age_at_entry_45_54,
    count(*) filter (where age_at_first_term::int between 55 and 59)                as age_at_entry_55_59,
    count(*) filter (where age_at_first_term::int between 60 and 110)               as age_at_entry_60_plus,
    count(*) filter (where has_disability)                                          as has_disability,
    count(*) filter (where not has_disability)                                      as not_has_disability,
    count(*) filter (where citizenship_earliest = '1')                              as citizenship_earliest_us_citizen,
    count(*) filter (where citizenship_earliest = '2')                              as citizenship_earliest_permanent_resident,
    count(*) filter (where citizenship_earliest = '3')                              as citizenship_earliest_temporary_resident,
    count(*) filter (where citizenship_earliest = '4')                              as citizenship_earliest_refugee_asylee,
    count(*) filter (where citizenship_earliest = '5')                              as citizenship_earliest_student_visa,
    count(*) filter (where citizenship_earliest = '6')                              as citizenship_earliest_other_status,
    count(*) filter (where citizenship_earliest = 'X' or citizenship_earliest is null) as citizenship_earliest_unknown
from db
