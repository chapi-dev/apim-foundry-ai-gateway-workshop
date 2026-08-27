"""
Prueba del AI Gateway con el SDK de OpenAI apuntando a APIM (protocolo Azure OpenAI).
Uso:
    pip install openai
    $env:APIM_GATEWAY_URL="https://xxxxx-apim.azure-api.net"
    $env:APIM_SUBSCRIPTION_KEY="<clave>"
    python clients/test-openai.py
"""
import os
from openai import AzureOpenAI

client = AzureOpenAI(
    azure_endpoint=os.environ["APIM_GATEWAY_URL"],
    api_key=os.environ["APIM_SUBSCRIPTION_KEY"],  # se envía como cabecera api-key -> clave de APIM
    api_version="2024-10-21",
)

resp = client.chat.completions.create(
    model="chat",  # nombre del despliegue en Foundry
    messages=[
        {"role": "system", "content": "Eres un asistente conciso."},
        {"role": "user", "content": "Explica qué es un AI Gateway en una frase."},
    ],
)

print(resp.choices[0].message.content)
print("---")
print("Tokens:", resp.usage.total_tokens if resp.usage else "n/a")
