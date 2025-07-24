FROM ahsanemon/linphone

# Install dependencies in a single RUN layer (reduces image size)
RUN apt-get update && apt-get install -y \
    bc \
    mpv \
    socat \
    pulseaudio \
    pulseaudio-utils \
    alsa-utils \
    dbus \
    jq \
    darkice \
    nano \
    && rm -rf /var/lib/apt/lists/*

# Use a script as entrypoint for better process management
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
