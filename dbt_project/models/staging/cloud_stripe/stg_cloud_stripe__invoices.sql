with

source as (

    select * from {{ ref('base__cloud_stripe_invoices') }}

),

customer_id_map as (

    select * from {{ ref('stg_stripe_customer_id_map') }}

),

charges as (

    select * from {{ ref('stg_cloud_stripe__charges') }}

),

renamed as (

    select
        {{ dbt_utils.star(
            from=ref('base__cloud_stripe_invoices'),
            except=['STRIPE_CUSTOMER_ID', 'SUBSCRIPTION_ID'],
            relation_alias='source'
        )}},

        coalesce(
            customer_id_map.new_customer_id,
            source.stripe_customer_id
            ) as stripe_customer_id,

        source.stripe_customer_id as original_stripe_customer_id,
        source.subscription_id,

        charges.cc_failure_message,
        charges.cc_expiration_date,

        coalesce(charges.refund_total,0) as refund_total,

        case
            when refund_total > 0
            and refund_total = invoice_total
                then true
            else false
        end as is_full_refund,

        case
            when charge_id is null
            and not is_subscription_upgrade
            and invoice_status is not null
                then false
                --If an invoice does not have a charge_id associated, then it
                --means the customer was never charged for it and therefore this
                --invoice is unpaid (e.g. in_1Jn69FKS6Y3lIrasHqbr1N1S).
                --If the charge_id is null and the invoice Status is null,
                --then that means the invoice was on a free plan btwn 2017-18
                --for consulting clients (e.g. in_19qBZZKS6Y3lIrasz6gmgl3o)
            when row_number() over (
                partition by stripe_customer_id
                order by invoice_date desc) = 1
                and is_full_refund
                and invoice_date < current_date()
                    then false
                --If a customer has a full-refund on their last invoice, then
                --we shouldn't count this as a charged invoice
                --(e.g. 'cus_KCB3DnUduJOjXC' -- went from S2M -> Managed,
                --then accidentally given another invoice)
            else true
        end as is_charged_invoice

    from source
    left join customer_id_map
        on source.stripe_customer_id = customer_id_map.old_customer_id
    left join charges using (charge_id)

)

select * from renamed