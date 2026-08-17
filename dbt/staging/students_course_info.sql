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
                --record for noncredit esl courses that are not coded 'Y' (unspecified level). if not, then record null
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
            end as any_493087_course_enrollment, 
            case 
                when
                    {{ classify_college("min(coll.college_name)") }} = 'CONFIRMED CC - A/B' then 'A'
                when {{ classify_college("min(coll.college_name)") }} = 'CONFIRMED CC - E/F' then 'E'
                when {{ classify_college("min(coll.college_name)") }} = 'CONFIRMED CC - 6 LEVELS' then '6'
                when {{ classify_college("min(coll.college_name)") }} = 'POSSIBLE CC' then 'P'
                else 'O'
            end as college_group_enrollment


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
        join 
            {{ source("caep_data", "sr1318colldist") }} coll
            on e.gi01 = coll.gi01_college
        where
            e.gi03 > 174
            and e.gi03 < 300  -- only include terms in the study window, up to 2030
            and e.sx02 = '19080808'  -- didn't drop
        group by e.student_uuid, e.gi03, coll.college_name
    ),
        cross_join_absolute as (
        select
            uuid,
            ('20'||left(gi03::text, 2)||term.quarter)::int as term,
            gi03
    from "postgres"."caep_analytics"."terms_adjusted" term
    cross join students s
    where term.gi03 > 174 and term.gi03 < 300
    ),
    per_term_absolute as (
        select
            uuid,
            term2.term,
            case when max(per_term_info.lowest_cb21_level_adjusted_rws) is null then '-' else max(per_term_info.lowest_cb21_level_adjusted_rws) end as lowest_cb21_level_adjusted_rws_abs,
            case when max(per_term_info.lowest_cb21_level_adjusted_all) is null then '-' else max(per_term_info.lowest_cb21_level_adjusted_all) end as lowest_cb21_level_adjusted_all_abs,
            case when max(per_term_info.lowest_cb21_level_adjusted_all_credit_types) is null then '-' else max(per_term_info.lowest_cb21_level_adjusted_all_credit_types) end as lowest_cb21_level_adjusted_all_credit_types_abs,
            case when max(per_term_info.lowest_cb21_level_adjusted_a_f_only_collapsed) is null then '-' else max(per_term_info.lowest_cb21_level_adjusted_a_f_only_collapsed) end as lowest_cb21_level_adjusted_a_f_only_collapsed_abs,
            case when max(per_term_info.lowest_cb21_level_adjusted_a_f_only_others_0) is null then '-' else max(per_term_info.lowest_cb21_level_adjusted_a_f_only_others_0) end as lowest_cb21_level_adjusted_a_f_only_others_0_abs,
            case when min(per_term_info.highest_cb21_level_adjusted_achieved_rws) is null then '-' else min(per_term_info.highest_cb21_level_adjusted_achieved_rws) end as highest_cb21_level_adjusted_achieved_rws_abs,
            case when min(per_term_info.highest_cb21_level_adjusted_achieved_all) is null then '-' else min(per_term_info.highest_cb21_level_adjusted_achieved_all) end as highest_cb21_level_adjusted_achieved_all_abs,
            case when min(per_term_info.highest_cb21_level_adjusted_achieved_crnc) is null then '-' else min(per_term_info.highest_cb21_level_adjusted_achieved_crnc) end as highest_cb21_level_adjusted_achieved_crnc_abs,
            case when bool_or(per_term_info.any_esl_enrollment::boolean) is null then '-' else bool_or(per_term_info.any_esl_enrollment::boolean)::integer::text end as any_esl_enrollment_abs,
            case when bool_or(per_term_info.any_noncredit_esl_enrollment::boolean) is null then '-' else bool_or(per_term_info.any_noncredit_esl_enrollment::boolean)::integer::text end as any_noncredit_esl_enrollment_abs,
            case when bool_or(per_term_info.any_credit_esl_enrollment::boolean) is null then '-' else bool_or(per_term_info.any_credit_esl_enrollment::boolean)::integer::text end as any_credit_esl_enrollment_abs,
            case when bool_or(per_term_info.any_both_esl_enrollment::boolean) is null then '-' else bool_or(per_term_info.any_both_esl_enrollment::boolean)::integer::text end as any_both_esl_enrollment_abs,
            case when bool_or(per_term_info.any_493084_course_enrollment::boolean) is null then '-' else bool_or(per_term_info.any_493084_course_enrollment::boolean)::integer::text end as any_493084_course_enrollment_abs,
            case when bool_or(per_term_info.any_493085_course_enrollment::boolean) is null then '-' else bool_or(per_term_info.any_493085_course_enrollment::boolean)::integer::text
            end as any_493085_course_enrollment_abs,
            case when bool_or(per_term_info.any_493086_course_enrollment::boolean) is null then '-' else bool_or(per_term_info.any_493086_course_enrollment::boolean)::integer::text end as any_493086_course_enrollment_abs,
            case when bool_or(per_term_info.any_493087_course_enrollment::boolean) is null then '-' else bool_or(per_term_info.any_493087_course_enrollment::boolean)::integer::text end as any_493087_course_enrollment_abs
    from cross_join_absolute term2 
    full outer join per_term_info on per_term_info.term = term2.gi03 and per_term_info.student_uuid = term2.uuid
    where term2.gi03 > 174 and term2.gi03 < 300
    group by uuid, term2.term
    ),
    -- term_in_6 / term_in_12 (console_2.sql): the latest term a student attended
    -- within the 6-term (3yr) and 12-term (6yr) windows after their first term.
    -- The FALL/SPRING window boundaries mirror the source arithmetic exactly.
    term_bounds as (

        select
            s.uuid as student_uuid,
            s.first_esl_term,
            case
                when left(s.first_esl_term::text, 2) = substr(term.year, 2, 2)  -- fall cohort
                then ((s.first_esl_term / 10) * 10) + 30 + 8
                else ((s.first_esl_term / 10) * 10) + 30 + 4  -- spring cohort
            end as latest_6_term,
            case
                when left(s.first_esl_term::text, 2) = substr(term.year, 2, 2)
                then ((s.first_esl_term / 10) * 10) + 60 + 8
                else ((s.first_esl_term / 10) * 10) + 60 + 4
            end as latest_12_term
        from students s
        join
            {{ ref('terms_adjusted') }} term
            on s.first_esl_term = term.gi03
    ),

    term_windows as (

        select
            tb.student_uuid,
            max(pti.term) filter (
                where pti.term between tb.first_esl_term + 1 and tb.latest_6_term
            ) as term_in_6,
            max(pti.term) filter (
                where pti.term between tb.latest_6_term + 1 and tb.latest_12_term
            ) as term_in_12
        from term_bounds tb
        join
            per_term_info pti
            on tb.student_uuid = pti.student_uuid
        group by tb.student_uuid

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
            {{ stringify('p','any_493087_course_enrollment') }}, 
            {{ stringify('p','college_group_enrollment') }}


        from students s
        left join per_term_info p on s.uuid = p.student_uuid
        group by s.uuid
    ),
    student_codes_absolute as (
        select abs.uuid as sca_uuid,
        {{ stringify('abs','any_esl_enrollment_abs') }},
        {{ stringify('abs','any_noncredit_esl_enrollment_abs') }},
        {{ stringify('abs','any_credit_esl_enrollment_abs') }},
        {{ stringify('abs','any_both_esl_enrollment_abs') }},
        {{ stringify('abs','lowest_cb21_level_adjusted_rws_abs') }},
        {{ stringify('abs','lowest_cb21_level_adjusted_all_abs') }},
        {{ stringify('abs','lowest_cb21_level_adjusted_a_f_only_collapsed_abs') }},
        {{ stringify('abs','lowest_cb21_level_adjusted_a_f_only_others_0_abs') }},
        {{ stringify('abs','lowest_cb21_level_adjusted_all_credit_types_abs') }},
        {{ stringify('abs','highest_cb21_level_adjusted_achieved_rws_abs') }},
        {{ stringify('abs','highest_cb21_level_adjusted_achieved_all_abs') }},
        {# {{ stringify('abs','highest_cb21_level_adjusted_achieved_crnc_abs') }}, #}
        {{ stringify('abs','any_493084_course_enrollment_abs') }},
        {{ stringify('abs','any_493085_course_enrollment_abs') }},
        {{ stringify('abs','any_493086_course_enrollment_abs') }},
        {{ stringify('abs','any_493087_course_enrollment_abs') }}
        from per_term_absolute abs
        group by abs.uuid
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
    sc.any_493087_course_enrollment_by_terms,
    sc.college_group_enrollment_by_terms,
    tw.term_in_6,
    tw.term_in_12,
    sca.*
from students s
join student_codes sc on sc.uuid = s.uuid
join term_windows tw on s.uuid = tw.student_uuid
join student_codes_absolute sca on s.uuid = sca.sca_uuid