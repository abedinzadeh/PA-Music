// just search for the "your domain" inside of the code and change it into your domain value that you have entered inside of the "linphonerc" file as well.
const express = require('express');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const bodyParser = require('body-parser');
const { exec } = require('child_process');

const app = express();
const PORT = 3000;

const RADIO_SH = '/home/admin/pa/pa.sh';
const LINPHONERC = '/home/admin/pa/linphonerc';
const RADIO_LOG = '/home/admin/pa/pa.log';

app.use(bodyParser.urlencoded({ extended: false }));

app.use((req, res, next) => {
  if (req.path === '/' || req.path === '/index.html') return next();
  express.static(path.join(__dirname, 'public'))(req, res, next);
});

app.get('/', (req, res) => {
  const config = {
    STREAM_URL: '', AUDIO_DEVICE: '', VOLUME_NORMAL: '',
    VOLUME_CALL: '', CALL_AUDIO_VOLUME: '', PHONE: '', PASSWORD: ''
  };

  try {
    const radioLines = fs.readFileSync(RADIO_SH, 'utf-8').split('\n');
    for (const line of radioLines) {
      if (line.startsWith('STREAM_URL=')) config.STREAM_URL = line.split('=')[1].replace(/"/g, '');
      if (line.startsWith('AUDIO_DEVICE=')) config.AUDIO_DEVICE = line.split('=')[1].replace(/"/g, '');
      if (line.startsWith('VOLUME_NORMAL=')) config.VOLUME_NORMAL = line.split('=')[1];
      if (line.startsWith('VOLUME_CALL=')) config.VOLUME_CALL = line.split('=')[1];
      if (line.startsWith('CALL_AUDIO_VOLUME=')) config.CALL_AUDIO_VOLUME = line.split('=')[1];
    }

    const linphoneContent = fs.readFileSync(LINPHONERC, 'utf-8');
    const matchPhone = linphoneContent.match(/username=(.+)/);
    if (matchPhone) config.PHONE = matchPhone[1];

    const matchHa1 = linphoneContent.match(/ha1=([a-f0-9]{32})/);
    if (matchHa1) config.PASSWORD = matchHa1[1];

    const streamHost = req.hostname || 'localhost';
    config.STREAM_PLAY_URL = `http://${streamHost}:3001/live`;

  } catch (err) {
    console.error('Error reading config files:', err);
  }

  const htmlPath = path.join(__dirname, 'public/index.html');
  let html = fs.readFileSync(htmlPath, 'utf-8');
  const script = `<script>window.config = ${JSON.stringify(config)};<\/script>`;
  html = html.replace('</head>', `${script}\n</head>`);
  res.send(html);
});

app.post('/save', (req, res) => {
  const {
    STREAM_URL, AUDIO_DEVICE, VOLUME_NORMAL, VOLUME_CALL,
    CALL_AUDIO_VOLUME, PHONE, PASSWORD, show_log
  } = req.body;

  let configChanged = false;
  const changes = [];
  function logChange(name, oldVal, newVal) {
    if (oldVal !== newVal) {
      changes.push(`${name} changed from \"${oldVal}\" to \"${newVal}\"`);
      configChanged = true;
    }
  }

  const radioLines = fs.readFileSync(RADIO_SH, 'utf-8').split('\n');
  const updatedRadio = radioLines.map(line => {
    if (/^STREAM_URL=/.test(line) && STREAM_URL) {
      logChange('STREAM_URL', line.split('=')[1].replace(/"/g, ''), STREAM_URL);
      return `STREAM_URL=\"${STREAM_URL}\"`;
    }
    if (/^AUDIO_DEVICE=/.test(line) && AUDIO_DEVICE) {
      logChange('AUDIO_DEVICE', line.split('=')[1].replace(/"/g, ''), AUDIO_DEVICE);
      return `AUDIO_DEVICE=\"${AUDIO_DEVICE}\"`;
    }
    if (/^VOLUME_NORMAL=/.test(line) && VOLUME_NORMAL) {
      logChange('VOLUME_NORMAL', line.split('=')[1], VOLUME_NORMAL);
      return `VOLUME_NORMAL=${VOLUME_NORMAL}`;
    }
    if (/^VOLUME_CALL=/.test(line) && VOLUME_CALL) {
      logChange('VOLUME_CALL', line.split('=')[1], VOLUME_CALL);
      return `VOLUME_CALL=${VOLUME_CALL}`;
    }
    if (/^CALL_AUDIO_VOLUME=/.test(line) && CALL_AUDIO_VOLUME) {
      logChange('CALL_AUDIO_VOLUME', line.split('=')[1], CALL_AUDIO_VOLUME);
      return `CALL_AUDIO_VOLUME=${CALL_AUDIO_VOLUME}`;
    }
    return line;
  });
  fs.writeFileSync(RADIO_SH, updatedRadio.join('\n'));

  if (PHONE || PASSWORD) {
    const phone = PHONE || '';
    let ha1 = '';

    const linphoneContent = fs.readFileSync(LINPHONERC, 'utf-8');
    const currentHa1Match = linphoneContent.match(/ha1=([a-f0-9]{32})/);
    const currentHa1 = currentHa1Match ? currentHa1Match[1] : '';
    const matchPhone = linphoneContent.match(/username=(.+)/);
    const currentPhone = matchPhone ? matchPhone[1] : '';

    if (PASSWORD === currentHa1) {
      ha1 = currentHa1;
    } else {
      ha1 = crypto.createHash('md5').update(`${phone}:"your domain":${PASSWORD}`).digest('hex');
    }

    if (phone !== currentPhone || ha1 !== currentHa1) {
      logChange('PHONE', currentPhone, phone);
      logChange('PASSWORD (ha1)', currentHa1, ha1);
    }

    let content = linphoneContent
      .replace(/reg_identity=sip:.*?@"your domain\.com\.au/", `reg_identity=sip:${phone}@"your domain"`)
      .replace(/username=.*/, `username=${phone}`)
      .replace(/ha1=.*/, `ha1=${ha1}`);

    fs.writeFileSync(LINPHONERC, content);
  }

  // Write config changes to log
  if (changes.length > 0) {
    const logEntry = `${new Date().toISOString().replace('T', ' ').split('.')[0]} - Config changes:\n${changes.join('\n')}\n`;
    fs.appendFileSync(RADIO_LOG, logEntry);
  }

  // Trim log entries older than 7 days
  const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;
  if (fs.existsSync(RADIO_LOG)) {
    const now = Date.now();
    const lines = fs.readFileSync(RADIO_LOG, 'utf-8').split('\n');
    const filtered = lines.filter(line => {
      const match = line.match(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/);
      if (!match) return true;
      const timestamp = new Date(match[0]).getTime();
      return now - timestamp < SEVEN_DAYS_MS;
    });
    fs.writeFileSync(RADIO_LOG, filtered.join('\n'));
  }

  setTimeout(() => {
    exec('docker restart pa', (err, stdout, stderr) => {
      if (err) console.error('Error restarting container:', stderr);
      else console.log('Container restarted:', stdout);
    });
  }, 1000);

  if (show_log) {
    const logContent = fs.existsSync(RADIO_LOG)
      ? fs.readFileSync(RADIO_LOG, 'utf-8').split('\n').reverse().join('\n')
      : 'No log file found.';
    res.send(`<pre>${logContent}</pre>`);
  } else {
    res.send('Configuration updated.');
  }
});

app.get('/audio-devices', (req, res) => {
  const uid = process.getuid();
  const pulseServer = `/run/pulse/native`;
  exec(`pactl --server=${pulseServer} list sinks short`, (err, stdout) => {
    if (err) {
      console.error('Failed to fetch audio devices:', err);
      return res.status(500).json([]);
    }
    const lines = stdout.trim().split('\n');
    const devices = lines.map(line => line.split('\t')[1]).filter(Boolean);
    res.json(devices);
  });
});

app.get('/read-log', (req, res) => {
  const logContent = fs.existsSync(RADIO_LOG)
    ? fs.readFileSync(RADIO_LOG, 'utf-8')
    : 'No log file found.';
  res.send(`<pre>${logContent}</pre>`);
});

app.post('/restart-pulse', (req, res) => {
  setTimeout(() => {
    exec('sudo /bin/systemctl restart pulseaudio.service', (err, stdout, stderr) => {
      if (err) {
        console.error('Error restarting PulseAudio:', stderr);
        return res.status(500).send('Error restarting PulseAudio');
      } else {
        console.log('PulseAudio service restarted');
        return res.send('PulseAudio restarted successfully');
      }
    });
  }, 1000);
});

app.get('/log-viewer', (req, res) => {
  let logContent = 'No log file found.';
  if (fs.existsSync(RADIO_LOG)) {
    const lines = fs.readFileSync(RADIO_LOG, 'utf-8').split('\n');
    logContent = lines.reverse().join('\n');
  }

  const html = `
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <title>radio.log</title>
      <style>
        body {
          font-family: monospace;
          padding: 20px;
          background: #f8f9fa;
          color: #333;
        }
        pre {
          white-space: pre-wrap;
          word-wrap: break-word;
          background: #fff;
          border: 1px solid #ccc;
          padding: 15px;
          border-radius: 8px;
          max-height: 90vh;
          overflow: auto;
        }
      </style>
    </head>
    <body>
      <h2>radio.log (Newest First)</h2>
      <pre>${logContent}</pre>
    </body>
    </html>
  `;

  res.send(html);
});

app.listen(PORT, () => {
  console.log(`Radio config dashboard running at http://localhost:${PORT}`);
});
