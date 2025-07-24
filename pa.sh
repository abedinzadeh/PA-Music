#!/bin/bash

# Configuration
STREAM_URL="http://ydpradio01:8000/SA"
VOLUME_NORMAL=100
VOLUME_CALL=30
CALL_AUDIO_VOLUME=110
FADE_STEPS=4
CHECK_INTERVAL=1
LOG_FILE="/var/log/pa.log"
LINPHONE_LOG="/var/log/linphone.log"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}


# Find microphone source name
detect_microphone_source() {
    local source
    source=$(pactl list short sources | awk -F'\t' '$2 ~ /usb.*input/ {print $2; exit}')
    if [ -z "$source" ]; then
        # fallback to default source
        source=$(pactl info | grep 'Default Source' | awk '{print $3}')
    fi
    echo "$source"
}

# Mute microphone source
mute_microphone() {
    local mic_source=$1
    pactl set-source-mute "$mic_source" 1
    log "Microphone muted: $mic_source"
}

# Unmute microphone source
unmute_microphone() {
    local mic_source=$1
    pactl set-source-mute "$mic_source" 0
    log "Microphone unmuted: $mic_source"
}



# Watch Linphone logs
watch_linphone_calls() {
    if [ -f "$LINPHONE_LOG" ]; then
        tail -Fn0 "$LINPHONE_LOG" | while read -r line; do
            [ -z "$line" ] && continue
            echo "$(date '+%Y-%m-%d %H:%M:%S') - [LINPHONE] $line" >> "$LOG_FILE"
        done &
        log "Started Linphone call log watcher"
    else
        log "[WARNING] Linphone log file not found at $LINPHONE_LOG"
    fi
}

# Detect audio sink
detect_audio_sink() {
    local sink
    local retries=10
    local delay=1

    for ((i=1; i<=retries; i++)); do
        sink=$(pactl list short sinks | awk -F'\t' '$2 ~ /usb.*(stereo|output)/ {print $2; exit}')
        if [ -n "$sink" ]; then
            log "Detected USB audio sink: $sink"
            echo "$sink"
            return 0
        fi

        sink=$(pactl info | grep 'Default Sink' | awk '{print $3}')
        if [ -n "$sink" ]; then
            log "[WARNING] USB sink not found, using default sink: $sink"
            echo "$sink"
            return 0
        fi

        log "[RETRY] Sink not found. Attempt $i/$retries..."
        sleep "$delay"
    done

    log "[ERROR] No audio sink detected after $retries retries."
    echo ""
    return 1
}

# Verify sink exists
verify_audio_sink() {
    if ! pactl list short sinks | awk '{print $2}' | grep -qx "$AUDIO_DEVICE"; then
        log "[ERROR] Audio sink '$AUDIO_DEVICE' missing. Restarting PulseAudio and Linphone..."
        systemctl restart pulseaudio.service
        sleep 2
        pkill -f linphonec
        sleep 2
        linphonec -a >> "$LINPHONE_LOG" 2>&1 &
        sleep 1
        return 1
    fi
    return 0
}

# Start MPV
start_mpv() {
    pkill -f "mpv --no-video" 2>/dev/null || true
    sleep 0.5
    nohup mpv --no-video --audio-device="pulse/$AUDIO_DEVICE" --volume="$VOLUME_NORMAL" "$STREAM_URL" >/dev/null 2>&1 &
    MPV_PID=$!
    sleep 2
    log "MPV started with PID $MPV_PID"
}

# Get MPV sink-input index
get_mpv_sink_input() {
    pactl list sink-inputs | awk '
        /Sink Input/ {id=$3}
        /application.name = "mpv"/ {gsub("#", "", id); print id; exit}
    '
}

