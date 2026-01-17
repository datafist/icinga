#!/bin/bash
#
# Host Notification Script für Icinga2
# Sendet Email-Benachrichtigungen bei Host-Problemen
#

PROG="$(basename $0)"

# Defaults
USEREMAIL=""
HOSTNAME=""
HOSTDISPLAYNAME=""
HOSTADDRESS=""
HOSTSTATE=""
HOSTOUTPUT=""
NOTIFICATIONTYPE=""
NOTIFICATIONAUTHOR=""
NOTIFICATIONCOMMENT=""
LONGDATETIME=""

# Parse arguments
while getopts "4:6:b:c:d:l:n:o:r:s:t:" opt; do
    case $opt in
        4) HOSTADDRESS="$OPTARG" ;;
        6) HOSTADDRESS6="$OPTARG" ;;
        b) NOTIFICATIONAUTHOR="$OPTARG" ;;
        c) NOTIFICATIONCOMMENT="$OPTARG" ;;
        d) LONGDATETIME="$OPTARG" ;;
        l) HOSTNAME="$OPTARG" ;;
        n) HOSTDISPLAYNAME="$OPTARG" ;;
        o) HOSTOUTPUT="$OPTARG" ;;
        r) USEREMAIL="$OPTARG" ;;
        s) HOSTSTATE="$OPTARG" ;;
        t) NOTIFICATIONTYPE="$OPTARG" ;;
        \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
    esac
done

# Validierung
if [ -z "$USEREMAIL" ]; then
    echo "ERROR: No recipient email specified (-r)"
    exit 1
fi

# State-Emoji für bessere Lesbarkeit
case "$HOSTSTATE" in
    UP)   STATE_EMOJI="✅" ;;
    DOWN) STATE_EMOJI="🔴" ;;
    *)    STATE_EMOJI="⚠️" ;;
esac

# Subject erstellen
case "$NOTIFICATIONTYPE" in
    PROBLEM)
        SUBJECT="$STATE_EMOJI [$HOSTSTATE] $HOSTDISPLAYNAME ist DOWN"
        ;;
    RECOVERY)
        SUBJECT="$STATE_EMOJI [$HOSTSTATE] $HOSTDISPLAYNAME ist wieder UP"
        ;;
    ACKNOWLEDGEMENT)
        SUBJECT="🔧 [$HOSTSTATE] $HOSTDISPLAYNAME - Problem bestätigt"
        ;;
    *)
        SUBJECT="📋 [$NOTIFICATIONTYPE] $HOSTDISPLAYNAME - $HOSTSTATE"
        ;;
esac

# Email-Body erstellen
BODY=$(cat <<EOF
═══════════════════════════════════════════════════════════
 ICINGA2 HOST NOTIFICATION
═══════════════════════════════════════════════════════════

Typ:      $NOTIFICATIONTYPE
Host:     $HOSTDISPLAYNAME ($HOSTNAME)
Adresse:  $HOSTADDRESS
Status:   $HOSTSTATE
Zeit:     $LONGDATETIME

───────────────────────────────────────────────────────────
OUTPUT
───────────────────────────────────────────────────────────
$HOSTOUTPUT

EOF
)

# Bei Acknowledgement: Autor und Kommentar hinzufügen
if [ -n "$NOTIFICATIONAUTHOR" ] && [ -n "$NOTIFICATIONCOMMENT" ]; then
    BODY+="
───────────────────────────────────────────────────────────
KOMMENTAR
───────────────────────────────────────────────────────────
Von:      $NOTIFICATIONAUTHOR
Kommentar: $NOTIFICATIONCOMMENT
"
fi

BODY+="
═══════════════════════════════════════════════════════════
 Gesendet von Icinga2 Monitoring
═══════════════════════════════════════════════════════════
"

# Email senden via msmtp
echo "$BODY" | /usr/bin/msmtp -a default -t <<EOF
To: $USEREMAIL
Subject: $SUBJECT
Content-Type: text/plain; charset=UTF-8

$BODY
EOF

exit $?
