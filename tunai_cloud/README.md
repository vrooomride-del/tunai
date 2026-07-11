# TUNAI Cloud AI Orchestrator

> **Status: Experimental — Not Production Active**
>
> The current production AI path remains:
> **Flutter → Firebase Cloud Functions (`aiTune`) → Vertex AI (Gemini 2.5 Flash)**
>
> This FastAPI service is **not currently deployed or used by default.**
> The Flutter feature flag `USE_TUNAI_CLOUD_ORCHESTRATOR` defaults to `false`.
>
> This module exists to develop future TUNAI-owned orchestration, acoustic rules,
> safety validation, and DSP profile generation — capabilities that cannot be
> built inside Firebase Functions alone.
>
> **Do not switch the production Flutter path without completing:**
> - Authentication (currently absent)
> - Rate limiting (currently absent)
> - Observability / structured logging to a log aggregator
> - Load and timeout testing against Gemini API
> - End-to-end migration testing with staging app builds

---

FastAPI backend that receives acoustic tuning requests from the TUNAI mobile app
and returns safe Acoustic Intent classifications via Gemini.

**Planned architecture (not yet active):**
```
Flutter App → HTTPS → Ubuntu Server
                         → Apache/Nginx Reverse Proxy
                         → FastAPI AI Orchestrator (127.0.0.1:8100)
                         → Gemini API (remote)
```

**Principle:** AI interprets. TUNAI validates. DSP executes.

The orchestrator never generates DSP register addresses, PEQ values,
biquad coefficients, or any hardware write commands.

---

## Local development

