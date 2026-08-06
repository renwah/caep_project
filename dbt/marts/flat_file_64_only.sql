{{ config(materialized='table', alias='flat_file_64_only_' ~ run_started_at.strftime('%Y%m%d')) }}

select *
from {{ ref('students_course_info') }}
where first_college_group IN ('CONFIRMED CC - 6 LEVELS', 'CONFIRMED CC - A/B', 'CONFIRMED CC - E/F')