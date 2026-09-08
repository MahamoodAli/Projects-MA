#!/bin/bash

# ============================================================
# Linux System Monitoring & Email Reporting Script
# Runs manually or via cron every 4 hours
# ============================================================

set -u

HOSTNAME=$(hostname)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
REPORT="/tmp/system_report_${HOSTNAME}_$(date +%Y%m%d_%H%M%S).html"

# Configure these
EMAIL_TO="admin@example.com"
DISK_THRESHOLD=80
CPU_THRESHOLD=80
MEMORY_THRESHOLD=80

# ------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------

status_class() {
    if [ "$1" -ge "$2" ]; then
        echo "critical"
    else
        echo "normal"
    fi
}

# ------------------------------------------------------------
# Disk Usage
# ------------------------------------------------------------

DISK_REPORT=""

while read -r filesystem size used available percent mount; do
    percent_num=${percent%\%}

    if [ "$percent_num" -ge "$DISK_THRESHOLD" ]; then
        class="critical"
    else
        class="normal"
    fi

    DISK_REPORT+="<tr>
        <td>$filesystem</td>
        <td>$size</td>
        <td>$used</td>
        <td>$available</td>
        <td class='$class'>$percent</td>
        <td>$mount</td>
    </tr>"
done < <(df -hP | awk 'NR>1 {print $1,$2,$3,$4,$5,$6}')

# ------------------------------------------------------------
# Running Services
# ------------------------------------------------------------

SERVICE_REPORT=""

if command -v systemctl >/dev/null 2>&1; then
    while read -r service; do
        status=$(systemctl is-active "$service" 2>/dev/null || true)

        if [ "$status" = "active" ]; then
            class="normal"
        else
            class="critical"
        fi

        SERVICE_REPORT+="<tr>
            <td>$service</td>
            <td class='$class'>$status</td>
        </tr>"
    done < <(
        systemctl list-unit-files \
            --type=service \
            --state=enabled \
            --no-legend \
            2>/dev/null |
        awk '{print $1}'
    )
else
    SERVICE_REPORT="<tr>
        <td colspan='2'>systemd/systemctl not available</td>
    </tr>"
fi

# ------------------------------------------------------------
# Memory Usage
# ------------------------------------------------------------

MEMORY_USED=$(free | awk '/Mem:/ {printf "%.0f", ($3/$2)*100}')
MEMORY_TOTAL=$(free -h | awk '/Mem:/ {print $2}')
MEMORY_USED_H=$(free -h | awk '/Mem:/ {print $3}')
MEMORY_AVAILABLE=$(free -h | awk '/Mem:/ {print $7}')

MEMORY_CLASS=$(status_class "$MEMORY_USED" "$MEMORY_THRESHOLD")

# ------------------------------------------------------------
# CPU Usage
# ------------------------------------------------------------

CPU_IDLE=$(top -bn1 | awk '/Cpu\(s\)/ {print $8}' | tr ',' '.')

if [ -n "$CPU_IDLE" ]; then
    CPU_USED=$(awk "BEGIN {printf \"%.0f\", 100-$CPU_IDLE}")
else
    CPU_USED=0
fi

CPU_CLASS=$(status_class "$CPU_USED" "$CPU_THRESHOLD")

LOAD_AVERAGE=$(uptime | awk -F'load average:' '{print $2}' | xargs)

# ------------------------------------------------------------
# System Information
# ------------------------------------------------------------

UPTIME=$(uptime -p)
KERNEL=$(uname -r)
IP_ADDRESS=$(hostname -I | awk '{print $1}')

# ------------------------------------------------------------
# Generate HTML Report
# ------------------------------------------------------------

cat > "$REPORT" <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>System Monitoring Report - $HOSTNAME</title>

<style>
body {
    font-family: Arial, sans-serif;
    color: #333;
    background: #f4f6f8;
    padding: 20px;
}

.container {
    max-width: 1100px;
    margin: auto;
    background: white;
    padding: 25px;
    border-radius: 8px;
}

