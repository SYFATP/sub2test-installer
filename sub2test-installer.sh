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
SUB2TEST_DB_CONTAINER=
SUB2TEST_API_BASE_URL=
SUB2TEST_ADMIN_API_KEY=
SUB2TEST_ENABLED=false
SUB2TEST_SCHEDULE=daily
SUB2TEST_CONCURRENCY=3
SUB2TEST_TIMEOUT_SECONDS=30
SUB2TEST_SLEEP_MIN_SECONDS=3
SUB2TEST_SLEEP_MAX_SECONDS=10
EOF

python3 - "$LIB_FILE" "$CONFIG_FILE" "$DEFAULT_COMPOSE_FILE" "$DEFAULT_APP_CONFIG_FILE" <<'PY'
from pathlib import Path
import sys

lib_path = Path(sys.argv[1])
config_file = sys.argv[2]
compose_file = sys.argv[3]
app_config_file = sys.argv[4]

content = r'''#!/bin/bash
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
path.write_text("\n".join(out) + "\n", encoding='utf-8')
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
  if [ -n "${SUB2TEST_DB_CONTAINER:-}" ]; then
    return 0
  fi

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

def output(host, port, user, password, dbname, sslmode, container=''):
    print(f"SUB2TEST_DB_HOST={host}")
    print(f"SUB2TEST_DB_PORT={port}")
    print(f"SUB2TEST_DB_USER={user}")
    print(f"SUB2TEST_DB_PASSWORD={password}")
    print(f"SUB2TEST_DB_NAME={dbname}")
    print(f"SUB2TEST_DB_SSLMODE={sslmode}")
    print(f"SUB2TEST_DB_CONTAINER={container}")

def load_dotenv(env_path: Path):
    values = {}
    if not env_path.exists():
        return values
    for raw_line in env_path.read_text(encoding='utf-8').splitlines():
        line = raw_line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, value = line.split('=', 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values

def parse_compose(path: Path):
    text = path.read_text(encoding='utf-8')
    env_match = re.search(r'\n\s+db:\n([\s\S]*?)(?:\n\S|\Z)', text)
    body = env_match.group(1) if env_match else text
    def env_value(key):
        patterns = [
            rf'^\s+-\s*{key}=(.+)$',
            rf'^\s+{key}:\s*["\']?(.+?)["\']?$',
        ]
        for pattern in patterns:
            match = re.search(pattern, text, re.MULTILINE | re.DOTALL)
            if match:
                return match.group(1).strip().strip('"').strip("'")
        inline_match = re.search(rf'^\s+{key}:\s*(.+)$', body, re.MULTILINE)
        if inline_match:
            return inline_match.group(1).strip().strip('"').strip("'")
        return ''

    container_match = re.search(r'^\s*container_name:\s*([^\s#]+)\s*$', text, re.MULTILINE)
    container_name = container_match.group(1).strip() if container_match else ''
    return {
        'host': env_value('POSTGRES_HOST') or 'db',
        'port': env_value('POSTGRES_PORT') or '5432',
        'user': env_value('POSTGRES_USER') or 'postgres',
        'password': env_value('POSTGRES_PASSWORD'),
        'dbname': env_value('POSTGRES_DB') or 'sub2api',
        'sslmode': 'disable',
        'container': container_name,
    }

explicit = {
    'host': os.getenv('SUB2TEST_DB_HOST', '').strip(),
    'port': os.getenv('SUB2TEST_DB_PORT', '').strip(),
    'user': os.getenv('SUB2TEST_DB_USER', '').strip(),
    'password': os.getenv('SUB2TEST_DB_PASSWORD', '').strip(),
    'dbname': os.getenv('SUB2TEST_DB_NAME', '').strip(),
    'sslmode': os.getenv('SUB2TEST_DB_SSLMODE', 'disable').strip() or 'disable',
    'container': os.getenv('SUB2TEST_DB_CONTAINER', '').strip(),
}
if explicit['container']:
    output(explicit['host'], explicit['port'] or '5432', explicit['user'], explicit['password'], explicit['dbname'], explicit['sslmode'], explicit['container'])
    sys.exit(0)
if explicit['host'] and explicit['user'] and explicit['dbname']:
    output(explicit['host'], explicit['port'] or '5432', explicit['user'], explicit['password'], explicit['dbname'], explicit['sslmode'], '')
    sys.exit(0)

compose_path = Path(os.getenv('SUB2TEST_COMPOSE_FILE', '__COMPOSE_FILE__'))
if compose_path.exists():
    compose_values = parse_compose(compose_path)
    output(
        compose_values['host'],
        compose_values['port'],
        compose_values['user'],
        compose_values['password'],
        compose_values['dbname'],
        compose_values['sslmode'],
        compose_values['container'],
    )
    sys.exit(0)

app_config = Path(os.getenv('SUB2API_CONFIG_FILE', '__APP_CONFIG_FILE__'))
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

preflight_api_config() {
  local api_base_url="${SUB2TEST_API_BASE_URL:-}"
  local admin_api_key="${SUB2TEST_ADMIN_API_KEY:-}"

  if [ -z "$api_base_url" ]; then
    echo "SUB2TEST_API_BASE_URL is required" >&2
    exit 1
  fi

  if [ -z "$admin_api_key" ]; then
    echo "SUB2TEST_ADMIN_API_KEY is required" >&2
    exit 1
  fi
}

preflight_runtime() {
  require_python_module yaml python3-yaml
  require_python_module psycopg2 python3-psycopg2
  require_python_module requests python3-requests
  preflight_config_source
  preflight_api_config
  eval "$(resolve_db_config)"
  export SUB2TEST_DB_HOST SUB2TEST_DB_PORT SUB2TEST_DB_USER SUB2TEST_DB_PASSWORD SUB2TEST_DB_NAME SUB2TEST_DB_SSLMODE SUB2TEST_DB_CONTAINER
  if [ -n "${SUB2TEST_DB_CONTAINER:-}" ]; then
    docker exec "$SUB2TEST_DB_CONTAINER" sh -lc 'command -v psql >/dev/null 2>&1' || {
      echo "psql is required inside DB container: $SUB2TEST_DB_CONTAINER" >&2
      exit 1
    }
    docker exec \
      -e PGPASSWORD="$SUB2TEST_DB_PASSWORD" \
      "$SUB2TEST_DB_CONTAINER" \
      psql -U "$SUB2TEST_DB_USER" -d "$SUB2TEST_DB_NAME" -Atqc 'SELECT 1' >/dev/null || {
      echo "database preflight failed via container: $SUB2TEST_DB_CONTAINER" >&2
      exit 1
    }
    docker exec \
      -e PGPASSWORD="$SUB2TEST_DB_PASSWORD" \
      "$SUB2TEST_DB_CONTAINER" \
      psql -U "$SUB2TEST_DB_USER" -d "$SUB2TEST_DB_NAME" -Atqc "SELECT to_regclass('public.accounts')" | grep -qx 'accounts' || {
      echo "accounts table not found" >&2
      exit 1
    }
    local columns
    columns="$(docker exec \
      -e PGPASSWORD="$SUB2TEST_DB_PASSWORD" \
      "$SUB2TEST_DB_CONTAINER" \
      psql -U "$SUB2TEST_DB_USER" -d "$SUB2TEST_DB_NAME" -Atqc "SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'accounts'")"
    printf '%s\n' "$columns" | grep -qx 'deleted_at' || { echo "accounts table columns missing: deleted_at" >&2; exit 1; }
    printf '%s\n' "$columns" | grep -qx 'status' || { echo "accounts table columns missing: status" >&2; exit 1; }
    printf '%s\n' "$columns" | grep -qx 'platform' || { echo "accounts table columns missing: platform" >&2; exit 1; }
    printf '%s\n' "$columns" | grep -qx 'type' || { echo "accounts table columns missing: type" >&2; exit 1; }
    echo "preflight checks passed"
    return 0
  fi
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
  local accounts_json
  accounts_json="$(mktemp)"
  local accounts_tsv=""
  trap 'rm -f "$accounts_json" "$accounts_tsv"' RETURN

  if [ -n "${SUB2TEST_DB_CONTAINER:-}" ]; then
    accounts_tsv="$(mktemp)"
    docker exec \
      -e PGPASSWORD="$SUB2TEST_DB_PASSWORD" \
      "$SUB2TEST_DB_CONTAINER" \
      psql -U "$SUB2TEST_DB_USER" -d "$SUB2TEST_DB_NAME" -F $'\t' -Atqc "SELECT id, COALESCE(name, ''), platform, type, status, COALESCE(credentials::text, '{}'), COALESCE(extra::text, '{}') FROM accounts WHERE deleted_at IS NULL AND status IN ('error', 'active') ORDER BY CASE WHEN status = 'error' THEN 0 ELSE 1 END, priority ASC, id ASC" > "$accounts_tsv"
    python3 - "$accounts_tsv" "$accounts_json" <<'PY_EXPORT_CONTAINER_ACCOUNTS'
import json
import sys

input_path = sys.argv[1]
output_path = sys.argv[2]

with open(input_path, 'r', encoding='utf-8') as src, open(output_path, 'w', encoding='utf-8') as out:
    for raw_line in src:
        line = raw_line.rstrip('\n')
        if not line:
            continue
        parts = line.split('\t', 6)
        if len(parts) != 7:
            continue
        account_id, name, platform, account_type, status, credentials_text, extra_text = parts
        try:
            credentials = json.loads(credentials_text) if credentials_text else {}
        except Exception:
            credentials = {}
        try:
            extra = json.loads(extra_text) if extra_text else {}
        except Exception:
            extra = {}
        out.write(json.dumps({
            'id': int(account_id),
            'name': name,
            'platform': platform,
            'type': account_type,
            'status': status,
            'credentials': credentials,
            'extra': extra,
        }, ensure_ascii=False) + '\n')
PY_EXPORT_CONTAINER_ACCOUNTS
  else
    python3 - "$accounts_json" <<'PY_EXPORT_ACCOUNTS'
import json
import os
import sys

import psycopg2

output_path = sys.argv[1]

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
    SELECT id, name, platform, type, status, credentials, extra
    FROM accounts
    WHERE deleted_at IS NULL AND status IN ('error', 'active')
    ORDER BY CASE WHEN status = 'error' THEN 0 ELSE 1 END, priority ASC, id ASC
    """
)
rows = cur.fetchall()
cur.close()
conn.close()

with open(output_path, 'w', encoding='utf-8') as fh:
    for account_id, name, platform, account_type, status, credentials, extra in rows:
        fh.write(json.dumps({
            'id': account_id,
            'name': name or '',
            'platform': platform,
            'type': account_type,
            'status': status,
            'credentials': credentials,
            'extra': extra,
        }, ensure_ascii=False) + '\n')
PY_EXPORT_ACCOUNTS
  fi

  python3 - "$accounts_json" <<'PY_RUN_HEALTH_CHECK'
import json
import os
import random
import signal
import sys
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor

import requests

def get_env(name: str, default: str = '') -> str:
    return (os.getenv(name, default) or '').strip()

def summarize_credentials(credentials: dict) -> str:
    if not isinstance(credentials, dict):
        return 'credentials=none'
    if credentials.get('email'):
        return f"email={credentials['email']}"
    return 'credentials=present'

def shorten_detail(detail: str) -> str:
    detail = (detail or '').strip().replace('\\n', ' ')
    detail = ' '.join(detail.split())
    return detail[:180]

sleep_min = int(get_env('SUB2TEST_SLEEP_MIN_SECONDS', '3') or '3')
sleep_max = int(get_env('SUB2TEST_SLEEP_MAX_SECONDS', '10') or '10')
timeout_seconds = int(get_env('SUB2TEST_TIMEOUT_SECONDS', '30') or '30')
batch_size = max(int(get_env('SUB2TEST_CONCURRENCY', '3') or '3'), 1)
rows_file = sys.argv[1]
with open(rows_file, 'r', encoding='utf-8') as fh:
    rows = [json.loads(line) for line in fh if line.strip()]
print(f'loaded {len(rows)} accounts (batch_size={batch_size})')
if not rows:
    sys.exit(0)

counts = Counter()
status_counts = Counter()
pipe_closed = False


def handle_sigpipe(signum, frame):
    raise BrokenPipeError()


signal.signal(signal.SIGPIPE, handle_sigpipe)

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


def parse_sse_events(response):
    event_buffer = []
    for raw_line in response.iter_lines(decode_unicode=True):
        if raw_line is None:
            continue
        line = raw_line.strip()
        if line == '':
            if event_buffer:
                payload = '\n'.join(event_buffer).strip()
                event_buffer.clear()
                if payload:
                    yield payload
            continue
        if line.startswith('data:'):
            event_buffer.append(line[5:].strip())
    if event_buffer:
        payload = '\n'.join(event_buffer).strip()
        if payload:
            yield payload


def classify_api_result(http_status: int | None, saw_success: bool) -> str:
    if saw_success:
        return 'success'
    if http_status == 429:
        return 'rate_limited'
    if http_status == 401:
        return 'error'
    return 'failed'


def run_account_test(row):
    account_id = row.get('id', '')
    name = row.get('name', '')
    platform = row.get('platform', '')
    account_type = row.get('type', '')
    source_status = row.get('status', '')
    credentials = as_dict(row.get('credentials'))
    started = time.time()
    result_text = ''
    saw_success = False
    http_status = None
    error_text = ''

    try:
        with requests.Session() as session:
            response = session.post(
                f"{get_env('SUB2TEST_API_BASE_URL').rstrip('/')}/admin/accounts/{account_id}/test",
                headers={
                    'x-api-key': get_env('SUB2TEST_ADMIN_API_KEY'),
                    'Content-Type': 'application/json',
                    'Accept': 'text/event-stream',
                },
                json={},
                timeout=timeout_seconds,
                stream=True,
            )
            http_status = response.status_code
            if response.status_code != 200:
                error_text = shorten_detail(response.text or response.reason or f'HTTP {response.status_code}')
            else:
                for chunk in parse_sse_events(response):
                    try:
                        event = json.loads(chunk)
                    except Exception:
                        continue
                    event_type = (event.get('type') or '').strip()
                    if event_type == 'content' and event.get('text'):
                        result_text += event.get('text') or ''
                    elif event_type == 'test_complete':
                        saw_success = bool(event.get('success'))
                        if not saw_success:
                            error_text = shorten_detail((event.get('error') or '').strip())
                    elif event_type == 'error':
                        error_text = shorten_detail((event.get('error') or '').strip())
                if not saw_success and not error_text:
                    error_text = shorten_detail(result_text) or 'test did not complete successfully'
    except Exception as exc:
        error_text = shorten_detail(str(exc))

    latency_ms = int((time.time() - started) * 1000)
    native_status = classify_api_result(http_status, saw_success)
    return {
        'account_id': account_id,
        'name': name,
        'platform': platform,
        'account_type': account_type,
        'source_status': source_status,
        'credentials': credentials,
        'saw_success': saw_success,
        'latency_ms': latency_ms,
        'native_status': native_status,
        'detail': shorten_detail(result_text if saw_success else error_text),
    }


for batch_start in range(0, len(rows), batch_size):
    batch = rows[batch_start:batch_start + batch_size]
    with ThreadPoolExecutor(max_workers=batch_size) as executor:
        batch_results = list(executor.map(run_account_test, batch))

    for item in batch_results:
        counts['success' if item['saw_success'] else 'failed'] += 1
        status_counts[item['native_status']] += 1
        result = 'success' if item['saw_success'] else 'failed'
        display_name = (item['name'] or '').strip() or f"account-{item['account_id']}"
        summary = summarize_credentials(item['credentials'])
        try:
            print(f"[{result}] account={item['account_id']} name={display_name} platform={item['platform']} type={item['account_type']} source_status={item['source_status']} latency_ms={item['latency_ms']} status={item['native_status']} {summary} detail={item['detail']}")
        except BrokenPipeError:
            pipe_closed = True
            break

    if pipe_closed:
        break

    if batch_start + batch_size < len(rows):
        if sleep_max <= sleep_min:
            sleep_seconds = max(sleep_min, 0)
        else:
            sleep_seconds = random.randint(max(sleep_min, 0), max(sleep_max, sleep_min))
        try:
            print(f"sleep {sleep_seconds}s before next batch")
        except BrokenPipeError:
            pipe_closed = True
            break
        time.sleep(sleep_seconds)

if not pipe_closed:
    try:
        print(f"summary success={counts['success']} failed={counts['failed']}")
        for key in ('success', 'error', 'rate_limited', 'failed'):
            if status_counts[key] > 0:
                print(f'summary status_{key}={status_counts[key]}')
    except BrokenPipeError:
        pass
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
  echo "SUB2TEST_DB_CONTAINER=${SUB2TEST_DB_CONTAINER:-}"
  echo "SUB2TEST_API_BASE_URL=${SUB2TEST_API_BASE_URL:-}"
  echo "SUB2TEST_ADMIN_API_KEY=${SUB2TEST_ADMIN_API_KEY:+***set***}"
  echo "SUB2TEST_ENABLED=${SUB2TEST_ENABLED:-false}"
  echo "SUB2TEST_SCHEDULE=${SUB2TEST_SCHEDULE:-daily}"
  echo "SUB2TEST_CONCURRENCY=${SUB2TEST_CONCURRENCY:-3}"
  echo "SUB2TEST_TIMEOUT_SECONDS=${SUB2TEST_TIMEOUT_SECONDS:-30}"
  echo "SUB2TEST_SLEEP_MIN_SECONDS=${SUB2TEST_SLEEP_MIN_SECONDS:-3}"
  echo "SUB2TEST_SLEEP_MAX_SECONDS=${SUB2TEST_SLEEP_MAX_SECONDS:-10}"
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
  edit_value SUB2TEST_DB_CONTAINER "${SUB2TEST_DB_CONTAINER:-}"
  edit_value SUB2TEST_API_BASE_URL "${SUB2TEST_API_BASE_URL:-http://127.0.0.1:8080/api/v1}"
  edit_value SUB2TEST_ADMIN_API_KEY "${SUB2TEST_ADMIN_API_KEY:-}"
  edit_value SUB2TEST_SCHEDULE "${SUB2TEST_SCHEDULE:-daily}"
  edit_value SUB2TEST_CONCURRENCY "${SUB2TEST_CONCURRENCY:-3}"
  edit_value SUB2TEST_TIMEOUT_SECONDS "${SUB2TEST_TIMEOUT_SECONDS:-30}"
  edit_value SUB2TEST_SLEEP_MIN_SECONDS "${SUB2TEST_SLEEP_MIN_SECONDS:-3}"
  edit_value SUB2TEST_SLEEP_MAX_SECONDS "${SUB2TEST_SLEEP_MAX_SECONDS:-10}"
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
  export SUB2TEST_DB_HOST SUB2TEST_DB_PORT SUB2TEST_DB_USER SUB2TEST_DB_PASSWORD SUB2TEST_DB_NAME SUB2TEST_DB_SSLMODE SUB2TEST_DB_CONTAINER
  export SUB2TEST_API_BASE_URL SUB2TEST_ADMIN_API_KEY
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
