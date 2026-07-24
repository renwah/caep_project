{#
    classify_college(college_name)

#}
{% macro classify_college(college_name) %}
    case
        when
            {{ college_name }} in (
                'COMPTON',
                'SANTA ANA',
                'CUESTA',
                'SEQUOIAS',
                'YUBA',
                'SAN FRANCISCO CITY',
                'OXNARD',
                'L.A. MISSION',
                'MENDOCINO',
                'SANTA MONICA',
                'CHABOT',
                'CHAFFEY',
                'SAN JOSE CITY',
                'EAST L.A.',
                'MODESTO',
                'ANTELOPE VALLEY',
                'SAN FRANCISCO CTRS',
                'SANTIAGO CANYON',
                'CITRUS',
                'GLENDALE',
                'VICTOR VALLEY',
                'PALO VERDE',
                'SADDLEBACK',
                'CONTRA COSTA',
                'FOOTHILL'
            )
        then 'CONFIRMED CC - A/B'
        when
            {{ college_name }} in (
                'DIABLO VALLEY',
                'BARSTOW',
                'MORENO VALLEY',
                'GOLDEN WEST',
                'RIO HONDO',
                'FRESNO CITY',
                'NORCO',
                'MISSION',
                'RIVERSIDE',
                'SIERRA'
            )
        then 'CONFIRMED CC - E/F'
        when
            {{ college_name }} in (
                'L.A. CITY',
                'SAN DIEGO CONTINUING',
                'ALAMEDA',
                'NORTH ORANGE CONT',
                'DESERT',
                'WOODLAND',
                'MIRA COSTA',
                'BAKERSFIELD',
                'GAVILAN',
                'L.A. HARBOR',
                'IMPERIAL VALLEY',
                'LANEY',
                'CERRITOS',
                'MONTEREY',
                'L.A. VALLEY',
                'VENTURA',
                'MADERA',
                'DE ANZA',
                'PALOMAR',
                'MARIN',
                'REEDLEY',
                'ORANGE COAST',
                'WEST VALLEY',
                'COLUMBIA',
                'IRVINE VALLEY',
                'LONG BEACH CITY',
                'ALLAN HANCOCK',
                'PORTERVILLE',
                'MT. SAN ANTONIO'
            )

        then 'CONFIRMED CC - 6 LEVELS'
        when
            {{ college_name }} in (
                'MERRITT',
                'MERCED',
                'HARTNELL',
                'COALINGA',
                'SHASTA',
                'COASTLINE',
                'LAKE TAHOE',
                'PASADENA CITY',
                'SANTA BARBARA CITY',
                'CANYONS',
                'SAN BERNARDINO',
                'COPPER MOUNTAIN',
                'SANTA ROSA',
                'SOUTHWEST L.A.',
                'EL CAMINO',
                'LOS MEDANOS',
                'NAPA VALLEY',
                'LAS POSITAS'
            )
        then 'POSSIBLE CC'
        else 'Other CC'
    end

{% endmacro %}