h1 {
    color: #1f2937;
}

h2 {
    border-bottom: 2px solid #ddd;
    padding-bottom: 8px;
}

table {
    width: 100%;
    border-collapse: collapse;
    margin-bottom: 25px;
}

th, td {
    border: 1px solid #ddd;
    padding: 9px;
    text-align: left;
}

th {
    background: #374151;
    color: white;
}

.normal {
    color: #15803d;
    font-weight: bold;
}

.critical {
    color: #dc2626;
    font-weight: bold;
}

.metric {
    display: inline-block;
    width: 30%;
    margin: 1%;
    padding: 15px;
    background: #f9fafb;
    border-radius: 6px;
}

.metric-value {
    font-size: 25px;
    font-weight: bold;
}
</style>
</head>

<body>
<div class="container">

<h1>System Monitoring Report</h1>

<p>
<b>Host:</b> $HOSTNAME<br>
<b>Date:</b> $TIMESTAMP<br>
<b>IP Address:</b> $IP_ADDRESS<br>
<b>Kernel:</b> $KERNEL<br>
<b>Uptime:</b> $UPTIME
</p>

<h2>System Overview</h2>

<div class="metric">
    <div>CPU Usage</div>
    <div class="metric-value $CPU_CLASS">$CPU_USED%</div>
</div>

<div class="metric">
    <div>Memory Usage</div>
    <div class="metric-value $MEMORY_CLASS">$MEMORY_USED%</div>
</div>

<div class="metric">
    <div>Load Average</div>
    <div class="metric-value">$LOAD_AVERAGE</div>
</div>

<h2>Disk Usage</h2>

<table>
<tr>
    <th>Filesystem</th>
    <th>Size</th>
    <th>Used</th>
    <th>Available</th>
    <th>Usage</th>
    <th>Mount Point</th>
</tr>
$DISK_REPORT
</table>

<h2>Memory Usage</h2>

<table>
<tr><th>Metric</th><th>Value</th></tr>
<tr><td>Total Memory</td><td>$MEMORY_TOTAL</td></tr>
<tr><td>Used Memory</td><td>$MEMORY_USED_H</td></tr>
<tr><td>Available Memory</td><td>$MEMORY_AVAILABLE</td></tr>
<tr><td>Usage</td><td class="$MEMORY_CLASS">$MEMORY_USED%</td></tr>
</table>

<h2>CPU Usage</h2>

<table>
<tr><th>Metric</th><th>Value</th></tr>
<tr><td>CPU Usage</td><td class="$CPU_CLASS">$CPU_USED%</td></tr>
<tr><td>Load Average</td><td>$LOAD_AVERAGE</td></tr>
</table>

<h2>Enabled Services</h2>

<table>
<tr>
    <th>Service</th>
    <th>Status</th>
</tr>
$SERVICE_REPORT
</table>

<hr>

<p>
Generated automatically by the Linux System Monitoring Script.
</p>

</div>
</body>
</html>
EOF

# ------------------------------------------------------------
# Send Email
# ------------------------------------------------------------

if command -v mail >/dev/null 2>&1; then

    {
        echo "To: $EMAIL_TO"
        echo "Subject: System Monitoring Report - $HOSTNAME - $TIMESTAMP"
        echo "MIME-Version: 1.0"
        echo "Content-Type: text/html; charset=UTF-8"
        echo
        cat "$REPORT"
    } | /usr/sbin/sendmail "$EMAIL_TO"

elif command -v mailx >/dev/null 2>&1; then

    mailx \
        -a "Content-Type: text/html" \
        -s "System Monitoring Report - $HOSTNAME" \
        "$EMAIL_TO" < "$REPORT"

else
    echo "ERROR: mail/mailx/sendmail not installed."
    echo "Report generated at: $REPORT"
    exit 1
fi

rm -f "$REPORT"

echo "Report sent successfully to $EMAIL_TO"
