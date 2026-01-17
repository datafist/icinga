#!/bin/bash
#
# Service Notification Script für Icinga2
# Sendet Email-Benachrichtigungen bei Service-Problemen
#

PROG="$(basename $0)"

# Defaults
USEREMAIL=""
HOSTNAME=""
HOSTDISPLAYNAME=""
HOSTADDRESS=""
SERVICENAME=""
SERVICEDISPLAYNAME=""
SERVICESTATE=""
SERVICEOUTPUT=""
NOTIFICATIONTYPE=""
NOTIFICATIONAUTHOR=""
NOTIFICATIONCOMMENT=""
LONGDATETIME=""

# Parse arguments
while getopts "4:6:b:c:d:e:l:n:o:r:s:t:u:" opt; do
    case $opt in
        4) HOSTADDRESS="$OPTARG" ;;
        6) HOSTADDRESS6="$OPTARG" ;;
        b) NOTIFICATIONAUTHOR="$OPTARG" ;;
        c) NOTIFICATIONCOMMENT="$OPTARG" ;;
        d) LONGDATETIME="$OPTARG" ;;
        e) SERVICENAME="$OPTARG" ;;
        l) HOSTNAME="$OPTARG" ;;
        n) HOSTDISPLAYNAME="$OPTARG" ;;
        o) SERVICEOUTPUT="$OPTARG" ;;
        r) USEREMAIL="$OPTARG" ;;
        s) SERVICESTATE="$OPTARG" ;;
        t) NOTIFICATIONTYPE="$OPTARG" ;;
        u) SERVICEDISPLAYNAME="$OPTARG" ;;
        \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
    esac
done

# Validierung
if [ -z "$USEREMAIL" ]; then
    echo "ERROR: No recipient email specified (-r)"
    exit 1
fi

# State-Emoji für bessere Lesbarkeit
case "$SERVICESTATE" in
    OK)       STATE_EMOJI="✅" ;;
    WARNING)  STATE_EMOJI="⚠️" ;;
    CRITICAL) STATE_EMOJI="🔴" ;;
    UNKNOWN)  STATE_EMOJI="❓" ;;
    *)        STATE_EMOJI="📋" ;;
esac

# Subject erstellen
case "$NOTIFICATIONTYPE" in
    PROBLEM)
        SUBJECT="$STATE_EMOJI [$SERVICESTATE] $HOSTDISPLAYNAME - $SERVICEDISPLAYNAME"
        ;;
    RECOVERY)
        SUBJECT="$STATE_EMOJI [$SERVICESTATE] $HOSTDISPLAYNAME - $SERVICEDISPLAYNAME wieder OK"
        ;;
    ACKNOWLEDGEMENT)
        SUBJECT="🔧 [$SERVICESTATE] $HOSTDISPLAYNAME - $SERVICEDISPLAYNAME bestätigt"
        ;;
    *)
        SUBJECT="📋 [$NOTIFICATIONTYPE] $HOSTDISPLAYNAME - $SERVICEDISPLAYNAME"
        ;;
esac

# Email-Body erstellen
BODY=$(cat <<EOF
═══════════════════════════════════════════════════════════
 ICINGA2 SERVICE NOTIFICATION
═══════════════════════════════════════════════════════════

Typ:      $NOTIFICATIONTYPE
Host:     $HOSTDISPLAYNAME ($HOSTNAME)
Adresse:  $HOSTADDRESS
Service:  $SERVICEDISPLAYNAME ($SERVICENAME)
Status:   $SERVICESTATE
Zeit:     $LONGDATETIME

───────────────────────────────────────────────────────────
OUTPUT
───────────────────────────────────────────────────────────
$SERVICEOUTPUT

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
