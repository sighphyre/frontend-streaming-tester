import asyncio
import httpx
import json
import time
import os

# Configuration
TARGET_URL = "http://10.1.1.1:3063/api/client/stream-frontend"
NUM_CONNECTIONS = int(os.getenv("NUM_CONNECTIONS", "100"))
TARGET_URL = os.getenv("TARGET_URL", "http://10.1.1.1:3063/api/client/stream-frontend")
AUTH_TOKEN = os.getenv("AUTH_TOKEN", "*:development.15c9d1ee348d52d154ca17fa1cccd97034fe64b7aa1a034f2a546e4f")
CONTEXT = {
    "userId": "tester-1",
    "properties": {"key1": "value1", "test": "test"}
}

async def connect_sdk(client, connection_id):
    try:
        async with client.stream(
            "GET",
            TARGET_URL,
            headers={
                "Authorization": AUTH_TOKEN,
                "Accept": "text/event-stream"
            },
            timeout=None
        ) as response:
            if response.status_code != 200:
                print(f"[Conn {connection_id}] Error: {response.status_code}")
                return

            print(f"[Conn {connection_id}] Connected. Holding open...")

            # Keep our connection alive here and print any incoming data
            async for line in response.aiter_lines():
                if line.startswith("data:"):
                    print(f"[Conn {connection_id}] Data received")

            await asyncio.sleep(3600)

    except Exception as e:
        print(f"[Conn {connection_id}] Failed: {e}")

async def main():
    limits = httpx.Limits(max_connections=NUM_CONNECTIONS)
    async with httpx.AsyncClient(limits=limits) as client:
        await asyncio.gather(*(connect_sdk(client, i) for i in range(NUM_CONNECTIONS)))

if __name__ == "__main__":
    asyncio.run(main())

