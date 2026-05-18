#!/bin/bash
set -euo pipefail

SUB2TEST_VERSION="0.1.0"
INSTALL_ROOT="/opt/sub2test"
CONFIG_DIR="/etc/sub2api"
SYSTEMD_SERVICE="/etc/systemd/system/sub2test.service"
SYSTEMD_TIMER="/etc/systemd/system/sub2test.timer"
LINK_FILE="/usr/local/bin/sub2test"
DEFAULT_SUB2API_ROOT="/opt/sub2api"
DEFAULT_COMPOSE_FILE="$DEFAULT_SUB2API_ROOT/docker-compose.yml"
DEFAULT_APP_CONFIG_FILE="$CONFIG_DIR/config.yaml"
FORCE_OVERWRITE=false

usage() {
  cat <<EOF_USAGE
Usage: sudo bash sub2test-installer.sh [options]

Options:
  --sub2api-root PATH       Set Sub2API install root (default: $DEFAULT_SUB2API_ROOT)
  --compose-file PATH       Set docker-compose.yml path explicitly
  --config-file PATH        Set Sub2API config.yaml path explicitly
  --install-root PATH       Set sub2test install root (default: /opt/sub2test)
  --config-dir PATH         Set sub2test config dir (default: /etc/sub2api)
  --link-file PATH          Set sub2test symlink path (default: /usr/local/bin/sub2test)
  --force                   Overwrite existing sub2test files
  --help                    Show this help
EOF_USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --sub2api-root)
      [ "$#" -ge 2 ] || { echo "Missing value for --sub2api-root" >&2; exit 1; }
      DEFAULT_SUB2API_ROOT="$2"
      DEFAULT_COMPOSE_FILE="$DEFAULT_SUB2API_ROOT/docker-compose.yml"
      shift 2
      ;;
    --compose-file)
      [ "$#" -ge 2 ] || { echo "Missing value for --compose-file" >&2; exit 1; }
      DEFAULT_COMPOSE_FILE="$2"
      shift 2
      ;;
    --config-file)
      [ "$#" -ge 2 ] || { echo "Missing value for --config-file" >&2; exit 1; }
      DEFAULT_APP_CONFIG_FILE="$2"
      shift 2
      ;;
    --install-root)
      [ "$#" -ge 2 ] || { echo "Missing value for --install-root" >&2; exit 1; }
      INSTALL_ROOT="$2"
      shift 2
      ;;
    --config-dir)
      [ "$#" -ge 2 ] || { echo "Missing value for --config-dir" >&2; exit 1; }
      CONFIG_DIR="$2"
      shift 2
      ;;
    --link-file)
      [ "$#" -ge 2 ] || { echo "Missing value for --link-file" >&2; exit 1; }
      LINK_FILE="$2"
      shift 2
      ;;
    --force)
      FORCE_OVERWRITE=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

CONFIG_FILE="$CONFIG_DIR/sub2test.env"
BIN_FILE="$INSTALL_ROOT/sub2test.sh"
LIB_FILE="$INSTALL_ROOT/lib.sh"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root (use sudo)." >&2
  exit 1
fi

command -v systemctl >/dev/null 2>&1 || {
  echo "systemd is required." >&2
  exit 1
}

command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required." >&2
  exit 1
}

if [ "$FORCE_OVERWRITE" != true ]; then
  if [ -e "$CONFIG_FILE" ] || [ -e "$BIN_FILE" ] || [ -e "$LIB_FILE" ] || [ -e "$SYSTEMD_SERVICE" ] || [ -e "$SYSTEMD_TIMER" ] || [ -L "$LINK_FILE" ] || [ -e "$LINK_FILE" ]; then
    echo "Existing sub2test files detected. Refusing to overwrite automatically." >&2
    echo "Please back up or remove these paths first, or rerun with --force:" >&2
    echo "  $CONFIG_FILE" >&2
    echo "  $BIN_FILE" >&2
    echo "  $LIB_FILE" >&2
    echo "  $SYSTEMD_SERVICE" >&2
    echo "  $SYSTEMD_TIMER" >&2
    echo "  $LINK_FILE" >&2
    exit 1
  fi
fi

mkdir -p "$INSTALL_ROOT" "$CONFIG_DIR"

