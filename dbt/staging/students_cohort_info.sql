{{ config(materialized="table") }}

-- students_cohort_info: cohort / sample / starting-point attributes, one row per
-- student, layered onto students_degree_info. This is the final model in the
-- chain, so it is the complete students table.
--
-- Source logic: "building sample.sql", "console_2.sql", and the CB21 sections of
-- "pathways_calculations.sql". Core fields recorded here:
-- * first term enrolled / first ESL term
-- * which sample  (in_sample, first_academic_year, cohort)
-- * first campus  (first_college_name)
-- * first course type  (noncredit / credit-only / both)
-- * first CB21 level, and the college-adjusted version
--
-- The four ESL program codes ('493084','493085','493086','493087') identify ESL
-- courses throughout, matching the source SQL.
with
    students as (select * from {{ ref("students_degree_info") }}),

    first_recorded_enrollment as (
        select
            s.uuid,
            case
                when min(sx.gi03) < 700
                then min(sx.gi03)  -- 2000s enrollment
                else min(sx.gi03) filter (where sx.gi03 between 300 and 999)  -- 1900s enrollment
            end as first_term_enrollment_any,
            -- catch cases where they had an early enrollment term, but they dropped
            -- all their classes--this will be later than first term
            case
                when
                    min(sx.gi03) filter (
                        where
                            sx.gi03 < 700
                            and sx.sx02 = '19080808'
                            and sx.sx04 not in ('W', 'FW', 'DR')
                    )
                    < 700
                then
                    min(sx.gi03) filter (
                        where
                            sx.gi03 < 700
                            and sx.sx02 = '19080808'
                            and sx.sx04 not in ('W', 'FW', 'DR')
                    )  -- 2000s enrollment
                else
                    min(sx.gi03) filter (
                        where
                            sx.gi03 between 300 and 999
                            and sx.sx02 = '19080808'
                            and sx.sx04 not in ('W', 'FW', 'DR')
                    )  -- 1900s enrollment
            end as first_term_enrollment_finished_term
        from students s
        join {{ source('caep_data', 'sr1318sx') }} sx on s.maskedsb00 = sx.maskedsb00
        group by s.uuid
    ),
    all_first_terms as (
        select
            fe.first_term_enrollment_any,
            fe.first_term_enrollment_finished_term,
            min(hf.ccc_first_term) as hf,
            min(sb.scd1) as scd1_val,
            s.uuid
        from students s
        join first_recorded_enrollment fe on s.uuid = fe.uuid
        join {{ source('caep_data', 'sr1318hf') }} hf on s.maskedsb00 = hf.maskedsb00
        join {{ source('caep_data', 'sr1318sb') }} sb on s.maskedsb00 = sb.maskedsb00
        group by
            s.uuid, fe.first_term_enrollment_any, fe.first_term_enrollment_finished_term
    ),

    -- where is the enrollment record incorrect?
    first_term_enrollment as (
        select
            s.uuid as student_uuid,
            case
                when
                    left(least(first_term_enrollment_any, hf, scd1_val)::varchar, 2)
                    = left(first_term_enrollment_any::varchar, 2)
                    and first_term_enrollment_any = first_term_enrollment_finished_term
                then first_term_enrollment_any  -- ignore a slightly wrong recorded first term from non-sx sources
                when
                    left(least(first_term_enrollment_any, hf, scd1_val)::varchar, 2)
                    = left(first_term_enrollment_any::varchar, 2)
                    and first_term_enrollment_any != first_term_enrollment_finished_term
                then first_term_enrollment_finished_term  -- ignore a slightly wrong recorded first term from non-sx sources, AND don't use that term if they didn't actually finish
                else least(first_term_enrollment_any, hf, scd1_val)
            end as first_term_enrollment,
            first_term_enrollment_any,
            hf,
            scd1_val
        from all_first_terms
        join students s on s.uuid = all_first_terms.uuid
    ),

    -- First term the student took an ESL course (this is what the cohort is keyed on).
    first_esl as (

        select
            sx.student_uuid,
            case
                --if the greatest term is in the 2000s (i.e. no 1900s enrollment), then return the lowest term from the 2000s.
                when max(sx.gi03) < 270
                then min(sx.gi03)
                --if the first term is above 270 (i.e. could be from 1928 or above), then return the lowest term from 270 to 999 (i.e. 1928 or above). Real data starts in the 1970s, but this covers the complete range in the case statement. 
                else min(sx.gi03) filter (where sx.gi03 between 270 and 999)
            end as first_esl_term, 
            mode() within group (order by coll.college_name) as first_college_name,
            case when min(cb.cb03) = '493087' then true else false end as first_term_integrated_esl_course
        from {{ source("caep_data", "sr1318sx") }} sx
        join
            {{ source("caep_data", "sr1318cb") }} cb
            on sx.cb00 = cb.cb00
            and cb.gi03 = sx.gi03
        join {{ source("caep_data", "sr1318colldist") }} coll on sx.gi01 = coll.gi01_college
        where
            cb.cb03 in ('493084', '493085', '493086', '493087')
            and sx.sx02 = '19080808'  -- didn't drop
            and sx.sx04 not in ('W', 'FW', 'DR')  -- didn't withdraw
        group by sx.student_uuid

    ),

    -- Cohort: half-year buckets keyed on the first ESL term.
    cohort_terms as (

        select
            fe.student_uuid,
            term.year as first_academic_year,
            case
                when
                    trim(term.term) in (
                        'SUMMER TERM',
                        'SUMMER QUARTER',
                        'FALL SEMESTER',
                        'FALL QUARTER',
                        'ANNUAL'
                    )
                then 'F'
                when
                    trim(term.term) in (
                        'WINTER INTERSESSION',
                        'WINTER QUARTER',
                        'SPRING SEMESTER',
                        'SPRING QUARTER'
                    )
                then 'S'
            end as cohort
        from first_esl fe
        join
            {{ source("caep_data", "sr1318term") }} term
            on fe.first_esl_term = term.gi03
        group by fe.student_uuid, cohort, first_academic_year
    ),

    -- Credit / non-credit ESL profile across the whole study window.
    esl_ever as (

        select
            sx.student_uuid,
            bool_or(cb.cb04 in ('D', 'C')) as ever_credit_esl,
            bool_and(cb.cb04 = 'N') as always_noncredit_esl,
            bool_and(cb.cb04 in ('C', 'D')) as always_credit_esl
        from {{ source("caep_data", "sr1318sx") }} sx
        join
            {{ source("caep_data", "sr1318cb") }} cb
            on sx.gi03 = cb.gi03
            and sx.cb00 = cb.cb00
        where
            cb.cb03 in ('493084', '493085', '493086', '493087')
            and sx.sx04 not in ('W', 'FW', 'DR')
            and sx.sx02 = '19080808'

        group by sx.student_uuid

    ),

    -- First course type: what ESL course(s) did the student take in their first term?
    first_term_courses as (

        select
            sx.student_uuid,
            bool_or(cb.cb04 = 'N') as first_term_noncredit,
            bool_and(cb.cb04 != 'N') as first_term_credit_only,
            (
                bool_or(cb.cb04 = 'N') and bool_or(cb.cb04 in ('D', 'C'))
            ) as first_term_credit_and_noncredit
        from {{ source("caep_data", "sr1318sx") }} sx
        join
            first_esl fe
            on sx.student_uuid = fe.student_uuid
            and sx.gi03 = fe.first_esl_term
        join
            {{ source("caep_data", "sr1318cb") }} cb
            on sx.gi03 = cb.gi03
            and cb.cb00 = sx.cb00
        where
            cb.cb03 in ('493084', '493085', '493086', '493087')
            and fe.first_esl_term is not null
            and sx.sx02 = '19080808'  -- didn't drop
            and sx.sx04 not in ('W', 'FW', 'DR')  -- didn't withdraw/drop
        group by sx.student_uuid
    ),

    -- First CB21 level (from pathways_calculations.sql "reassign first level"):
    -- rank each student's ESL terms, take term 1, find the lowest starting level
    -- (max levels_below_transfer) among their non-credit ESL courses, and map it
    -- back to a CB21 letter. Also carries the college where that first term happened.
    esl_terms_ranked as (

        select distinct
            sx.student_uuid,
            dense_rank() over (
                partition by sx.student_uuid order by sx.gi03 asc
            ) as term_number,
            m.levels_below_transfer,
            coll.college_name
        from {{ source("caep_data", "sr1318sx") }} sx
        join
            {{ source("caep_data", "sr1318cb") }} cb
            on sx.cb00 = cb.cb00
            and sx.gi03 = cb.gi03
            and sx.gi01 = cb.gi01
        join {{ source("caep_data", "sr1318term") }} term on sx.gi03 = term.gi03
        join
            {{ source("caep_data", "sr1318colldist") }} coll
            on sx.gi01 = coll.gi01_college
        join {{ source("caep_data", "course_efl_score_mapping") }} m on cb.cb21 = m.cb21
        join first_esl fe on sx.student_uuid = fe.student_uuid and sx.gi03 >= fe.first_esl_term
        where
            sx.gi03 > 174 and sx.gi03 < 300  -- only include terms in the study window, up to 2030
            and sx.sx02 = '19080808'  -- didn't drop
            and sx.sx04 not in ('W', 'NP', 'INP', 'FW', 'DR', 'F')  -- didn't fail/drop
            and fe.first_esl_term is not null
            and cb.cb03 in ('493084', '493085', '493086', '493087') 
            and cb.cb04 = 'N'

    ),
    -- find actual lowest level
    first_term_level as (

        select
            student_uuid,
            max(levels_below_transfer) as lowest_starting_level
        from esl_terms_ranked
        where term_number = 1
        group by student_uuid

    ),
    -- convert level to CB21 for readability
    first_cb21 as (

        select f.student_uuid, m.cb21 as first_cb21_level
        from first_term_level f
        join
            {{ source("caep_data", "course_efl_score_mapping") }} m
            on f.lowest_starting_level = m.levels_below_transfer

    ),

    first_term_level_credit_only as (
        select
            sx.student_uuid,
            max(m.levels_below_transfer) filter (
                where sx.gi03 = fe.first_esl_term
            ) as lowest_starting_level_credit_only
        from {{ source("caep_data", "sr1318sx") }} sx
        join first_esl fe on sx.student_uuid = fe.student_uuid
        join
            {{ source("caep_data", "sr1318cb") }} cb
            on sx.gi03 = cb.gi03
            and cb.cb00 = sx.cb00
        join {{ source("caep_data", "course_efl_score_mapping") }} m on cb.cb21 = m.cb21
        where
            cb.cb03 in ('493084', '493085', '493086', '493087') 
            and sx.sx02 = '19080808'  -- didn't drop
            and sx.sx04 not in ('W', 'NP', 'INP', 'FW', 'DR', 'F')  -- didn't fail/drop
        group by sx.student_uuid
        having bool_and(cb.cb04 != 'N')  -- only return for credit-only students
    ),
    first_term_cb21_credit_only as (
        select f.student_uuid, m.cb21 as first_cb21_level_credit_only
        from first_term_level_credit_only f
        join
            {{ source("caep_data", "course_efl_score_mapping") }} m
            on f.lowest_starting_level_credit_only = m.levels_below_transfer
    ),

    -- both_credit_noncredit_esl: among students who ever took credit ESL, did they
    -- also take a non-credit ESL course (after term 175)? (console_2.sql)
    esl_noncredit_after_174 as (

        select sx.student_uuid, bool_or(cb.cb04 = 'N') as took_noncredit_after_174
        from {{ source("caep_data", "sr1318sx") }} sx
        join
            {{ source("caep_data", "sr1318cb") }} cb
            on sx.gi03 = cb.gi03
            and sx.cb00 = cb.cb00
        where
            sx.gi03 > 174
            and cb.cb03 in ('493084', '493085', '493086', '493087')
            and sx.sx02 = '19080808'  -- didn't drop
            and sx.sx04 not in ('W', 'NP', 'INP', 'FW', 'DR', 'F')  -- didn't fail/drop
        group by sx.student_uuid

    ),

    -- term_in_6 / term_in_12 (console_2.sql): the latest term a student attended
    -- within the 6-term (3yr) and 12-term (6yr) windows after their first term.
    -- The FALL/SPRING window boundaries mirror the source arithmetic exactly.
    term_bounds as (

        select
            fe.student_uuid,
            fe.first_esl_term,
            case
                when left(fe.first_esl_term::text, 2) = substr(term.year, 2, 2)  -- fall cohort
                then ((fe.first_esl_term / 10) * 10) + 30 + 8
                else ((fe.first_esl_term / 10) * 10) + 30 + 4  -- spring cohort
            end as latest_6_term,
            case
                when left(fe.first_esl_term::text, 2) = substr(term.year, 2, 2)
                then ((fe.first_esl_term / 10) * 10) + 60 + 8
                else ((fe.first_esl_term / 10) * 10) + 60 + 4
            end as latest_12_term
        from first_esl fe
        join
            {{ source("caep_data", "sr1318term") }} term
            on fe.first_esl_term = term.gi03
        where fe.first_esl_term is not null

    ),

    term_windows as (

        select
            tb.student_uuid,
            max(sx.gi03) filter (
                where sx.gi03 between tb.first_esl_term + 1 and tb.latest_6_term
            ) as term_in_6,
            max(sx.gi03) filter (
                where sx.gi03 between tb.latest_6_term + 1 and tb.latest_12_term
            ) as term_in_12
        from term_bounds tb
        join
            {{ source("caep_data", "sr1318sx") }} sx
            on tb.student_uuid = sx.student_uuid
        group by tb.student_uuid

    ),

    -- "B/F to A" full-completion metric (pathways_calculations.sql): using the
    -- college-adjusted CB21 level, the first term a student reaches level 1 (A),
    -- and how many levels below they started from.
    esl_terms_adjusted as (

        select distinct
            sx.student_uuid,
            dense_rank() over (
                partition by sx.student_uuid order by sx.gi03 asc
            ) as term_number,
            cb.cb03,
            case
                when
                    coll.college_name in (
                        'COMPTON',
                        'SANTA ANA',
                        'CUESTA',
                        'SEQUOIAS',
                        'YUBA',
                        'SAN FRANCISCO CITY',
                        'OXNARD',
                        'L.A. MISSION',
                        'MENDOCINO',
                        'SANTA MONICA',
                        'CHABOT',
                        'CHAFFEY',
                        'SAN JOSE CITY',
                        'EAST L.A.',
                        'MODESTO',
                        'ANTELOPE VALLEY',
                        'SAN FRANCISCO CTRS',
                        'SANTIAGO CANYON',
                        'CITRUS',
                        'GLENDALE',
                        'VICTOR VALLEY',
                        'PALO VERDE',
                        'SADDLEBACK',
                        'CONTRA COSTA',
                        'FOOTHILL'
                    )
                then case when cb.cb21 = 'B' then 'A' else cb.cb21 end
                when
                    coll.college_name in (
                        'DIABLO VALLEY',
                        'BARSTOW',
                        'MORENO VALLEY',
                        'GOLDEN WEST',
                        'RIO HONDO',
                        'FRESNO CITY',
                        'NORCO',
                        'MISSION',
                        'RIVERSIDE',
                        'SIERRA'
                    )
                then case when cb.cb21 = 'E' then 'F' else cb.cb21 end
                else cb.cb21
            end as cb21_adjusted,
            coll.college_name as college_name_adj
        from {{ source("caep_data", "sr1318sx") }} sx
        join
            {{ source("caep_data", "sr1318cb") }} cb
            on sx.cb00 = cb.cb00
            and sx.gi03 = cb.gi03
            and sx.gi01 = cb.gi01
        join {{ source("caep_data", "sr1318term") }} term on sx.gi03 = term.gi03
        join
            {{ source("caep_data", "sr1318colldist") }} coll
            on sx.gi01 = coll.gi01_college
        where
            sx.gi03 between 175 and 300
            and sx.sx02 = '19080808'
            and sx.sx04 not in ('W', 'NP', 'INP', 'FW', 'DR', 'F')
            and cb.cb03 in ('493084', '493085', '493086', '493087')
            and cb.cb04 = 'N'
    ),

    term_data_adj as (

        select distinct
            eta.student_uuid,
            eta.term_number,
            --for lowest starting level, if all courses are 493087, return that level. otherwise, return the lowest starting level excluding 493087
            first_value(
            CASE 
                WHEN (max(m.levels_below_transfer) filter (where cb03 != '493087')) is null
                THEN max(m.levels_below_transfer)
                ELSE (max(m.levels_below_transfer) filter (where cb03 != '493087')) 
            END)
             over (
                partition by eta.student_uuid order by eta.term_number
            ) as lowest_starting_level,  
            CASE 
                WHEN (min(m.levels_below_transfer) filter (where cb03 != '493087')) is null
                THEN min(m.levels_below_transfer)
                ELSE (min(m.levels_below_transfer) filter (where cb03 != '493087')) 
            END
             as max_level_in_term
        from esl_terms_adjusted eta
        join
            {{ source("caep_data", "course_efl_score_mapping") }} m
            on eta.cb21_adjusted = m.cb21
        group by eta.student_uuid, eta.term_number

    ),
    -- find the first level a student started at. we're not interested in integrated
    -- courses
    first_term_level_adj as (

        select
            student_uuid,
            -- return lowest starting level not including y, if all courses are y,
            -- return lowest starting level including y
            case
                when max(m.levels_below_transfer) filter (where cb21 != 'Y') is null
                then max(m.levels_below_transfer)
                else max(m.levels_below_transfer) filter (where cb21 != 'Y')
            end as lowest_starting_level
        from esl_terms_adjusted eta
        join
            {{ source("caep_data", "course_efl_score_mapping") }} m
            on eta.cb21_adjusted = m.cb21
        where term_number = 1 and cb03 != '493087'
        group by student_uuid

    ),
    first_cb21_adj as (

        select f.student_uuid, m.cb21 as first_cb21_level_adj
        from first_term_level_adj f
        join
            {{ source("caep_data", "course_efl_score_mapping") }} m
            on f.lowest_starting_level = m.levels_below_transfer

    ),

    completers_adj as (

        select
            student_uuid,
            min(term_number) as terms_to_full_completion_adj,
            (lowest_starting_level - 1) as full_completion_levels_adj
        from term_data_adj
        where max_level_in_term = 1
        group by student_uuid, lowest_starting_level

    )

