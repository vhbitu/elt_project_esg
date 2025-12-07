# Script auxiliar só para testar a API OpenWeather localmente

import os
import requests
from pprint import pprint

API_KEY = os.environ.get("AIR_POLLUTION_API_KEY")
if not API_KEY:
    raise RuntimeError("Defina a variável de ambiente AIR_POLLUTION_API_KEY")

# Exemplo: São Paulo
LAT = -23.5505
LON = -46.6333

url = "https://api.openweathermap.org/data/2.5/air_pollution"
params = {
    "lat": LAT,
    "lon": LON,
    "appid": API_KEY,
}
print("Request params:", params)

resp = requests.get(url, params=params, timeout=10)
print("Status code:", resp.status_code)
pprint(resp.json())
