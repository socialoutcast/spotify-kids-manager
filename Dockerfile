FROM python:3.9-slim

RUN apt-get update && apt-get install -y \
    curl \
    bluetooth \
    bluez \
    pulseaudio-module-bluetooth \
    systemd \
    sudo \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/spotify-kids

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY web/ ./web/
COPY config/ ./config/
COPY scripts/ ./scripts/

RUN mkdir -p web/static

EXPOSE 8080

CMD ["python", "web/app.py"]