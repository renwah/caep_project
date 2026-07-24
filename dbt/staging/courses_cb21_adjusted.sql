{{ config(materialized="view") }}


with courses as (select * from {{ source("caep_data", "sr1318cb") }})

select
    c.gi03 as term,
    c.cb00,
    c.cb01,
    c.gi01,
    c.cb04,
    c.cb21,
    c.cb03,
    case
        when c.cb03 in ('493084', '493085', '493086', '493087') then true else false
    end as is_esl_course,
    case
        when c.cb03 in ('493084', '493085', '493086', '493087') and c.cb04 = 'N'
        then true
        else false
    end as is_noncredit_esl_course,
    case
        when c.cb03 in ('493084', '493085', '493086', '493087') and c.cb04 in ('C', 'D')
        then true
        else false
    end as is_credit_esl_course,
    case
        when c.cb03 in ('493084', '493085', '493086', '493087') and c.cb04 = 'N'
        then
            case
                when
                    c.gi01 in (
                        '141',
                        '291',
                        '311',
                        '361',
                        '363',
                        '422',
                        '472',
                        '482',
                        '561',
                        '592',
                        '621',
                        '641',
                        '682',
                        '711',
                        '731',
                        '743',
                        '748',
                        '781',
                        '821',
                        '871',
                        '873',
                        '891',
                        '921',
                        '951',
                        '991'
                    )
                then
                    -- combine a/b
                    case
                        when c.cb21 = 'A'
                        then 'A'
                        when c.cb21 = 'B'
                        then 'A'
                        when c.cb21 = 'C'
                        then 'C'
                        when c.cb21 = 'D'
                        then 'D'
                        when c.cb21 = 'E'
                        then 'E'
                        when c.cb21 = 'F'
                        then 'F'
                        when c.cb21 in ('Y', 'G', 'H')
                        then c.cb21
                    end
                when
                    c.gi01 in (
                        '271',
                        '312',
                        '492',
                        '571',
                        '832',
                        '881',
                        '911',
                        '961',
                        '962',
                        '963'
                    )
                then
                    -- combine e/f
                    case
                        when c.cb21 = 'A'
                        then 'A'
                        when c.cb21 = 'B'
                        then 'B'
                        when c.cb21 = 'C'
                        then 'C'
                        when c.cb21 = 'D'
                        then 'D'
                        when c.cb21 = 'E'
                        then 'F'  -- TODO: not sure what to do here
                        when c.cb21 = 'F'
                        then 'F'
                        when c.cb21 in ('Y', 'G', 'H')
                        then c.cb21
                    end
                else c.cb21
            end
    else c.cb21
    end as esl_course_level_adjusted_for_college
from courses c