cat > "$CONFIG_FILE" <<EOF
SUB2TEST_DEPLOY_MODE=compose
SUB2TEST_COMPOSE_FILE=$DEFAULT_COMPOSE_FILE
SUB2API_CONFIG_FILE=$DEFAULT_APP_CONFIG_FILE
SUB2TEST_DB_HOST=
SUB2TEST_DB_PORT=5432
SUB2TEST_DB_USER=
SUB2TEST_DB_PASSWORD=
SUB2TEST_DB_NAME=
SUB2TEST_DB_SSLMODE=disable
SUB2TEST_ENABLED=false
SUB2TEST_SCHEDULE=daily
SUB2TEST_CONCURRENCY=3
SUB2TEST_TIMEOUT_SECONDS=30
SUB2TEST_SLEEP_MIN_SECONDS=3
SUB2TEST_SLEEP_MAX_SECONDS=10
SUB2TEST_PERMANENT_ERROR_THRESHOLD=3
EOF

python3 - "$LIB_FILE" "$CONFIG_FILE" "$DEFAULT_COMPOSE_FILE" "$DEFAULT_APP_CONFIG_FILE" <<'PY'
from pathlib import Path
import sys

lib_path = Path(sys.argv[1])
config_file = sys.argv[2]
compose_file = sys.argv[3]
app_config_file = sys.argv[4]

