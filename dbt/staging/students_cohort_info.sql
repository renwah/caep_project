{{ config(materialized='view') }}

-- students_cohort_info: cohort / sample / starting-point attributes, one row per
-- student, layered onto students_degree_info. This is the final model in the
-- chain, so it is the complete students table.
--
-- Source logic: "building sample.sql", "console_2.sql", and the CB21 sections of
-- "pathways_calculations.sql". Core fields recorded here:
--   * first term enrolled / first ESL term
--   * which sample  (in_sample, first_academic_year, cohort)
--   * first campus  (first_college_name)
--   * first course type  (noncredit / credit-only / both)
--   * first CB21 level, and the college-adjusted version
--
-- The four ESL program codes ('493084','493085','493086','493087') identify ESL
-- courses throughout, matching the source SQL.

with students as (

    select * from {{ ref('students_degree_info') }}

),

-- First term the student was enrolled in anything. The <700 guard mirrors the
-- source: real study terms are <700; 700+ codes are placeholders, so fall back
-- to the 300-999 window only when every term is a placeholder.
first_enrollment as (

    select
        student_uuid,
        case
            when min(gi03) < 700 then min(gi03)
            else min(gi03) filter (where gi03 between 300 and 999)
        end as first_term_enrolled
    from {{ source('caep_data', 'sr1318sx') }}
    group by student_uuid

),

-- First term the student took an ESL course (this is what the cohort is keyed on).
first_esl as (

    select
        sx.student_uuid,
        case
            when min(sx.gi03) < 700 then min(sx.gi03)
            else min(sx.gi03) filter (where sx.gi03 between 300 and 999)
        end as first_esl_term
    from {{ source('caep_data', 'sr1318sx') }} sx
    join {{ source('caep_data', 'sr1318cb') }} cb
        on sx.cb00 = cb.cb00 and cb.gi03 = sx.gi03
    where cb.cb03 in ('493084', '493085', '493086', '493087')
    group by sx.student_uuid

),