### Requirements
- Python 3.11+
- A Gemini API key (from [Google AI Studio](https://aistudio.google.com/))

### Setup
```bash
cd tunai_cloud
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

cp .env.example .env
# Edit .env and set GEMINI_API_KEY
```

### Run
```bash
.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8100 --reload
```

### Test health
```bash
curl http://127.0.0.1:8100/health
```

### Test interpret
```bash
curl -X POST http://127.0.0.1:8100/v1/tune/interpret \
  -H "Content-Type: application/json" \
  -d '{
    "user_text": "보컬은 더 또렷하게, 저음은 덜 울리게 해줘.",
    "locale": "ko-KR",
    "speaker": {
      "model": "TUNAI ONE",
      "profile": "consumer_safe"
    }
  }'
```

### Run tests
```bash
cd tunai_cloud
python -m pytest -v
```

---

## Ubuntu deployment

### Before you deploy — gather this information

| Item | Command to check |
|------|-----------------|
| Ubuntu version | `lsb_release -a` |
| Python version | `python3 --version` |
| Web server | `systemctl status apache2 nginx` |
| Listening ports | `ss -ltnp` |
| Existing VirtualHosts | `apache2ctl -S` or `nginx -T` |
| Disk usage | `df -h` |
| RAM | `free -h` |
| Firewall | `sudo ufw status` |
| Existing SSL certs | `sudo certbot certificates` |

Do not apply any deployment steps until you have confirmed these values
and chosen your API subdomain (e.g. `api.tunai.kr`).

---

### Step 1 — Copy files to server

```bash
# From your local machine:
rsync -av --exclude='.venv' --exclude='__pycache__' --exclude='.env' \
  tunai_cloud/ user@your-server:/opt/tunai-cloud/
```

Or clone the repo directly on the server and `cd tunai_cloud/`.

---

### Step 2 — Set up Python environment

```bash
sudo mkdir -p /opt/tunai-cloud
sudo chown <YOUR_USER>:<YOUR_GROUP> /opt/tunai-cloud

cd /opt/tunai-cloud
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

---

### Step 3 — Configure .env

```bash
cp .env.example .env
nano .env
# Set: GEMINI_API_KEY, APP_ENV=production, CORS_ALLOWED_ORIGINS
```

Permissions:
```bash
chmod 600 /opt/tunai-cloud/.env
```

---

### Step 4 — Smoke test before systemd

```bash
cd /opt/tunai-cloud
source .venv/bin/activate
uvicorn app.main:app --host 127.0.0.1 --port 8100

# In another terminal:
curl http://127.0.0.1:8100/health
```

---

### Step 5 — Install systemd service

```bash
# Edit placeholder values first:
nano deploy/tunai-orchestrator.service.example
# Replace <TUNAI_SERVICE_USER> and <TUNAI_SERVICE_GROUP>

sudo cp deploy/tunai-orchestrator.service.example \
  /etc/systemd/system/tunai-orchestrator.service

sudo systemctl daemon-reload
sudo systemctl enable tunai-orchestrator
sudo systemctl start tunai-orchestrator
sudo systemctl status tunai-orchestrator
```

---

### Step 6 — Reverse proxy (choose ONE: Apache or Nginx)

#### Apache

```bash
# Required modules (only once):
sudo a2enmod proxy proxy_http ssl headers rewrite
sudo systemctl restart apache2

# Copy and edit config:
nano deploy/apache-tunai-api.conf.example
# Replace <TUNAI_API_DOMAIN> and SSL paths

sudo cp deploy/apache-tunai-api.conf.example \
  /etc/apache2/sites-available/tunai-api.conf
sudo a2ensite tunai-api

# ALWAYS validate before reload:
sudo apachectl configtest && sudo systemctl reload apache2
```

#### Nginx

```bash
nano deploy/nginx-tunai-api.conf.example
# Replace <TUNAI_API_DOMAIN> and SSL paths

sudo cp deploy/nginx-tunai-api.conf.example \
  /etc/nginx/sites-available/tunai-api
sudo ln -s /etc/nginx/sites-available/tunai-api \
  /etc/nginx/sites-enabled/

# ALWAYS validate before reload:
sudo nginx -t && sudo systemctl reload nginx
```

---

### Step 7 — HTTPS with Let's Encrypt

Before running certbot, confirm:
- DNS A record for `<TUNAI_API_DOMAIN>` points to this server
- Port 80 is open in your firewall
- The VirtualHost/server block for port 80 is active

```bash
sudo apt install certbot
# For Apache:
sudo apt install python3-certbot-apache
sudo certbot --apache -d <TUNAI_API_DOMAIN>

# For Nginx:
sudo apt install python3-certbot-nginx
sudo certbot --nginx -d <TUNAI_API_DOMAIN>
```

---

### Step 8 — Firewall

Port 8100 must NOT be publicly exposed:
```bash
# Check current rules:
sudo ufw status

# 8100 should NOT appear with ALLOW from outside.
# If it does: sudo ufw delete allow 8100
```

Only expose 80 and 443:
```bash
sudo ufw allow 'Apache Full'   # or 'Nginx Full'
```

---

### Step 9 — Log rotation

Create `/etc/logrotate.d/tunai-api`:
```
/var/log/apache2/tunai-api-*.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    postrotate
        systemctl reload apache2 > /dev/null 2>&1 || true
    endscript
}
```

For Nginx replace paths accordingly.

---

### Logs

```bash
# Service logs:
sudo journalctl -u tunai-orchestrator -f

# Access logs:
sudo tail -f /var/log/apache2/tunai-api-access.log
# or:
sudo tail -f /var/log/nginx/tunai-api-access.log
```

---

### Rollback

```bash
sudo systemctl stop tunai-orchestrator
# Restore previous code from backup or git
sudo systemctl start tunai-orchestrator
sudo systemctl status tunai-orchestrator
```

---

## Flutter integration

### Enable TUNAI Cloud (feature flag)

```bash
flutter run \
  --dart-define=USE_TUNAI_CLOUD_ORCHESTRATOR=true \
  --dart-define=TUNAI_CLOUD_BASE_URL=https://<TUNAI_API_DOMAIN>
```

### Usage in Dart

```dart
import 'package:tunai/core/tunai_cloud_service.dart';

// Check feature flag:
if (tunaiCloudEnabled) {
  final response = await TunaiCloudService().interpretTuneRequest(
    userText: '보컬은 더 또렷하게, 저음은 덜 울리게 해줘.',
    roomScan: RoomScanSummary(roomType: 'desk', soundScore: 82),
    speaker: SpeakerSummary(model: 'TUNAI ONE', profile: 'consumer_safe'),
  );
  // response.requiresConfirmation is always true
  // response.intent.bassBoom, .vocalClarity, etc.
}
```

### TODO before release
- [ ] Remove `google_generative_ai` from `pubspec.yaml` if no longer needed in app
- [ ] Confirm Firebase Functions `aiTune` is still serving existing features
- [ ] Set `TUNAI_CLOUD_BASE_URL` to production domain in CI/CD
- [ ] Remove Gemini API key from any app-level configuration
- [ ] Implement authentication on the orchestrator API

---

## Security notes

- `GEMINI_API_KEY` is only on the server, never in the Flutter app
- `.env` is in `.gitignore` — never commit it
- Uvicorn binds to `127.0.0.1` only — not publicly accessible
- Only the reverse proxy (Apache/Nginx) is exposed to the internet
- Port 8100 must not be open in the firewall
- `requires_confirmation` is always `true` — AI output is never auto-applied
