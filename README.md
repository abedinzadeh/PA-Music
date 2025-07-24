PA-Music
PA-Music is a Docker-based solution designed to stream online music and register to a SIP account, with easy web-based dashboard configuration.


🔧 Setup Instructions
Create a folder named pa inside the home directory of a user named admin on your Ubuntu server.

Note: All scripts are designed to work with a user account called admin.

Place all project files inside the ~/pa directory.

Run the installer script:
./pa-install.sh
This will automatically:

Create and run two containers: pa and icecast

Set up the necessary configuration and dependencies

🌐 Web Interface
Login Page
Accessible at:

http://<server-address>:3000
Default admin password: Admin

You can change this password in the default.html file.

Playback Stream Page
Accessible at:
http://<server-address>:3001
Default admin password: admin

You can change this password in the darkice.cfg file.

🎵 Features
Online Music Streaming

Stream URL, music volume, and phone call volume are fully configurable via the web interface.

SIP Integration

Register a phone number using SIP protocol with any SIP provider.

SIP credentials can be configured through the web dashboard.

SIP login details are stored at the end of the linphonerc file.

Automatic USB Audio Detection

When a USB sound card is connected or reconnected, it will be auto-detected and used for streaming.

Live Playback Control

A "Play Music" button is available on the login page.

USB Audio Output Selection

You can select and change the output USB audio device through the login interface.

Comprehensive Logging

All events and actions are logged in detail for troubleshooting and monitoring.

📁 File Locations
default.html: Contains login UI settings and admin password.

darkice.cfg: Controls streaming config and access credentials for port 3001.

linphonerc: Contains SIP account configuration details.
