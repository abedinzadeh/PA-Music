#!/bin/bash
set -euo pipefail

# Redirect all logs to /var/log/pa.log (APPEND mode now)
exec >> /var/log/pa.log 2>&1

echo "[ENTRYPOINT][$(date '+%Y-%m-%d %H:%M:%S')] Starting entrypoint script..."

export PULSE_SERVER=unix:/var/run/pulse/native

# Wait for PulseAudio and USB sink
echo "[ENTRYPOINT][$(date '+%Y-%m-%d %H:%M:%S')] Checking for PulseAudio and USB sink..."
for i in {1..10}; do
  if pactl info >/dev/null 2>&1; then
    USB_SINK=$(pactl list short sinks | grep usb | awk '{print $2}' || true)
    if [[ -n "$USB_SINK" ]]; then
      echo "[ENTRYPOINT][$(date '+%Y-%m-%d %H:%M:%S')] PulseAudio is ready. USB sink detected: $USB_SINK"
      break
    fi
  fi
  echo "[ENTRYPOINT][$(date '+%Y-%m-%d %H:%M:%S')] Retry $i/10: Waiting for PulseAudio and USB sink..."
  sleep 1
done

if [[ -z "${USB_SINK:-}" ]]; then
  echo "[ERROR][$(date '+%Y-%m-%d %H:%M:%S')] USB sink not available or PulseAudio not ready after timeout."
  exit 1
fi

echo "[ENTRYPOINT][$(date '+%Y-%m-%d %H:%M:%S')] Syncing SIP..."
cp /opt/linphonerc /root/.linphonerc
chmod 600 /root/.linphonerc

echo "[ENTRYPOINT][$(date '+%Y-%m-%d %H:%M:%S')] Starting SIP..."

# Modified Linphone startup to capture ALL logs
linphonec -a >> /var/log/linphone.log 2>&1 &

echo "[ENTRYPOINT][$(date '+%Y-%m-%d %H:%M:%S')] Starting PA Script..."
chmod +x /opt/pa.sh
/opt/pa.sh &

# Keep container running
wait
