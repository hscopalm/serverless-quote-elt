# necessary imports
import pendulum
import boto3
from boto3.dynamodb.conditions import Key
import simplejson as json
import os
import duckdb
import numpy as np

# import the SQL queries
from transform_sql import quotes_fact, quotes_agg


# date (UTC) of interest to query (yesterday's ingestions)
ingested_date = pendulum.now("UTC").add(days=-1).to_date_string()


def query_table(table, ingested_date):
    """
    Query the table for all items with the given ingested_date
    """
    response = table.query(
        KeyConditionExpression=Key("ingested_date").eq(ingested_date),
    )

    return response


def dump_to_json(response, file_name):
    """
    Dump the response to a JSON file
    """
    quotes = json.dumps(response["Items"], indent=2)

    file_path = os.path.join(os.path.dirname(__file__), file_name)

    with open(file_path, "w") as outfile:
        outfile.write(quotes)

    return file_path


def load_json_to_duckdb(file_path):
    """
    Load the JSON file into DuckDB
    """

    # create a connection to the DuckDB database
    duckdb.read_json(file_path, format="array")

    # create a table in the DuckDB database from the JSON file
    duckdb.sql("CREATE TABLE quotes AS SELECT * FROM '{}';".format(file_path))


def transform_quotes():
    """
    Execute CTAS statements to transform the quotes data
    """
    duckdb.sql("CREATE TABLE quotes_fact AS {sql}".format(sql=quotes_fact))

    duckdb.sql("CREATE TABLE quotes_agg AS {sql}".format(sql=quotes_agg))


def cleanup():
    """
    Clean up the JSON file
    """
    os.remove("quotes.json")


# what the lambda runs
def lambda_handler(event, context):
    # instantiate the resource to interact with the DynamoDB service API
    db = boto3.resource("dynamodb")

    table = db.Table("quotes_raw")

    response = query_table(table, ingested_date)

    quotes_json_path = dump_to_json(response, "quotes.json")

    # load the JSON file into DuckDB
    load_json_to_duckdb(quotes_json_path)

    # transform the quotes data
    transform_quotes()

    # query the DuckDB database for demonstration and logging purposes
    print(duckdb.sql("SELECT * FROM quotes;"))
    print(duckdb.sql("SELECT * FROM quotes_fact;"))
    print(duckdb.sql("SELECT * FROM quotes_agg;"))

    # what was the most common quote ingested yesterday?
    top_quote = duckdb.sql("SELECT * FROM quotes_agg limit 1;").fetchdf()
    quote_distribution = duckdb.sql("SELECT quote_count FROM quotes_agg").fetchnumpy()[
        "quote_count"
    ]

    # measures of dispersion
    min = np.amin(quote_distribution)
    max = np.amax(quote_distribution)
    range = np.ptp(quote_distribution)
    variance = np.var(quote_distribution)
    sd = np.std(quote_distribution)

    print(
        'The most common quote ingested yesterday was: "{}" by {}'.format(
            top_quote["quote_text"].values[0], top_quote["author"].values[0]
        )
    )

    # let's print out some descriptive statistics
    print("For the quotes ingested yesterday, the distribution of quote counts is:")
    print("Measures of Dispersion")
    print("Minimum # of ingestions =", min)
    print("Maximum # of ingestions =", max)
    print("Range =", range)
    print("Variance =", variance)
    print("Standard Deviation =", sd)
    print("Total Distinct Quotes =", len(quote_distribution))

    cleanup()

    return "Quotes transformed successfully!"
