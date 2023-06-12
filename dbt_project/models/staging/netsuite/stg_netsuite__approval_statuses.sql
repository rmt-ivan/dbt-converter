with

source as (

    select * from {{ source('netsuite','approval_status') }}
    where _fivetran_deleted = false
    
),

renamed as (

    select
        --ids
        id as approval_status_id,

        -- dimensions
        name as approval_status,
        
        -- metadata
        _fivetran_synced

    from source

)

select * from renamed