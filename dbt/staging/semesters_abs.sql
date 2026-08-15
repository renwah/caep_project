{{ config(materialized="table") }}        
        with semesters as (select
            term.year,
            term.quarter,
            ('20'||left(min(gi03)::text, 2)||term.quarter)::int as term,
            string_agg(term.term, ', ') as term_names,
            string_agg(term.gi03::text, '-') as term_codes
    from "postgres"."caep_analytics"."terms_adjusted" term
    where term.gi03 > 174 and term.gi03 < 300
        GROUP BY term.year, term.quarter)
            select * from semesters
        ORDER BY left(term_codes, 2), quarter