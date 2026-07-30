{{ config(materialized="table") }}


with
    students as (
        select *
        from {{ ref("students_cohort_info") }}
        where first_term_enrolled between 175 and 234 and first_esl_term is not null
    ),

    {# CB21 noncredit only A-F (adjusted depending on campus), 0 = not enrolled in noncredit ESL course, Y, G, H recorded as is ) for ONLY three topcodes (not ESL integrated)
Any ESL enrollment per semester (1 for enrolled, 0 for not enrolled)
Any noncredit ESL enrollment per semester (1 for noncredit, 0 for not enrolled IN NONCREDIT)
Any credit ESL enrollment per semester (1 for credit, 0 for not enrolled IN CREDIT (note: a student could have 1 values for both semesters for noncredit + credit variable))
Any both ESL enrollment per semester (1 for credit, 0 for not enrolled IN BOTH) #}
    per_term_info as (
        select
            e.student_uuid,
            e.gi03 as term,
            cast(bool_or(c.is_esl_course::bool) as int) as any_esl_enrollment,
            cast(bool_or(c.is_noncredit_esl_course::bool and e.sx04 not in ('W', 'FW', 'DR')) as int) as any_noncredit_esl_enrollment,
            cast(bool_or(c.is_credit_esl_course::bool and e.sx04 not in ('W', 'FW', 'DR')) as int) as any_credit_esl_enrollment,
            cast(bool_or(
                c.is_noncredit_esl_course::bool and c.is_credit_esl_course::bool and e.sx04 not in ('W', 'FW', 'DR')
            ) as int) as any_both_esl_enrollment,
            -- only record for noncredit esl courses that are not integrated and are
            -- not incorrectly labeled Y level courses
            max(
                case
                --record for noncredit esl courses that are not integrated. if not, then record null
                    when c.is_noncredit_esl_course::bool and c.cb03 != '493087' and e.sx04 not in ('W', 'FW', 'DR')
                    then case when c.esl_course_level_adjusted_for_college in ('Y') then '1'
                    else c.esl_course_level_adjusted_for_college end
                    else '0'
                end
            ) as lowest_cb21_level_adjusted_rws,
            max(
                case
                    when c.is_noncredit_esl_course::bool and e.sx04 not in ('W', 'FW', 'DR')
                    then case when c.esl_course_level_adjusted_for_college in ('Y') then '1'
                    else c.esl_course_level_adjusted_for_college end
                    else '0'
                end
            ) as lowest_cb21_level_adjusted_all,
            max(
                case
                    when c.is_esl_course::bool and e.sx04 not in ('W', 'FW', 'DR')
                    then case when c.esl_course_level_adjusted_for_college in ('Y') then '1'
                    else c.esl_course_level_adjusted_for_college end
                    else '0'
                end
            ) as lowest_cb21_level_adjusted_all_credit_types,
            max(
                case
                    when c.is_noncredit_esl_course::bool and e.sx04 not in ('W', 'FW', 'DR')
                    then 
                        case 
                        when c.esl_course_level_adjusted_for_college in ('Y') then '1'
                        when c.esl_course_level_adjusted_for_college in ('G', 'H') then 'F'
                        else c.esl_course_level_adjusted_for_college
                        end
                    else '0'
                end
            ) as lowest_cb21_level_adjusted_a_f_only_collapsed,
            max(
                case
                    when c.is_noncredit_esl_course::bool and e.sx04 not in ('W', 'FW', 'DR')
                    then 
                        case 
                            when c.esl_course_level_adjusted_for_college in ('Y') then '1'
                            when c.esl_course_level_adjusted_for_college in ('G', 'H') then '0'
                            else c.esl_course_level_adjusted_for_college
                        end
                    else '0'
                end
            ) as lowest_cb21_level_adjusted_a_f_only_others_0,
            min(
                case
                --record for noncredit esl courses that are not integrated. if not, then record null
                    when c.is_noncredit_esl_course::bool and c.cb03 != '493087' and e.sx04 not in ('W', 'NP', 'INP', 'FW', 'DR', 'F')  -- didn't fail/drop
                    then case when c.esl_course_level_adjusted_for_college in ('Y') then null
                    else c.esl_course_level_adjusted_for_college end
                    else '0'
                end
            ) as highest_cb21_level_adjusted_achieved_rws,
            min(
                case
                --record for noncredit esl courses that are not integrated. if not, then record null
                    when c.is_noncredit_esl_course::bool and e.sx04 not in ('W', 'NP', 'INP', 'FW', 'DR', 'F')  -- didn't fail/drop
                    then case when c.esl_course_level_adjusted_for_college in ('Y') then null
                    else c.esl_course_level_adjusted_for_college end
                    else '0'
                end
            ) as highest_cb21_level_adjusted_achieved_all,
            min(
                case
                --record for noncredit esl courses that are not integrated. if not, then record null
                    when c.is_esl_course::bool and e.sx04 not in ('W', 'NP', 'INP', 'FW', 'DR', 'F')  -- didn't fail/drop
                    then case when c.esl_course_level_adjusted_for_college in ('Y') then null
                    else c.esl_course_level_adjusted_for_college end
                    else '0'
                end
            ) as highest_cb21_level_adjusted_achieved_crnc,
            case 
                when bool_or(c.cb03 = '493084' and e.sx04 not in ('W', 'FW', 'DR')) then 1 else 0
            end as any_493084_course_enrollment,
            case 
                when bool_or(c.cb03 = '493085' and e.sx04 not in ('W', 'FW', 'DR')) then 1 else 0
            end as any_493085_course_enrollment,
            case 
                when bool_or(c.cb03 = '493086' and e.sx04 not in ('W', 'FW', 'DR')) then 1 else 0
            end as any_493086_course_enrollment,
            case 
                when bool_or(c.cb03 = '493087' and e.sx04 not in ('W', 'FW', 'DR')) then 1 else 0
            end as any_493087_course_enrollment


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
        where
            e.gi03 > 174
            and e.gi03 < 300  -- only include terms in the study window, up to 2030
            and e.sx02 = '19080808'  -- didn't drop
        group by e.student_uuid, e.gi03
    ),
    student_codes as (
        select
            s.uuid,
            {{ stringify('p','any_esl_enrollment') }}, 
            {{ stringify('p','any_noncredit_esl_enrollment') }}, 
            {{ stringify('p','any_credit_esl_enrollment') }},
            {{ stringify('p','any_both_esl_enrollment') }},
            {{ stringify('p','lowest_cb21_level_adjusted_rws')}}, 
            {{ stringify('p','lowest_cb21_level_adjusted_all') }},
            {{ stringify('p','lowest_cb21_level_adjusted_a_f_only_collapsed') }},
            {{ stringify('p','lowest_cb21_level_adjusted_a_f_only_others_0') }},
            {{ stringify('p','lowest_cb21_level_adjusted_all_credit_types') }},
            {{ stringify('p','highest_cb21_level_adjusted_achieved_rws') }},
            {{ stringify('p','highest_cb21_level_adjusted_achieved_all') }},
            {# {{ stringify('p','highest_cb21_level_adjusted_achieved_crnc') }}, #}
            {{ stringify('p','any_493084_course_enrollment') }},
            {{ stringify('p','any_493085_course_enrollment') }},
            {{ stringify('p','any_493086_course_enrollment') }},
            {{ stringify('p','any_493087_course_enrollment') }}


        from students s
        left join per_term_info p on s.uuid = p.student_uuid
        group by s.uuid
    )
-- add fields to existing fields
select
    s.*,
    sc.any_esl_enrollment_by_terms,
    sc.any_noncredit_esl_enrollment_by_terms,
    sc.any_credit_esl_enrollment_by_terms,
    sc.any_both_esl_enrollment_by_terms,
    sc.lowest_cb21_level_adjusted_rws_by_terms, 
    sc.lowest_cb21_level_adjusted_all_by_terms,
    sc.lowest_cb21_level_adjusted_all_credit_types_by_terms,
    sc.lowest_cb21_level_adjusted_a_f_only_collapsed_by_terms,
    sc.lowest_cb21_level_adjusted_a_f_only_others_0_by_terms,
    sc.highest_cb21_level_adjusted_achieved_rws_by_terms,
    sc.highest_cb21_level_adjusted_achieved_all_by_terms,
    {# sc.highest_cb21_level_adjusted_achieved_crnc_by_terms, #}
    sc.any_493084_course_enrollment_by_terms,
    sc.any_493085_course_enrollment_by_terms,
    sc.any_493086_course_enrollment_by_terms,
    sc.any_493087_course_enrollment_by_terms
from student_codes sc
join students s on sc.uuid = s.uuid