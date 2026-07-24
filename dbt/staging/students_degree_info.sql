{{ config(materialized='view') }}

-- students_degree_info: degree / award attributes, one row per student, layered
-- onto students_demographics.
--
-- Source logic: "demographics study.sql" (earliest + highest degree sections).
-- Awards are read from sr1318sp; sp03 is the award date as a YYYYMMDD integer,
-- and sp_award_types ranks award codes so we can pick the "highest" one.

with students as (

    select * from {{ ref('students_demographics') }}

),

-- Normalize the raw sp03 integer into a real date once, up front.
awards as (

    select
        maskedsb00,
        sp01                                 as topcode,
        sp02                                 as award_code,
        gi03,
        to_date(sp03::text, 'YYYYMMDD')      as degree_date
    from {{ source('caep_data', 'sr1318sp') }}
    where sp03 is not null
      and gi03 >= 175

),

-- Earliest degree earned, plus a count of degrees in the period.
earliest_degree as (

    select
        maskedsb00,
        (array_agg(degree_date order by degree_date asc))[1] as earliest_degree_date,
        (array_agg(award_code  order by degree_date asc))[1] as earliest_degree_type,
        (array_agg(topcode     order by degree_date asc))[1] as earliest_degree_topcode,
        count(*)                                             as number_degrees_17_23
    from awards
    group by maskedsb00

),

-- Highest degree earned, ranked by sp_award_types.award_ranking (1 = highest).
highest_degree as (

    select
        a.maskedsb00,
        (array_agg(a.award_code    order by t.award_ranking asc))[1] as highest_degree_earned,
        (array_agg(t.award_description order by t.award_ranking asc))[1] as highest_degree_earned_description
    from awards a
    join {{ source('caep_data', 'sp_award_types') }} t
        on a.award_code = t.award_code
    where a.gi03 between 175 and 234
    group by a.maskedsb00

),

-- Term (gi03) corresponding to the earliest degree date, matched on the custom
-- quarter encoding stored on sr1318term.
earliest_degree_term as (

    select
        ed.maskedsb00,
        max(t.gi03) as earliest_degree_term
    from earliest_degree ed
    join {{ source('caep_data', 'sr1318term') }} t
        on date_part('quarter', ed.earliest_degree_date) = t.quarter
       and right(date_part('year', ed.earliest_degree_date)::text, 2) = left(t.gi03::text, 2)
    where ed.earliest_degree_date is not null
    group by ed.maskedsb00

)

select
    s.*,

    ed.earliest_degree_date,
    ed.earliest_degree_type,
    ed.earliest_degree_topcode,
    ed.number_degrees_17_23,
    edt.earliest_degree_term,

    hd.highest_degree_earned,
    hd.highest_degree_earned_description

from students s
left join earliest_degree      ed  on s.maskedsb00 = ed.maskedsb00
left join earliest_degree_term edt on s.maskedsb00 = edt.maskedsb00
left join highest_degree       hd  on s.maskedsb00 = hd.maskedsb00
