{{ config(materialized='table') }}

-- students: the identity spine. One row per student.
--
-- maskedsb00 is the natural key. `uuid` is the surrogate key that every raw sr*
-- table already references through its student_uuid column, so we take the
-- existing (maskedsb00, uuid) mapping from the source as-is rather than
-- regenerating it (regenerating would break every downstream join). All of the
-- *calculated* columns that used to live on this table are rebuilt by the
-- students_demographics / students_degree_info / students_cohort_info models
-- that layer on top of this one.

select
    maskedsb00,
    uuid
from {{ source('caep_data', 'students') }}