content = '''#!/bin/bash
set -euo pipefail

CONFIG_FILE="${SUB2TEST_CONFIG_FILE:-__CONFIG_FILE__}"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

require_python() {
  command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }
}

require_python_module() {
  local module="$1"
  local package_name="$2"
  require_python
  if ! python3 -c 'import importlib, sys; importlib.import_module(sys.argv[1])' "$module"; then
    echo "$package_name is required" >&2
    exit 1
  fi
}

save_config_value() {
  local key="$1"
  local value="$2"
  python3 - "$CONFIG_FILE" "$key" "$value" <<'PY_SAVE_CONFIG'
from pathlib import Path
import sys
path = Path(sys.argv[1])
key = sys.argv[2]
value = sys.argv[3]
lines = []
if path.exists():
    lines = path.read_text(encoding='utf-8').splitlines()
out = []
updated = False
for line in lines:
    if line.startswith(key + '='):
        out.append(f"{key}={value}")
        updated = True
    else:
        out.append(line)
if not updated:
    out.append(f"{key}={value}")
path.write_text("\\n".join(out) + "\\n", encoding='utf-8')
PY_SAVE_CONFIG
}

systemd_calendar() {
  case "${SUB2TEST_SCHEDULE:-daily}" in
    hourly) echo "hourly" ;;
    daily) echo "daily" ;;
    weekly) echo "weekly" ;;
    *) echo "daily" ;;
  esac
}

render_timer() {
  cat > /etc/systemd/system/sub2test.timer <<EOF_TIMER
[Unit]
Description=Run sub2test periodically

[Timer]
OnCalendar=$(systemd_calendar)
Persistent=true
RandomizedDelaySec=120
Unit=sub2test.service

[Install]
WantedBy=timers.target
EOF_TIMER
}

preflight_config_source() {
  if [ -n "${SUB2TEST_DB_HOST:-}" ] && [ -n "${SUB2TEST_DB_USER:-}" ] && [ -n "${SUB2TEST_DB_NAME:-}" ]; then
    return 0
  fi

  local deploy_mode="${SUB2TEST_DEPLOY_MODE:-compose}"
  local compose_file="${SUB2TEST_COMPOSE_FILE:-__COMPOSE_FILE__}"
  local app_config="${SUB2API_CONFIG_FILE:-__APP_CONFIG_FILE__}"

  if [ "$deploy_mode" = "compose" ] && [ -f "$compose_file" ]; then
    return 0
  fi

  if [ -f "$app_config" ]; then
    return 0
  fi

  echo "No usable config source found. Set SUB2TEST_DB_* explicitly, or provide SUB2TEST_COMPOSE_FILE / SUB2API_CONFIG_FILE." >&2
  exit 1
}

resolve_db_config() {
  require_python
  python3 - <<'PY_RESOLVE_DB'
import os
import re
import sys
from pathlib import Path

def output(host, port, user, password, dbname, sslmode):
    print(f"SUB2TEST_DB_HOST={host}")
    print(f"SUB2TEST_DB_PORT={port}")
    print(f"SUB2TEST_DB_USER={user}")
    print(f"SUB2TEST_DB_PASSWORD={password}")
    print(f"SUB2TEST_DB_NAME={dbname}")
    print(f"SUB2TEST_DB_SSLMODE={sslmode}")

def load_dotenv(env_path: Path):
    values = {}
    if not env_path.exists():
        return values
    for raw_line in env_path.read_text(encoding='utf-8').splitlines():
        line = raw_line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, value = line.split('=', 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        values[key] = value
    return values

def resolve_value(raw: str, env_values: dict[str, str], default: str = ''):
    raw = (raw or '').strip()
    if not raw:
        return default
    if raw.startswith('${') and raw.endswith('}'):
        inner = raw[2:-1]
        if ':-' in inner:
            key, fallback = inner.split(':-', 1)
            return env_values.get(key, os.getenv(key, fallback)) or fallback
        if ':?' in inner:
            key, message = inner.split(':?', 1)
            value = env_values.get(key, os.getenv(key, ''))
            if not value:
                print(f"Missing required compose variable: {key} ({message})", file=sys.stderr)
                sys.exit(1)
            return value
        return env_values.get(inner, os.getenv(inner, default)) or default
    return raw

host = os.getenv('SUB2TEST_DB_HOST', '').strip()
port = os.getenv('SUB2TEST_DB_PORT', '').strip()
user = os.getenv('SUB2TEST_DB_USER', '').strip()
password = os.getenv('SUB2TEST_DB_PASSWORD', '').strip()
dbname = os.getenv('SUB2TEST_DB_NAME', '').strip()
sslmode = os.getenv('SUB2TEST_DB_SSLMODE', 'disable').strip() or 'disable'
if host and user and dbname:
    output(host, port or '5432', user, password, dbname, sslmode)
    sys.exit(0)

deploy_mode = os.getenv('SUB2TEST_DEPLOY_MODE', 'compose').strip().lower()
compose_file = Path(os.getenv('SUB2TEST_COMPOSE_FILE', '__COMPOSE_FILE__'))
app_config = Path(os.getenv('SUB2API_CONFIG_FILE', '__APP_CONFIG_FILE__'))

if deploy_mode == 'compose' and compose_file.exists():
    text = compose_file.read_text(encoding='utf-8')
    dotenv = load_dotenv(compose_file.parent / '.env')

    def find_env_value(name, default=''):
        patterns = [
            rf'^\\s*-\\s*{name}=(.+)$',
            rf'^\\s+{name}:\\s*["\\']?([^"\\'\\n]+)["\\']?\\s*$',
        ]
        for pattern in patterns:
            match = re.search(pattern, text, re.MULTILINE)
            if match:
                return resolve_value(match.group(1).strip(), dotenv, default)
        return default

    host = find_env_value('DATABASE_HOST', 'postgres')
    port = find_env_value('DATABASE_PORT', '5432')
    user = find_env_value('DATABASE_USER', '')
    password = find_env_value('DATABASE_PASSWORD', '')
    dbname = find_env_value('DATABASE_DBNAME', '')
    sslmode = find_env_value('DATABASE_SSLMODE', 'disable') or 'disable'
    output(host, port, user, password, dbname, sslmode)
    sys.exit(0)

if app_config.exists():
    try:
        import yaml
    except Exception:
        print('python3-yaml is required', file=sys.stderr)
        sys.exit(1)
    cfg = yaml.safe_load(app_config.read_text(encoding='utf-8')) or {}
    db = cfg.get('database') or {}
    output(
        db.get('host', ''),
        str(db.get('port', 5432)),
        db.get('user', ''),
        db.get('password', ''),
        db.get('dbname', ''),
        db.get('sslmode', 'disable') or 'disable',
    )
    sys.exit(0)

print('Unable to resolve database config', file=sys.stderr)
sys.exit(1)
PY_RESOLVE_DB
}

preflight_runtime() {
  require_python_module yaml python3-yaml
  require_python_module psycopg2 python3-psycopg2
  require_python_module requests python3-requests
  preflight_config_source
  eval "$(resolve_db_config)"
  export SUB2TEST_DB_HOST SUB2TEST_DB_PORT SUB2TEST_DB_USER SUB2TEST_DB_PASSWORD SUB2TEST_DB_NAME SUB2TEST_DB_SSLMODE
  python3 - <<'PY_PREFLIGHT_RUNTIME'
import os
import sys
import psycopg2

required = ['SUB2TEST_DB_HOST', 'SUB2TEST_DB_PORT', 'SUB2TEST_DB_USER', 'SUB2TEST_DB_NAME']
missing = [k for k in required if not os.getenv(k)]
if missing:
    print('database config missing: ' + ', '.join(missing), file=sys.stderr)
    sys.exit(1)

conn = psycopg2.connect(
    host=os.environ['SUB2TEST_DB_HOST'],
    port=os.environ['SUB2TEST_DB_PORT'],
    user=os.environ['SUB2TEST_DB_USER'],
    password=os.getenv('SUB2TEST_DB_PASSWORD', ''),
    dbname=os.environ['SUB2TEST_DB_NAME'],
    sslmode=os.getenv('SUB2TEST_DB_SSLMODE', 'disable'),
)
cur = conn.cursor()
cur.execute('SELECT 1')
cur.fetchone()
cur.execute("SELECT to_regclass('public.accounts')")
if cur.fetchone()[0] is None:
    print('accounts table not found', file=sys.stderr)
    sys.exit(1)
cur.execute(
    """
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'accounts'
    """
)
columns = {row[0] for row in cur.fetchall()}
required_columns = {'deleted_at', 'status', 'platform', 'type'}
missing_columns = sorted(required_columns - columns)
if missing_columns:
    print('accounts table columns missing: ' + ', '.join(missing_columns), file=sys.stderr)
    sys.exit(1)
cur.close()
conn.close()
print('preflight checks passed')
PY_PREFLIGHT_RUNTIME
}

run_health_check() {
  preflight_runtime
  python3 - <<'PY_RUN_HEALTH_CHECK'
import json
import os
import random
import sys
import time

import psycopg2
import requests

def get_env(name: str, default: str = '') -> str:
    return (os.getenv(name, default) or '').strip()

sleep_min = int(get_env('SUB2TEST_SLEEP_MIN_SECONDS', '3') or '3')
sleep_max = int(get_env('SUB2TEST_SLEEP_MAX_SECONDS', '10') or '10')
timeout_seconds = int(get_env('SUB2TEST_TIMEOUT_SECONDS', '30') or '30')
concurrency = int(get_env('SUB2TEST_CONCURRENCY', '3') or '3')

conn = psycopg2.connect(
    host=os.environ['SUB2TEST_DB_HOST'],
    port=os.environ['SUB2TEST_DB_PORT'],
    user=os.environ['SUB2TEST_DB_USER'],
    password=os.getenv('SUB2TEST_DB_PASSWORD', ''),
    dbname=os.environ['SUB2TEST_DB_NAME'],
    sslmode=os.getenv('SUB2TEST_DB_SSLMODE', 'disable'),
)
cur = conn.cursor()
cur.execute(
    """
    SELECT id, name, platform, type, status, error_message, credentials, extra
    FROM accounts
    WHERE deleted_at IS NULL AND status = 'active'
    ORDER BY priority ASC, id ASC
    """
)
rows = cur.fetchall()
cur.close()
conn.close()

print(f'loaded {len(rows)} active accounts (configured concurrency={concurrency})')
if not rows:
    sys.exit(0)

session = requests.Session()
headers = {'Accept': 'text/event-stream'}

def as_dict(value):
    if isinstance(value, dict):
        return value
    if value is None:
        return {}
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
            return parsed if isinstance(parsed, dict) else {}
        except Exception:
            return {}
    return {}

claude_api_url = 'https://api.anthropic.com/v1/messages?beta=true'
openai_api_url = 'https://api.openai.com/v1/responses'
gemini_api_url = 'https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent'

def choose_model(platform: str, account_type: str, credentials: dict, extra: dict) -> str:
    platform = (platform or '').lower()
    if platform == 'openai':
        return 'gpt-5.4'
    if platform == 'gemini':
        return 'gemini-2.0-flash'
    return 'claude-sonnet-4-5-20250929'

for account_id, name, platform, account_type, status, error_message, credentials_raw, extra_raw in rows:
    credentials = as_dict(credentials_raw)
    extra = as_dict(extra_raw)
    model = choose_model(platform, account_type, credentials, extra)
    started = time.time()
    ok = False
    detail = ''

    try:
        platform_key = (platform or '').lower()
        type_key = (account_type or '').lower()

        if platform_key == 'openai':
            if type_key == 'oauth':
                token = (credentials.get('access_token') or '').strip()
                if not token:
                    raise RuntimeError('missing access_token')
                payload = {
                    'model': model,
                    'input': 'hi',
                    'max_output_tokens': 32,
                }
                response = session.post(
                    openai_api_url,
                    headers={**headers, 'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'},
                    json=payload,
                    timeout=timeout_seconds,
                )
            elif type_key == 'apikey':
                api_key = (credentials.get('api_key') or '').strip()
                if not api_key:
                    raise RuntimeError('missing api_key')
                base_url = (credentials.get('base_url') or 'https://api.openai.com').rstrip('/')
                payload = {
                    'model': model,
                    'input': 'hi',
                    'max_output_tokens': 32,
                }
                response = session.post(
                    f'{base_url}/v1/responses',
                    headers={**headers, 'Authorization': f'Bearer {api_key}', 'Content-Type': 'application/json'},
                    json=payload,
                    timeout=timeout_seconds,
                )
            else:
                raise RuntimeError(f'unsupported openai account type: {account_type}')
        elif platform_key == 'gemini':
            api_key = (credentials.get('api_key') or '').strip()
            if not api_key:
                raise RuntimeError('missing api_key')
            payload = {
                'contents': [
                    {
                        'parts': [
                            {'text': 'hi'}
                        ]
                    }
                ]
            }
            response = session.post(
                gemini_api_url.format(model=model),
                params={'key': api_key},
                headers={'Content-Type': 'application/json'},
                json=payload,
                timeout=timeout_seconds,
            )
        elif platform_key in ('anthropic', 'claude'):
            payload = {
                'model': model,
                'messages': [
                    {
                        'role': 'user',
                        'content': 'hi',
                    }
                ],
                'max_tokens': 32,
                'stream': False,
            }
            if type_key in ('oauth', 'setup_token'):
                token = (credentials.get('access_token') or '').strip()
                if not token:
                    raise RuntimeError('missing access_token')
                response = session.post(
                    claude_api_url,
                    headers={
                        'Authorization': f'Bearer {token}',
                        'Content-Type': 'application/json',
                        'anthropic-version': '2023-06-01',
                    },
                    json=payload,
                    timeout=timeout_seconds,
                )
            elif type_key == 'apikey':
                api_key = (credentials.get('api_key') or '').strip()
                if not api_key:
                    raise RuntimeError('missing api_key')
                base_url = (credentials.get('base_url') or 'https://api.anthropic.com').rstrip('/')
                response = session.post(
                    f'{base_url}/v1/messages?beta=true',
                    headers={
                        'x-api-key': api_key,
                        'Content-Type': 'application/json',
                        'anthropic-version': '2023-06-01',
                    },
                    json=payload,
                    timeout=timeout_seconds,
                )
            else:
                raise RuntimeError(f'unsupported anthropic account type: {account_type}')
        else:
            raise RuntimeError(f'unsupported platform: {platform}')

        ok = 200 <= response.status_code < 300
        body = response.text.strip().replace('\\n', ' ')
        detail = body[:300] if body else response.reason
        if not ok:
            detail = f'http {response.status_code}: {detail}'
    except Exception as exc:
        detail = str(exc)

    latency_ms = int((time.time() - started) * 1000)
    result = 'success' if ok else 'failed'
    display_name = (name or '').strip() or f'account-{account_id}'
    print(f'[{result}] account={account_id} name={display_name} platform={platform} type={account_type} model={model} latency_ms={latency_ms} detail={detail}')

    if sleep_max <= sleep_min:
        time.sleep(max(sleep_min, 0))
    else:
        time.sleep(random.randint(max(sleep_min, 0), max(sleep_max, sleep_min)))
PY_RUN_HEALTH_CHECK
}
'''
content = content.replace('__CONFIG_FILE__', config_file)
content = content.replace('__COMPOSE_FILE__', compose_file)
content = content.replace('__APP_CONFIG_FILE__', app_config_file)
lib_path.write_text(content, encoding='utf-8')
PY
chmod +x "$LIB_FILE"

