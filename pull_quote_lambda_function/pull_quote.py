import requests
import pendulum
import boto3

# url to hit, pulls a random quote according to params passed
url = "https://api.quotable.io/quotes/random"


# function performing the heavy lifting
def get_quotes():
    response = requests.get(url)

    return response


# for the returned quotes, lightly transform
def parse_quotes():
    quote_obj = get_quotes().json()
    print(quote_obj)

    for quote in quote_obj:
        print(quote)

        transformed_quote = {
            "ingested_date": pendulum.now("UTC").to_date_string(),  # partition key
            "ingested_at": str(pendulum.now("UTC")),  # sort key
            "quote_id": quote["_id"],
            "content": quote["content"],
            "author": quote["author"],
            "tag_list": quote["tags"],
            "author_slug": quote["authorSlug"],
            "character_count": quote["length"],
            "added_date": quote["dateAdded"],
            "modified_date": quote["dateModified"],
        }

    return transformed_quote


# Function to put an entry into the DynamoDB table
def put_table_item(table, item):
    response = table.put_item(Item=item)

    # If there were errors, throw an exception
    if response["ResponseMetadata"]["HTTPStatusCode"] != 200:
        raise Exception("Failed to update table!")


# what the lambda runs
def lambda_handler(event, context):
    # instantiate the resource to interact with the DynamoDB service API
    db = boto3.resource("dynamodb")

    # Table instance
    table = db.Table("quotes_raw")

    quote = parse_quotes()

    put_table_item(table, quote)
