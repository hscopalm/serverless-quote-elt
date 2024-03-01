# sql to generate a fact level table for the quotes_raw
quotes_fact = """

select
    quote_id
    , content as quote_text -- rename the column, as if we had dirty data / couldn't change the source
    , author
    , author_slug
    
    , tag_list
    , character_count
    
    , added_date
    , modified_date
    
    , ingested_date
    , ingested_at
    
from quotes

"""

# sql to generate an aggregate table for the quotes_fact, one row per distinct quote_id
quotes_agg = """

select
    quote_id
    , quote_text
    , author

    , count(quote_id) as quote_count
    , min(ingested_at) as first_ingestion
    , max(ingested_at) as last_ingestion
    , array_agg(ingested_at) as ingestion_dates
    
from quotes_fact

group by
    quote_id
    , quote_text
    , author
    
order by
    quote_count desc
    ;

"""
