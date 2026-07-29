{{ config(materialized='view') }}

-- students_demographics: personal demographic attributes, one row per student,
-- layered onto the students spine.
--
-- Source logic: "demographics study.sql". Race is decoded from the sr1318st.sb29
-- bitstring; gender from sb04. Citizenship / highest education are read over the
-- study window (gi03 between 175 and 234); age is taken at the student's first
-- recorded term.

with students as (

    select * from {{ ref('students') }}

),

-- gender + race, aggregated to one row per student across all of that student's
-- college records. The per-field min/max choices mirror the original queries.
demographics as (

    select
        maskedsb00,
        min(sb04)                                                                     as gender,
        max(left(sb29, 1))                                                            as hispanic_non_hispanic,
        max(case when substr(sb29, 2, 4) like '%Y%' then 'Y' else 'N' end)            as latin_american,
        max(case
                when substr(sb29, 6, 9) like '%Y%' or substr(sb29, 17, 4) like '%Y%'
                    then 'Y' else 'N' end)                                            as aapi,
        max(substr(sb29, 15, 1))                                                       as black,
        max(substr(sb29, 16, 1))                                                      as indigenous_american,
        max(substr(sb29, 21, 1))                                                      as white,
        min(case when length(sb29) < 21 or sb29 not like '%Y%' then 'Y' else 'N' end) as no_data
    from {{ source('caep_data', 'sr1318st') }}
    group by maskedsb00

),

-- earliest / latest citizenship status within the study window.
citizenship as (

    select
        maskedsb00,
        (array_agg(sb06 order by gi03 asc))[1]  as citizenship_earliest,
        (array_agg(sb06 order by gi03 desc))[1] as citizenship_latest
    from {{ source('caep_data', 'sr1318st') }}
    where gi03 between 175 and 234
    group by maskedsb00

),

-- highest level of education (first character of sb11) within the study window.
highest_ed as (

    select
        maskedsb00,
        min(left(sb11, 1)) as highest_ed
    from {{ source('caep_data', 'sr1318st') }}
    where gi03 between 175 and 234
    group by maskedsb00

),

-- primary disability.
disability as (

    select
        maskedsb00,
        min(sd01) as primary_disability
    from {{ source('caep_data', 'sr1318sd') }}
    group by maskedsb00

),

-- age at first term = std1 value at the student's earliest recorded term.
age_at_first_term as (

    select
        maskedsb00,
        (array_agg(std1 order by gi03 asc))[1] as age_at_first_term
    from {{ source('caep_data', 'sr1318st') }}
    group by maskedsb00

),

-- special-admit / dual-enrollment flag (sb11 = '10000').
special_admit as (

    select
        maskedsb00,
        bool_or(sb11 = '10000') as special_admit_dual_enrollment
    from {{ source('caep_data', 'sr1318st') }}
    group by maskedsb00

),

-- student educational goal (sb14) taken at the earliest recorded term.
ed_goal as (

    select
        maskedsb00,
        (array_agg(sb14 order by gi03 asc))[1] as sb14_student_ed_goal
    from {{ source('caep_data', 'sr1318st') }}
    group by maskedsb00

),

-- ever enrolled in (transfer-level, cb05 in A/B) English or Math.
--   English cb03: 150100, 150110, 152000
--   Math    cb03: 170000, 170200, 170100, 170110, 170170
-- Joined on cb00 only, matching the source query.
english_or_math as (

    select
        sx.maskedsb00,
        count(sx.sx01) > 1 as english_or_math_enrollment
    from {{ source('caep_data', 'sr1318sx') }} sx
    join {{ source('caep_data', 'sr1318cb') }} c on sx.cb00 = c.cb00
    where c.cb05 in ('A', 'B')
      and (c.cb03 in ('150100', '150110', '152000')
           or c.cb03 in ('170000', '170200', '170100', '170110', '170170'))
    group by sx.maskedsb00

),

-- financial aid: Pell (sf21 = 'GP') and EOPS (sf21 = 'GE') recipients.
financial_aid as (

    select
        maskedsb00,
        bool_or(sf21 = 'GP') as pell_grant_recipient,
        bool_or(sf21 = 'GE') as eops_recipient
    from {{ source('caep_data', 'sr1318sfa') }}
    group by maskedsb00

)

select
    s.maskedsb00,
    s.uuid,

    d.gender,
    d.hispanic_non_hispanic,
    d.latin_american,
    d.aapi,
    d.black,
    d.indigenous_american,
    d.white,
    d.no_data,

    c.citizenship_earliest,
    c.citizenship_latest,

    e.highest_ed,
    dis.primary_disability,
    a.age_at_first_term,

    sa.special_admit_dual_enrollment,
    g.sb14_student_ed_goal,
    em.english_or_math_enrollment,
    fa.pell_grant_recipient,
    fa.eops_recipient

from students s
left join demographics       d   on s.maskedsb00 = d.maskedsb00
left join citizenship        c   on s.maskedsb00 = c.maskedsb00
left join highest_ed         e   on s.maskedsb00 = e.maskedsb00
left join disability         dis on s.maskedsb00 = dis.maskedsb00
left join age_at_first_term  a   on s.maskedsb00 = a.maskedsb00
left join special_admit      sa  on s.maskedsb00 = sa.maskedsb00
left join ed_goal            g   on s.maskedsb00 = g.maskedsb00
left join english_or_math    em  on s.maskedsb00 = em.maskedsb00
left join financial_aid      fa  on s.maskedsb00 = fa.maskedsb00