select
    s.*,

    fte.first_term_enrollment as first_term_enrolled,
    fe.first_esl_term,

    -- which sample / cohort
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
    case
        when ee.ever_credit_esl then na.took_noncredit_after_174
    end as both_credit_noncredit_esl,

    -- attendance windows + "B/F to A" completion
    tw.term_in_6,
    tw.term_in_12,
    c_adj.terms_to_full_completion_adj,
    c_adj.full_completion_levels_adj,

    -- first campus + first CB21 level (raw and college-adjusted)
    fe.first_college_name,
    fe.first_term_integrated_esl_course,
    fc.first_cb21_level,
    fc_adj.first_cb21_level_adj,
    fc_co.first_cb21_level_credit_only,
    {{ classify_college("first_college_name") }} as first_college_group

from students s
left join first_term_enrollment fte on s.uuid = fte.student_uuid
left join first_esl fe on s.uuid = fe.student_uuid
left join cohort_terms ct on s.uuid = ct.student_uuid
left join first_term_courses ftc on s.uuid = ftc.student_uuid
left join esl_ever ee on s.uuid = ee.student_uuid
left join esl_noncredit_after_174 na on s.uuid = na.student_uuid
left join term_windows tw on s.uuid = tw.student_uuid
left join completers_adj c_adj on s.uuid = c_adj.student_uuid
left join first_cb21 fc on s.uuid = fc.student_uuid
left join first_cb21_adj fc_adj on s.uuid = fc_adj.student_uuid
left join first_term_cb21_credit_only fc_co on s.uuid = fc_co.student_uuid
