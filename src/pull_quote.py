import requests
from datetime import datetime

# url to hit, pulls a random quote according to params passed
url = 'https://api.quotable.io/quotes/random'

# function performing the heavy lifting
def get_quotes():
    response = requests.get(url)
    return response

# what the lambda runs
def lambda_handler():
    quote_obj = get_quotes().json()

    for quote in quote_arr:
        print(quote)
        
    return quote_obj
