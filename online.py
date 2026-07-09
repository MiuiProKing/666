from telethon import TelegramClient
import asyncio

api_id = 25889533
api_hash = "ea4dbf39e42c3a04639a7cdb281d6fe7"

client = TelegramClient("session", api_id, api_hash)

async def main():
    await client.start()

    print("Бот запущен")

    while True:
        try:
            await client.send_message("me", "ку")
            print("Сообщение отправлено")
            await asyncio.sleep(10)

        except Exception as e:
            print("Ошибка:", e)
            await asyncio.sleep(5)

asyncio.run(main())