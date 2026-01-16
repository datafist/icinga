FROM python:3.11-slim

LABEL maintainer="Icinga Monitoring Stack"
LABEL description="Icinga2 Prometheus Exporter"

WORKDIR /app

# Git installieren und Repo klonen
RUN apt-get update && \
    apt-get install -y --no-install-recommends git && \
    git clone https://github.com/opsdis/icinga2-exporter.git . && \
    pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir -e . && \
    apt-get remove -y git && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

# Config-Verzeichnis
RUN mkdir -p /etc/icinga2-exporter

EXPOSE 9150

# Verwende das installierte Package
CMD ["python", "-m", "icinga2_exporter", "-f", "/etc/icinga2-exporter/config.yml"]
