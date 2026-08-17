{{ config(materialized='table', alias='flat_file_64_only_' ~ run_started_at.strftime('%Y%m%d')) }}

select *, (
    multiple_colleges and
                                                              (college_group_enrollment_by_terms similar to '%O+' OR
                                                               college_group_enrollment_by_terms SIMILAR TO '%P+')
) as non_64_college_enrollment
from {{ ref('students_course_info') }}
where first_college_group IN ('CONFIRMED CC - 6 LEVELS', 'CONFIRMED CC - A/B', 'CONFIRMED CC - E/F')