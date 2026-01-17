# Icinga2 mit msmtp für Email-Benachrichtigungen
# Base Image Version: 2.15.1
FROM icinga/icinga2:2.15.1

# msmtp installieren für Email-Versand
RUN apt-get update && \
    apt-get install -y --no-install-recommends msmtp msmtp-mta ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    # Log-Verzeichnis für msmtp
    touch /var/log/msmtp.log && \
    chmod 666 /var/log/msmtp.log
