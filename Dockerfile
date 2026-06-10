FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

RUN mkdir -p /var/log/flaskapp/archive

COPY app.py .
COPY templates/ templates/

EXPOSE 5000

CMD ["python", "app.py"]
