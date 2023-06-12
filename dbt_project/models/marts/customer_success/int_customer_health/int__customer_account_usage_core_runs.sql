{% set t7d_logic = 'date_day between dateadd(day, -8, current_date()) and dateadd(day, -1, current_date())'%}
{% set t7to14d_logic = 'date_day between dateadd(day, -15, current_date()) and dateadd(day, -8, current_date())'%}
{% set t30d_logic = 'date_day between dateadd(day, -31, current_date()) and dateadd(day, -1, current_date())'%}
{% set t30to90d_logic = 'date_day between dateadd(day, -91, current_date()) and dateadd(day, -31, current_date())'%}
{% set t90d_logic = 'date_day between dateadd(day, -91, current_date()) and dateadd(day, -1, current_date())'%}

with

runs as (

    select * from {{ ref('fct_core_run_metrics') }}

),

mappings as (

    select * from {{ ref('cloud_account_mappings') }}
    where is_current_paying_account

),

joined as (

    select
        mappings.customer_id,
        runs.*
    from runs
    inner join mappings 
        on mappings.account_id = runs.cloud_account_id

),


runs_agg as (

    select 
    
        date_day,
        customer_id,
        count(*) as core_runs,
        sum(count_succeed) as core_models_built,
        count(case when is_failed_run = 0 and type = 'core_run' then unique_id_sk end) as core_runs_successful,
        count(case when is_failed_run = 1 and type = 'core_run' then unique_id_sk end) as core_runs_failed

    from joined
    group by 1,2

),

trailing_run_metrics as (

    select 
        customer_id,

        {%-
            set run_types =['core_runs',
                'core_models_built',
                'core_runs_successful',
                'core_runs_failed',
            ]
        -%}

        {% for run_type in run_types -%}

        
            sum(
                case 
                    when {{ t7d_logic }}
                        then {{run_type}} 
                    else 0 
                end
            ) as t7d_{{run_type}}

            ,sum(
                case 
                    when {{ t7to14d_logic }}
                        then {{run_type}} 
                    else 0 
                end
            ) as prev_t7d_{{run_type}}

            ,sum(
                case 
                    when {{ t30d_logic }}
                        then {{run_type}} 
                    else 0 
                end
            ) as t30d_{{run_type}}

            ,sum(
                case 
                    when {{ t30to90d_logic }}
                        then {{run_type}}  
                    else 0 
                end
            ) as prev_t30d_{{run_type}}

            ,sum(
                case 
                    when {{ t90d_logic }}
                        then {{run_type}}   
                    else 0 
                end
            ) as t90d_{{run_type}}

        {% if not loop.last %},{% endif %}
        {% endfor %}    
    from runs_agg
    group by 1
),

pct_changes as (

    select
        *

    {%-
        set run_metrics =[
            'core_runs',
            'core_models_built',
            'core_runs_successful',
            'core_runs_failed',
            ]
    -%}

    {% for run_metric in run_metrics -%}

        ,round(
            ((t7d_{{ run_metric }} - prev_t7d_{{ run_metric }}) / nullif(prev_t7d_{{ run_metric }},0)),
            2
        ) as t7d_{{ run_metric }}_pct_change

        ,round(
            ((t30d_{{ run_metric }} - prev_t7d_{{ run_metric }}) / nullif(prev_t30d_{{ run_metric }},0)),
            2
        ) as t30d_{{ run_metric }}_pct_change

    {%- endfor %}

    from trailing_run_metrics

)

select * from pct_changes