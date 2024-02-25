import pendulum
import boto3
from boto3.dynamodb.conditions import Key
import simplejson as json
import os
import duckdb

# instantiate the resource to interact with the DynamoDB service API
db = boto3.resource("dynamodb")
table = db.Table("quotes_raw")

# date (UTC) of interest to query (yesterday's ingestions)
# ingested_date = pendulum.now("UTC").add(days=-1).to_date_string()
# testing, remove!
ingested_date = pendulum.now("UTC").add(days=0).to_date_string()


def query_table(ingested_date):
    """
    Query the table for all items with the given ingested_date
    """
    response = table.query(
        KeyConditionExpression=Key("ingested_date").eq(ingested_date),
    )

    return response


response = query_table(ingested_date)
quotes = json.dumps(response["Items"], indent=2)

file_name = "quotes.json"
file_path = os.path.join(os.path.dirname(__file__), file_name)

with open(file_path, "w") as outfile:
    outfile.write(quotes)

# create a connection to the DuckDB database
duckdb.read_json(file_path, format="array")

# create a table in the DuckDB database from the JSON file
duckdb.sql("CREATE TABLE quotes AS SELECT * FROM '{}';".format(file_path))

sql = """

select
    quote_id
    , content
    , author

    , count(quote_id) as quote_count
    , min(ingested_at) as first_ingestion
    , max(ingested_at) as last_ingestion
    , array_agg(ingested_at) as ingestion_dates
    
from quotes

group by
    quote_id
    , content
    , author
    
order by
    quote_count desc
    ;

"""

# query the DuckDB database
print(duckdb.sql(sql))
