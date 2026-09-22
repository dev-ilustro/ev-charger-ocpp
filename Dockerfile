FROM python:3.11-slim

WORKDIR /app

# ติดตั้ง dependencies ก่อนเพื่อใช้ Docker layer cache
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# คัดลอกโค้ดทั้งหมด
COPY app ./app

# โฟลเดอร์เก็บฐานข้อมูล SQLite (ควร mount เป็น volume บน Coolify เพื่อกันข้อมูลหาย)
RUN mkdir -p /app/data
VOLUME ["/app/data"]

ENV DATA_DIR=/app/data
EXPOSE 9000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "9000"]
