{{ config(materialized='table') }}

WITH students AS (SELECT *
                  FROM {{ ref('students_course_info') }}
                  where first_college_group IN ('CONFIRMED CC - 6 LEVELS', 'CONFIRMED CC - A/B', 'CONFIRMED CC - E/F')
                  ),
     awards AS (SELECT s.*,
                        gen_random_uuid () as award_uuid,
                       sp.sp01                                                                                                  AS topcode,
                       top.top6title                                                                                            AS award_subject_title,
                       sp.sp02                                                                                                  AS award_code,
                       CASE
                           WHEN sp.sp02 = 'A' THEN 'Associate of Arts (A.A.) degree'
                           WHEN sp.sp02 = 'S' THEN 'Associate of Science (A.S.) degree'
                           WHEN sp.sp02 = 'Y' THEN 'Baccalaureate of Arts (B.A.) degree'
                           WHEN sp.sp02 = 'Z' THEN 'Baccalaureate of Science (B.S.) degree'
                           WHEN sp.sp02 IN ('E', 'B', 'N', 'L', 'Z','O') THEN 'Credit Certificate requiring fewer than 30 semester units'
                           WHEN sp.sp02 = 'T' THEN 'Credit Certificate requiring 30 to fewer than 60 semester units'
                           WHEN sp.sp02 = 'F' THEN 'Credit Certificate requiring 60 or more semester units'
                           WHEN sp.sp02 = 'G' THEN 'Noncredit award requiring fewer than 48 hours of direct instruction or directly
supervised activity'
                           WHEN sp.sp02 = 'H' THEN 'Noncredit award requiring from 48 to fewer than 96 hours of direct instruction or
directly supervised activity'
                           WHEN sp.sp02 = 'I' THEN 'Noncredit award requiring from 96 to fewer than 144 hours of direct instruction or
directly supervised activity'
                           WHEN sp.sp02 = 'J' THEN 'Noncredit award requiring from 144 to fewer than 192 hours of direct instruction or
directly supervised activity'
                           WHEN sp.sp02 = 'K' THEN 'Noncredit award requiring from 192 to fewer than 288 hours of direct instruction or
directly supervised activity'
                           WHEN sp.sp02 = 'P' THEN 'Noncredit award requiring from 288 to fewer than 480 hours of direct instruction or
directly supervised activity'
                           WHEN sp.sp02 = 'Q' THEN 'Noncredit award requiring from 480 to fewer than 960 hours of direct instruction or
directly supervised activity'
                           WHEN sp.sp02 = 'R' THEN 'Noncredit award requiring 960 hours or more of direct instruction or directly supervised
activity'
                           WHEN sp.sp02 = 'U' THEN 'Noncredit Adult Education High School Diploma'
                            ELSE 'Unknown'
                                END as award_description,
                               sp.gi03,
        to_date(sp.sp03::TEXT, 'YYYYMMDD') AS awarded_date
                FROM {{source('caep_data', 'sr1318sp')}}  sp
                         JOIN students s ON sp.student_uuid = s.uuid
                         JOIN caep_data.sr1318topcode top ON sp.sp01 = top.top6
                WHERE sp03 IS NOT NULL
                  AND gi03 >= 175),
    ranked as (
        select a.*, dense_rank() OVER (PARTITION BY a.uuid ORDER BY awarded_date ASC) as award_number from awards a
    )
    select * from ranked
