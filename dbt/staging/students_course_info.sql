{{ config(materialized="table") }}


with
    students as (select * from {{ ref("students_cohort_info") }}),

    {# CB21 noncredit only A-F (adjusted depending on campus), 0 = not enrolled in noncredit ESL course, Y, G, H recorded as is ) for ONLY three topcodes (not ESL integrated)
Any ESL enrollment per semester (1 for enrolled, 0 for not enrolled)
Any noncredit ESL enrollment per semester (1 for noncredit, 0 for not enrolled IN NONCREDIT)
Any credit ESL enrollment per semester (1 for credit, 0 for not enrolled IN CREDIT (note: a student could have 1 values for both semesters for noncredit + credit variable))
Any both ESL enrollment per semester (1 for credit, 0 for not enrolled IN BOTH) #}

    per_term_info as (
        select
            e.student_uuid,
            e.gi03 as term,
            bool_or(c.is_esl_course::bool) as any_esl_enrollment,
            bool_or(c.is_noncredit_esl_course::bool) as any_noncredit_esl_enrollment,
            bool_or(c.is_credit_esl_course::bool) as any_credit_esl_enrollment,
            bool_or(
                c.is_noncredit_esl_course::bool and c.is_credit_esl_course::bool
            ) as any_both_esl_enrollment,
            first_value(c.esl_course_level_adjusted_for_college) over (
                partition by e.student_uuid, e.gi03 order by csm.levels_below_transfer
            ) as first_cb21_level_adjusted_for_college
        -- cb21 level for each term, adjusted for college (A-F, G/H, Y, 0)
        -- any esl enrollment per term
        -- any noncredit esl enrollment per term
        -- any credit esl enrollment per term
        -- any both esl enrollment per term 
        from {{ source("caep_data", "sr1318sx") }} e
        join {{ ref("courses_cb21_adjusted") }} c on e.cb00 = c.cb00 and e.gi03 = c.term
        join
            {{ source("caep_data", "course_efl_score_mapping") }} csm
            on c.cb21 = csm.cb21
            and ((c.cb21 != 'Y' and c.cb04 = 'N') or (c.cb03 != '493087'))  -- don't code Y level noncredit courses or integrated ESL courses
        where e.gi03 > 174 AND e.gi03 < 300 -- only include terms in the study window, up to 2030
        and e.sx02 = '19080808'                -- didn't drop
      and e.sx04 not in ('W', 'FW', 'DR')  -- didn't withdraw/drop
        group by e.student_uuid, e.gi03, c.esl_course_level_adjusted_for_college, csm.levels_below_transfer
    ),
    student_codes as (
    select
        s.uuid,
        string_agg(p.any_esl_enrollment::int::varchar, '' order by p.term)
            as any_esl_enrollment_by_term,
        string_agg(p.any_noncredit_esl_enrollment::int::varchar, '' order by p.term)
            as any_noncredit_esl_enrollment_by_term,
        string_agg(p.any_credit_esl_enrollment::int::varchar, '' order by p.term)
            as any_credit_esl_enrollment_by_term,
        string_agg(p.any_both_esl_enrollment::int::varchar, '' order by p.term)
            as any_both_esl_enrollment_by_term,
        string_agg(p.first_cb21_level_adjusted_for_college, '' order by p.term)
            as first_cb21_level_adjusted_for_college_by_term
    from students s
    left join per_term_info p on s.uuid = p.student_uuid
    group by s.uuid
    )
-- add fields to existing fields
select s.*, sc.any_esl_enrollment_by_term, sc.any_noncredit_esl_enrollment_by_term, sc.any_credit_esl_enrollment_by_term, sc.any_both_esl_enrollment_by_term, sc.first_cb21_level_adjusted_for_college_by_term
from student_codes sc
join students s on sc.uuid = s.uuid