-- Analysis sample (from building sample.sql's ells_started_17_w_attendance):
--   * took an ESL course in the study window (gi03 170-239),
--   * with >= 12 attendance hours in at least one academic year,
--   * whose first ESL term falls in the window,
--   * and who did NOT take ESL before the window (excluded below).
ell_enrollment as (

    select sx.student_uuid, sx.sx05, sx.gi03
    from {{ source('caep_data', 'sr1318sx') }} sx
    join {{ source('caep_data', 'sr1318cb') }} cb on sx.cb00 = cb.cb00
    where cb.cb03 in ('493084', '493085', '493086', '493087')
      and sx.gi03 between 170 and 239
    group by sx.student_uuid, sx.cb00, sx.cb01, sx.sx05, sx.gi03, sx.gi01

),

ell_attendance as (

    select student_uuid
    from ell_enrollment
    group by student_uuid, left(gi03::text, 2)
    having sum(sx05::double precision) >= 12

),

ells_before_study_period as (

    select distinct sx.maskedsb00
    from {{ source('caep_data', 'sr1318sx') }} sx
    join {{ source('caep_data', 'sr1318cb') }} cb on sx.cb00 = cb.cb00
    where cb.cb03 in ('493084', '493085', '493086', '493087')
      and sx.gi03 < 170

),

sample as (

    select sx.student_uuid
    from {{ source('caep_data', 'sr1318sx') }} sx
    join ell_attendance ell on sx.student_uuid = ell.student_uuid
    where sx.maskedsb00 not in (select maskedsb00 from ells_before_study_period)
    group by sx.student_uuid
    having min(sx.gi03) between 170 and 239

),

-- Cohort: half-year buckets keyed on the first ESL term.
cohort_terms as (

    select
        fe.student_uuid,
        term.year as first_academic_year,
        case
            when trim(term.term) in ('SUMMER TERM', 'SUMMER QUARTER', 'FALL SEMESTER', 'FALL QUARTER', 'ANNUAL')
                then 'F'
            when trim(term.term) in ('WINTER INTERSESSION', 'WINTER QUARTER', 'SPRING SEMESTER', 'SPRING QUARTER')
                then 'S'
        end as cohort
    from first_esl fe
    join {{ source('caep_data', 'sr1318term') }} term on fe.first_esl_term = term.gi03

),

-- Credit / non-credit ESL profile across the whole study window.
esl_ever as (

    select
        sx.student_uuid,
        bool_or(cb.cb04 in ('D', 'C')) as ever_credit_esl,
        bool_and(cb.cb04 = 'N')        as always_noncredit_esl,
        bool_and(cb.cb04 in ('C', 'D')) as always_credit_esl
    from {{ source('caep_data', 'sr1318sx') }} sx
    join {{ source('caep_data', 'sr1318cb') }} cb
        on sx.gi03 = cb.gi03 and sx.cb00 = cb.cb00
    where sx.gi03 between 170 and 239
      and cb.cb03 in ('493084', '493085', '493086', '493087')
    group by sx.student_uuid

),

-- First course type: what ESL course(s) did the student take in their first term?
first_term_courses as (

    select
        sx.student_uuid,
        bool_or(cb.cb04 = 'N')                                                 as first_term_noncredit,
        bool_and(cb.cb04 != 'N')                                              as first_term_credit_only,
        (bool_or(cb.cb04 = 'N') and bool_or(cb.cb04 in ('D', 'C')))            as first_term_credit_and_noncredit
    from {{ source('caep_data', 'sr1318sx') }} sx
    join first_enrollment fe
        on sx.student_uuid = fe.student_uuid and sx.gi03 = fe.first_term_enrolled
    join {{ source('caep_data', 'sr1318cb') }} cb
        on sx.gi03 = cb.gi03 and cb.cb00 = sx.cb00
    where cb.cb03 in ('493084', '493085', '493086', '493087')
    group by sx.student_uuid

),

-- First CB21 level (from pathways_calculations.sql "reassign first level"):
-- rank each student's ESL terms, take term 1, find the lowest starting level
-- (max levels_below_transfer) among their non-credit ESL courses, and map it
-- back to a CB21 letter. Also carries the college where that first term happened.
esl_terms_ranked as (

    select distinct
        sx.student_uuid,
        dense_rank() over (partition by sx.student_uuid order by sx.gi03 asc) as term_number,
        m.levels_below_transfer,
        coll.college_name
    from {{ source('caep_data', 'sr1318sx') }} sx
    join {{ source('caep_data', 'sr1318cb') }} cb
        on sx.cb00 = cb.cb00 and sx.gi03 = cb.gi03 and sx.gi01 = cb.gi01
    join {{ source('caep_data', 'sr1318term') }} term on sx.gi03 = term.gi03
    join {{ source('caep_data', 'sr1318colldist') }} coll on sx.gi01 = coll.gi01_college
    join {{ source('caep_data', 'course_efl_score_mapping') }} m on cb.cb21 = m.cb21
    where sx.gi03 > 174
      and left(term.year, 3) = '201'          -- during the period of interest
      and sx.sx02 = '19080808'                -- didn't drop
      and sx.sx04 not in ('W', 'NP', 'INP', 'FW', 'DR', 'F')  -- didn't fail/drop
      and cb.cb03 in ('493084', '493085', '493086', '493087')
      and cb.cb04 = 'N'
      and cb.cb21 != 'Y'

),

first_term_level as (

    select
        student_uuid,
        max(levels_below_transfer)                                     as lowest_starting_level,
        (array_agg(college_name order by levels_below_transfer desc))[1] as first_college_name
    from esl_terms_ranked
    where term_number = 1
    group by student_uuid

),

first_cb21 as (

    select
        f.student_uuid,
        f.first_college_name,
        m.cb21 as first_cb21_level
    from first_term_level f
    join {{ source('caep_data', 'course_efl_score_mapping') }} m
        on f.lowest_starting_level = m.levels_below_transfer

),

-- both_credit_noncredit_esl: among students who ever took credit ESL, did they
-- also take a non-credit ESL course (after term 174)? (console_2.sql)
esl_noncredit_after_174 as (

    select
        sx.student_uuid,
        bool_or(cb.cb04 = 'N') as took_noncredit_after_174
    from {{ source('caep_data', 'sr1318sx') }} sx
    join {{ source('caep_data', 'sr1318cb') }} cb
        on sx.gi03 = cb.gi03 and sx.cb00 = cb.cb00
    where sx.gi03 > 174
      and cb.cb03 in ('493084', '493085', '493086', '493087')
    group by sx.student_uuid

),

-- term_in_6 / term_in_12 (console_2.sql): the latest term a student attended
-- within the 6-term (3yr) and 12-term (6yr) windows after their first term.
-- The FALL/SPRING window boundaries mirror the source arithmetic exactly.
term_bounds as (

    select
        fe.student_uuid,
        fe.first_term_enrolled,
        case
            when left(fe.first_term_enrolled::text, 2) = substr(term.year, 2, 2)  -- fall cohort
                then ((fe.first_term_enrolled / 10) * 10) + 30 + 8
            else ((fe.first_term_enrolled / 10) * 10) + 30 + 4                     -- spring cohort
        end as latest_6_term,
        case
            when left(fe.first_term_enrolled::text, 2) = substr(term.year, 2, 2)
                then ((fe.first_term_enrolled / 10) * 10) + 60 + 8
            else ((fe.first_term_enrolled / 10) * 10) + 60 + 4
        end as latest_12_term
    from first_enrollment fe
    join {{ source('caep_data', 'sr1318term') }} term on fe.first_term_enrolled = term.gi03
    where fe.first_term_enrolled is not null

),

term_windows as (

    select
        tb.student_uuid,
        max(sx.gi03) filter (where sx.gi03 between tb.first_term_enrolled + 1 and tb.latest_6_term)  as term_in_6,
        max(sx.gi03) filter (where sx.gi03 between tb.latest_6_term + 1 and tb.latest_12_term)        as term_in_12
    from term_bounds tb
    join {{ source('caep_data', 'sr1318sx') }} sx on tb.student_uuid = sx.student_uuid
    group by tb.student_uuid

),

-- "B/F to A" full-completion metric (pathways_calculations.sql): using the
-- college-adjusted CB21 level, the first term a student reaches level 1 (A),
-- and how many levels below they started from.
esl_terms_adjusted as (

    select distinct
        sx.student_uuid,
        dense_rank() over (partition by sx.student_uuid order by sx.gi03 asc) as term_number,
        cb.cb03,
        case
            when coll.college_name in (
                'COMPTON','SANTA ANA','CUESTA','SEQUOIAS','YUBA','SAN FRANCISCO CITY','OXNARD',
                'L.A. MISSION','MENDOCINO','SANTA MONICA','CHABOT','CHAFFEY','SAN JOSE CITY','EAST L.A.',
                'MODESTO','ANTELOPE VALLEY','SAN FRANCISCO CTRS','SANTIAGO CANYON','CITRUS','GLENDALE',
                'VICTOR VALLEY','PALO VERDE','SADDLEBACK','CONTRA COSTA','FOOTHILL')
                then case when cb.cb21 = 'B' then 'A' else cb.cb21 end
            when coll.college_name in (
                'DIABLO VALLEY','BARSTOW','MORENO VALLEY','GOLDEN WEST','RIO HONDO','FRESNO CITY',
                'NORCO','MISSION','RIVERSIDE','SIERRA')
                then case when cb.cb21 = 'E' then 'F' else cb.cb21 end
            else cb.cb21
        end as cb21_adjusted
    from {{ source('caep_data', 'sr1318sx') }} sx
    join {{ source('caep_data', 'sr1318cb') }} cb
        on sx.cb00 = cb.cb00 and sx.gi03 = cb.gi03 and sx.gi01 = cb.gi01
    join {{ source('caep_data', 'sr1318term') }} term on sx.gi03 = term.gi03
    join {{ source('caep_data', 'sr1318colldist') }} coll on sx.gi01 = coll.gi01_college
    where sx.gi03 > 174
      and left(term.year, 3) = '201'
      and sx.sx02 = '19080808'
      and sx.sx04 not in ('W', 'NP', 'INP', 'FW', 'DR', 'F')
      and cb.cb03 in ('493084', '493085', '493086', '493087')
      and cb.cb21 not in ('G', 'H', 'Y')
      and cb.cb04 = 'N'

),

term_data_bf as (

    select distinct
        eta.student_uuid,
        eta.term_number,
        first_value(max(m.levels_below_transfer))
            over (partition by eta.student_uuid order by eta.term_number) as lowest_starting_level,
        min(m.levels_below_transfer)                                      as max_level_in_term
    from esl_terms_adjusted eta
    join {{ source('caep_data', 'course_efl_score_mapping') }} m on eta.cb21_adjusted = m.cb21
    group by eta.student_uuid, eta.term_number

),

completers_bf as (

    select
        student_uuid,
        min(term_number)             as terms_to_full_completion_adjusted_bf_to_a,
        (lowest_starting_level - 1)  as full_completion_levels_adjusted_bf_to_a
    from term_data_bf
    where max_level_in_term = 1
    group by student_uuid, lowest_starting_level

)

select
    s.*,

    fe.first_term_enrolled,
    fes.first_esl_term,

    -- which sample / cohort
    (smp.student_uuid is not null) as in_sample,
    ct.first_academic_year,
    ct.cohort,

    -- first course type
    ftc.first_term_noncredit,
    ftc.first_term_credit_only,
    ftc.first_term_credit_and_noncredit,

    -- credit / non-credit ESL profile
    ee.ever_credit_esl,
    ee.always_noncredit_esl,
    ee.always_credit_esl,
    case when ee.ever_credit_esl then na.took_noncredit_after_174 end as both_credit_noncredit_esl,

    -- attendance windows + "B/F to A" completion
    tw.term_in_6,
    tw.term_in_12,
    cbf.terms_to_full_completion_adjusted_bf_to_a,
    cbf.full_completion_levels_adjusted_bf_to_a,

    -- first campus + first CB21 level (raw and college-adjusted)
    fc.first_college_name,
    fc.first_cb21_level,
    case
        -- Colleges that collapse A/B into A.
        when fc.first_college_name in (
            'COMPTON','SANTA ANA','CUESTA','SEQUOIAS','YUBA','SAN FRANCISCO CITY','OXNARD',
            'L.A. MISSION','MENDOCINO','SANTA MONICA','CHABOT','CHAFFEY','SAN JOSE CITY','EAST L.A.',
            'MODESTO','ANTELOPE VALLEY','SAN FRANCISCO CTRS','SANTIAGO CANYON','CITRUS','GLENDALE',
            'VICTOR VALLEY','PALO VERDE','SADDLEBACK','CONTRA COSTA','FOOTHILL')
            then case fc.first_cb21_level
                     when 'B' then 'A'
                     else fc.first_cb21_level
                 end
        -- Colleges that collapse E/F into F.
        when fc.first_college_name in (
            'DIABLO VALLEY','BARSTOW','MORENO VALLEY','GOLDEN WEST','RIO HONDO','FRESNO CITY',
            'NORCO','MISSION','RIVERSIDE','SIERRA')
            then case fc.first_cb21_level
                     when 'E' then 'F'
                     else fc.first_cb21_level
                 end
        else fc.first_cb21_level
    end as first_cb21_level_adjusted

from students s
left join first_enrollment    fe  on s.uuid = fe.student_uuid
left join first_esl           fes on s.uuid = fes.student_uuid
left join sample              smp on s.uuid = smp.student_uuid
left join cohort_terms        ct  on s.uuid = ct.student_uuid
left join first_term_courses  ftc on s.uuid = ftc.student_uuid
left join esl_ever            ee  on s.uuid = ee.student_uuid
left join esl_noncredit_after_174 na on s.uuid = na.student_uuid
left join term_windows        tw  on s.uuid = tw.student_uuid
left join completers_bf       cbf on s.uuid = cbf.student_uuid
left join first_cb21          fc  on s.uuid = fc.student_uuid
