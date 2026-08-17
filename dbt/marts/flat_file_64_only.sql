{{ config(materialized='table', alias='flat_file_64_only_' ~ run_started_at.strftime('%Y%m%d')) }}

select *, (
    multiple_colleges and
                                                              (college_group_enrollment_by_terms similar to '%O+' OR
                                                               college_group_enrollment_by_terms SIMILAR TO '%P+')
) as non_64_college_enrollment,
--cohort is long enough for 6 years observation based on 264 max gi03
--check: count backward on sem_abs file
(first_esl_term between 175 and 251) as observation_6_sem,
(first_esl_term between 175 and 235) as observation_12_sem
from {{ ref('students_course_info') }}
where first_college_group IN ('CONFIRMED CC - 6 LEVELS', 'CONFIRMED CC - A/B', 'CONFIRMED CC - E/F')