python3 - "$BIN_FILE" "$CONFIG_FILE" "$DEFAULT_COMPOSE_FILE" "$DEFAULT_APP_CONFIG_FILE" "$LINK_FILE" "$INSTALL_ROOT" <<'PY'
from pathlib import Path
import sys

bin_path = Path(sys.argv[1])
config_file = sys.argv[2]
compose_file = sys.argv[3]
app_config_file = sys.argv[4]
link_file = sys.argv[5]
install_root = sys.argv[6]

content = '''#!/bin/bash
set -euo pipefail

export SUB2TEST_CONFIG_FILE="${SUB2TEST_CONFIG_FILE:-__CONFIG_FILE__}"
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || printf '%s\n' "$0")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
. "$SCRIPT_DIR/lib.sh"
[ -f "$SUB2TEST_CONFIG_FILE" ] && . "$SUB2TEST_CONFIG_FILE"

show_config() {
  echo "SUB2TEST_DEPLOY_MODE=${SUB2TEST_DEPLOY_MODE:-compose}"
  echo "SUB2TEST_COMPOSE_FILE=${SUB2TEST_COMPOSE_FILE:-__COMPOSE_FILE__}"
  echo "SUB2API_CONFIG_FILE=${SUB2API_CONFIG_FILE:-__APP_CONFIG_FILE__}"
  echo "SUB2TEST_DB_HOST=${SUB2TEST_DB_HOST:-}"
  echo "SUB2TEST_DB_PORT=${SUB2TEST_DB_PORT:-5432}"
  echo "SUB2TEST_DB_USER=${SUB2TEST_DB_USER:-}"
  echo "SUB2TEST_DB_NAME=${SUB2TEST_DB_NAME:-}"
  echo "SUB2TEST_DB_SSLMODE=${SUB2TEST_DB_SSLMODE:-disable}"
  echo "SUB2TEST_ENABLED=${SUB2TEST_ENABLED:-false}"
  echo "SUB2TEST_SCHEDULE=${SUB2TEST_SCHEDULE:-daily}"
  echo "SUB2TEST_CONCURRENCY=${SUB2TEST_CONCURRENCY:-3}"
  echo "SUB2TEST_TIMEOUT_SECONDS=${SUB2TEST_TIMEOUT_SECONDS:-30}"
  echo "SUB2TEST_SLEEP_MIN_SECONDS=${SUB2TEST_SLEEP_MIN_SECONDS:-3}"
  echo "SUB2TEST_SLEEP_MAX_SECONDS=${SUB2TEST_SLEEP_MAX_SECONDS:-10}"
  echo "SUB2TEST_PERMANENT_ERROR_THRESHOLD=${SUB2TEST_PERMANENT_ERROR_THRESHOLD:-3}"
}

edit_value() {
  local key="$1"
  local current="$2"
  read -r -p "$key [$current]: " input
  if [ -n "$input" ]; then
    save_config_value "$key" "$input"
    . "$SUB2TEST_CONFIG_FILE"
  fi
}

enable_task() {
  preflight_runtime
  save_config_value SUB2TEST_ENABLED true
  render_timer
  systemctl daemon-reload
  systemctl enable --now sub2test.timer
  echo "sub2test timer enabled"
}

disable_task() {
  save_config_value SUB2TEST_ENABLED false
  systemctl disable --now sub2test.timer || true
  echo "sub2test timer disabled"
}

edit_config() {
  edit_value SUB2TEST_DEPLOY_MODE "${SUB2TEST_DEPLOY_MODE:-compose}"
  edit_value SUB2TEST_COMPOSE_FILE "${SUB2TEST_COMPOSE_FILE:-__COMPOSE_FILE__}"
  edit_value SUB2API_CONFIG_FILE "${SUB2API_CONFIG_FILE:-__APP_CONFIG_FILE__}"
  edit_value SUB2TEST_DB_HOST "${SUB2TEST_DB_HOST:-}"
  edit_value SUB2TEST_DB_PORT "${SUB2TEST_DB_PORT:-5432}"
  edit_value SUB2TEST_DB_USER "${SUB2TEST_DB_USER:-}"
  edit_value SUB2TEST_DB_PASSWORD "${SUB2TEST_DB_PASSWORD:-}"
  edit_value SUB2TEST_DB_NAME "${SUB2TEST_DB_NAME:-}"
  edit_value SUB2TEST_DB_SSLMODE "${SUB2TEST_DB_SSLMODE:-disable}"
  edit_value SUB2TEST_SCHEDULE "${SUB2TEST_SCHEDULE:-daily}"
  edit_value SUB2TEST_CONCURRENCY "${SUB2TEST_CONCURRENCY:-3}"
  edit_value SUB2TEST_TIMEOUT_SECONDS "${SUB2TEST_TIMEOUT_SECONDS:-30}"
  edit_value SUB2TEST_SLEEP_MIN_SECONDS "${SUB2TEST_SLEEP_MIN_SECONDS:-3}"
  edit_value SUB2TEST_SLEEP_MAX_SECONDS "${SUB2TEST_SLEEP_MAX_SECONDS:-10}"
  edit_value SUB2TEST_PERMANENT_ERROR_THRESHOLD "${SUB2TEST_PERMANENT_ERROR_THRESHOLD:-3}"
  preflight_runtime
  render_timer
  systemctl daemon-reload
  if systemctl is-enabled sub2test.timer >/dev/null 2>&1; then
    systemctl restart sub2test.timer
  fi
}

uninstall_self() {
  systemctl disable --now sub2test.timer || true
  rm -f /etc/systemd/system/sub2test.service /etc/systemd/system/sub2test.timer "__LINK_FILE__"
  rm -rf "__INSTALL_ROOT__"
  echo "sub2test removed"
}

run_once() {
  . "$SUB2TEST_CONFIG_FILE"
  export SUB2TEST_DEPLOY_MODE SUB2TEST_COMPOSE_FILE SUB2API_CONFIG_FILE
  export SUB2TEST_DB_HOST SUB2TEST_DB_PORT SUB2TEST_DB_USER SUB2TEST_DB_PASSWORD SUB2TEST_DB_NAME SUB2TEST_DB_SSLMODE
  export SUB2TEST_SLEEP_MIN_SECONDS SUB2TEST_SLEEP_MAX_SECONDS
  run_health_check
}

menu() {
  while true; do
    echo
    echo "sub2test menu"
    echo "1) Enable automatic task"
    echo "2) Disable automatic task"
    echo "3) Edit parameters"
    echo "4) Run once now"
    echo "5) Show current config"
    echo "6) Uninstall script and timer"
    echo "7) Exit"
    read -r -p "> " choice
    case "$choice" in
      1) enable_task ;;
      2) disable_task ;;
      3) edit_config ;;
      4) run_once ;;
      5) show_config ;;
      6) uninstall_self; exit 0 ;;
      7) exit 0 ;;
      *) echo "Unknown choice" ;;
    esac
  done
}

case "${1:-menu}" in
  run-once) run_once ;;
  show-config) show_config ;;
  enable) enable_task ;;
  disable) disable_task ;;
  menu) menu ;;
  *) echo "Usage: sub2test [menu|run-once|show-config|enable|disable]" >&2; exit 1 ;;
esac
'''
content = content.replace('__CONFIG_FILE__', config_file)
content = content.replace('__COMPOSE_FILE__', compose_file)
content = content.replace('__APP_CONFIG_FILE__', app_config_file)
content = content.replace('__LINK_FILE__', link_file)
content = content.replace('__INSTALL_ROOT__', install_root)
bin_path.write_text(content, encoding='utf-8')
PY
chmod +x "$BIN_FILE"

cat > "$SYSTEMD_SERVICE" <<EOF
[Unit]
Description=Sub2API external sub2test runner
After=network.target

[Service]
Type=oneshot
ExecStart=$LINK_FILE run-once
EOF

cat > "$SYSTEMD_TIMER" <<'EOF'
[Unit]
Description=Run sub2test periodically

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=120
Unit=sub2test.service

[Install]
WantedBy=timers.target
EOF

ln -sf "$BIN_FILE" "$LINK_FILE"
systemctl daemon-reload

echo "sub2test installed"
echo "Config: $CONFIG_FILE"
echo "Command: $LINK_FILE"
echo "Sub2API root: $DEFAULT_SUB2API_ROOT"
echo "Compose file: $DEFAULT_COMPOSE_FILE"
echo "App config: $DEFAULT_APP_CONFIG_FILE"
echo "Enable timer: systemctl enable --now sub2test.timer"