# Set MPV volume with fade
set_volume() {
    local target_vol=$1
    local mpv_index
    mpv_index=$(get_mpv_sink_input)
    if [ -z "$mpv_index" ]; then
        log "MPV sink input not found."
        return
    fi

    local current_vol

    current_vol=$(pactl list sink-inputs | awk -v idx="$mpv_index" '
        $1 == "Sink" && $2 == "Input" && $3 == "#"idx {found=1}
        found {
            if ($0 ~ /Volume:/) {
                for (i = 1; i <= NF; i++) {
                    if ($i ~ /[0-9]+%/) {
                        gsub("%", "", $i)
                        print $i
                        exit
                    }
                }
            }
        }
    ')


    [ -z "$current_vol" ] && current_vol=$VOLUME_NORMAL

    local diff=$((target_vol - current_vol))
    for ((i=1; i<=FADE_STEPS; i++)); do
        local step=$((current_vol + diff * i / FADE_STEPS))
        pactl set-sink-input-volume "$mpv_index" "${step}%"
        sleep 0.2
    done

    pactl set-sink-input-volume "$mpv_index" "${target_vol}%"
    log "MPV volume set to ${target_vol}% (sink-input $mpv_index)"
}

# Check call state
check_call_active() {
    pactl list sink-inputs | grep -q 'application.name = "linphonec"'
}

## This script and new PA solution were developed by Hossein Abedinzadeh and deployed to all Drake's stores on 01/05/2025 ##
# Move Linphone audio and set its volume
move_linphone_audio() {
    local retries=10
    local linphone_index
    log "Looking for Linphone sink-input..."

    while (( retries > 0 )); do
        linphone_index=$(pactl list sink-inputs | awk '
            /Sink Input/ { id = $3 }
            /application.name = "linphonec"/ { gsub("#", "", id); print id; exit }
        ')

        if [ -n "$linphone_index" ]; then
            log "Found Linphone sink-input $linphone_index. Moving to sink: $AUDIO_DEVICE"
            pactl move-sink-input "$linphone_index" "$AUDIO_DEVICE"
            pactl set-sink-input-volume "$linphone_index" "${CALL_AUDIO_VOLUME}%"
            log "Set Linphone volume to ${CALL_AUDIO_VOLUME}%"
            return 0
        fi

        log "Linphone sink-input not ready... ($retries left)"
        sleep 1
        ((retries--))
    done

    log "ERROR: Timed out waiting for Linphone sink-input."
    return 1
}

# Main logic
main() {
    log "=== Radio Controller Started ==="
    watch_linphone_calls

    AUDIO_DEVICE=$(detect_audio_sink)
    MICROPHONE_SOURCE=$(detect_microphone_source)

    until verify_audio_sink; do
        log "Waiting for audio sink '$AUDIO_DEVICE' to become available..."
        sleep 2
    done

    pactl set-default-sink "$AUDIO_DEVICE"
    log "Set PulseAudio default sink to: $AUDIO_DEVICE"
    log "Default sink after setting: $(pactl info | grep 'Default Sink')"

    # Set monitor source as default source
    DEFAULT_SINK="$AUDIO_DEVICE"
    MONITOR_SOURCE="${DEFAULT_SINK}.monitor"
    if pactl set-default-source "$MONITOR_SOURCE" 2>/dev/null; then
        log "Set PulseAudio default source to: $MONITOR_SOURCE"
    else
        log "Warning: Failed to set monitor source (may not be available)"
    fi


    pactl set-sink-volume "$AUDIO_DEVICE" 100%
    start_mpv

    local prev_state="no_call"

    while true; do
        if ! verify_audio_sink; then
            log "Sink lost. Re-detecting..."
            AUDIO_DEVICE=$(detect_audio_sink)
            until verify_audio_sink; do
                sleep 2
            done
            pactl set-sink-volume "$AUDIO_DEVICE" 100%
            start_mpv
        fi

        if ! ps -p "$MPV_PID" >/dev/null; then
            log "MPV not running. Restarting..."
            start_mpv
        fi

        if check_call_active; then
            if [ "$prev_state" != "call" ]; then
                log "Call detected. Fading music volume."
                set_volume "$VOLUME_CALL"
                move_linphone_audio
                mute_microphone "$MICROPHONE_SOURCE"
                prev_state="call"
            fi
        else
            if [ "$prev_state" != "no_call" ]; then
                log "Call ended. Restoring music volume."
                set_volume "$VOLUME_NORMAL"
                unmute_microphone "$MICROPHONE_SOURCE"
                prev_state="no_call"
            fi
        fi

        sleep "$CHECK_INTERVAL"
    done
}


# Start DarkIce for streaming
darkice -c /etc/darkice.cfg >> /var/log/stream.log 2>&1 &

main
