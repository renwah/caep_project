{{ config(materialized="table") }}

select
    gi03,
    year,
    term,
    case
        when right(gi03::varchar, 1) in ('1', '2')
        then 1
        when right(gi03::varchar, 1) in ('3', '4')
        then 2
        when right(gi03::varchar, 1) in ('5', '6')
        then 3
        when right(gi03::varchar, 1) in ('7', '8')
        then 4
    end as quarter
        from {{ source("caep_data", "sr1318term") }}
        where right(gi03::varchar, 1) != '0'

