#!/bin/bash
set -euo pipefail

SUB2TEST_VERSION="0.1.6"
SUB2TEST_PROJECT_URL="https://github.com/SYFATP/sub2test-installer"
INSTALL_ROOT="/opt/sub2test"
CONFIG_DIR="/etc/sub2api"
SYSTEMD_SERVICE="/etc/systemd/system/sub2test.service"
SYSTEMD_TIMER="/etc/systemd/system/sub2test.timer"
LINK_FILE="/usr/local/bin/sub2test"
DEFAULT_SUB2API_ROOT="/opt/sub2api-deploy"
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

  python3 - "$CONFIG_FILE" "$DEFAULT_COMPOSE_FILE" "$DEFAULT_APP_CONFIG_FILE" <<'PY_CONFIG'
from pathlib import Path
import sys

config_path = Path(sys.argv[1])
compose_file = sys.argv[2]
app_config_file = sys.argv[3]
existing = {}
if config_path.exists():
    for raw_line in config_path.read_text(encoding='utf-8').splitlines():
        line = raw_line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, value = line.split('=', 1)
        existing[key.strip()] = value

untested_every_minutes_default = '30'
if existing.get('SUB2TEST_UNTESTED_EVERY_MINUTES', '').strip():
    untested_every_minutes_default = existing['SUB2TEST_UNTESTED_EVERY_MINUTES'].strip()
elif existing.get('SUB2TEST_UNTESTED_EVERY_30_MINUTES', 'false') == 'true':
    untested_every_minutes_default = '30'
else:
    legacy_untested_hours = existing.get('SUB2TEST_UNTESTED_EVERY_HOURS', '').strip()
    if legacy_untested_hours.isdigit():
        untested_every_minutes_default = str(int(legacy_untested_hours) * 60)

def keep(key: str, default: str) -> str:
    value = existing.get(key, default)
    return '' if value is None else str(value)

content = f'''# 界面语言：zh / en
SUB2TEST_LANGUAGE={keep("SUB2TEST_LANGUAGE", "zh")}
# sub2test 运行模式：compose=优先从 docker-compose / config.yaml 自动推断数据库信息
SUB2TEST_DEPLOY_MODE={keep("SUB2TEST_DEPLOY_MODE", "compose")}
# Sub2API 的 docker-compose.yml 路径，用于自动识别数据库配置
SUB2TEST_COMPOSE_FILE={keep("SUB2TEST_COMPOSE_FILE", compose_file)}
# Sub2API 的 config.yaml 路径，用于自动识别数据库配置
SUB2API_CONFIG_FILE={keep("SUB2API_CONFIG_FILE", app_config_file)}
# 数据库主机地址；留空时尝试自动识别
SUB2TEST_DB_HOST={keep("SUB2TEST_DB_HOST", "")}
# 数据库端口
SUB2TEST_DB_PORT={keep("SUB2TEST_DB_PORT", "5432")}
# 数据库用户名；留空时尝试自动识别
SUB2TEST_DB_USER={keep("SUB2TEST_DB_USER", "")}
# 数据库密码；留空时尝试自动识别
SUB2TEST_DB_PASSWORD={keep("SUB2TEST_DB_PASSWORD", "")}
# 数据库名；留空时尝试自动识别
SUB2TEST_DB_NAME={keep("SUB2TEST_DB_NAME", "")}
# 数据库 SSL 模式，常见值：disable / require
SUB2TEST_DB_SSLMODE={keep("SUB2TEST_DB_SSLMODE", "disable")}
# 数据库容器名；设置后优先通过 docker exec + psql 查库
SUB2TEST_DB_CONTAINER={keep("SUB2TEST_DB_CONTAINER", "")}
# 管理端 API 基础地址，例如 http://127.0.0.1:38080/api/v1
SUB2TEST_API_BASE_URL={keep("SUB2TEST_API_BASE_URL", "")}
# 管理端 x-api-key，用于调用 /admin/accounts/{{id}}/test
SUB2TEST_ADMIN_API_KEY={keep("SUB2TEST_ADMIN_API_KEY", "")}
# OpenAI 平台 token_expired 后追加的未授权分组 ID；留空表示不追加分组
SUB2TEST_UNAUTHORIZED_GROUP_OPENAI={keep("SUB2TEST_UNAUTHORIZED_GROUP_OPENAI", "")}
# Anthropic 平台 token_expired 后追加的未授权分组 ID；留空表示不追加分组
SUB2TEST_UNAUTHORIZED_GROUP_ANTHROPIC={keep("SUB2TEST_UNAUTHORIZED_GROUP_ANTHROPIC", "")}
# Gemini 平台 token_expired 后追加的未授权分组 ID；留空表示不追加分组
SUB2TEST_UNAUTHORIZED_GROUP_GEMINI={keep("SUB2TEST_UNAUTHORIZED_GROUP_GEMINI", "")}
# Antigravity 平台 token_expired 后追加的未授权分组 ID；留空表示不追加分组
SUB2TEST_UNAUTHORIZED_GROUP_ANTIGRAVITY={keep("SUB2TEST_UNAUTHORIZED_GROUP_ANTIGRAVITY", "")}
# 连续 error 达到该次数后自动停用账号
SUB2TEST_ERROR_STREAK_THRESHOLD={keep("SUB2TEST_ERROR_STREAK_THRESHOLD", "3")}
# sub2test 本地状态文件路径
SUB2TEST_STATE_FILE={keep("SUB2TEST_STATE_FILE", "/opt/sub2test/state.json")}
# 共用运行锁最多等待多少秒；0 表示不等待
SUB2TEST_LOCK_WAIT_SECONDS={keep("SUB2TEST_LOCK_WAIT_SECONDS", "3600")}
# 是否启用未测试 active 账号独立定时任务：true / false
SUB2TEST_UNTESTED_ENABLED={keep("SUB2TEST_UNTESTED_ENABLED", "false")}
# 未测试 active 账号每隔多少分钟执行一次（5-720）
SUB2TEST_UNTESTED_EVERY_MINUTES={keep("SUB2TEST_UNTESTED_EVERY_MINUTES", untested_every_minutes_default)}
# 未测试 active 账号 systemd RandomizedDelaySec
SUB2TEST_UNTESTED_RANDOMIZED_DELAY_SECONDS={keep("SUB2TEST_UNTESTED_RANDOMIZED_DELAY_SECONDS", "120")}
# 是否启用重复账号排查任务：true / false
SUB2TEST_DUPLICATES_ENABLED={keep("SUB2TEST_DUPLICATES_ENABLED", "false")}
# 重复账号排查每隔多少分钟执行一次（5-720）
SUB2TEST_DUPLICATES_EVERY_MINUTES={keep("SUB2TEST_DUPLICATES_EVERY_MINUTES", "60")}
# 重复账号排查 systemd RandomizedDelaySec
SUB2TEST_DUPLICATES_RANDOMIZED_DELAY_SECONDS={keep("SUB2TEST_DUPLICATES_RANDOMIZED_DELAY_SECONDS", "120")}
# 排查重复时是否跳过停用账号：true / false
SUB2TEST_DUPLICATES_SKIP_INACTIVE={keep("SUB2TEST_DUPLICATES_SKIP_INACTIVE", "true")}
# 是否启用代理分配任务：true / false
SUB2TEST_PROXY_ASSIGN_ENABLED={keep("SUB2TEST_PROXY_ASSIGN_ENABLED", "false")}
# 代理分配任务每隔多少分钟执行一次（5-720）
SUB2TEST_PROXY_ASSIGN_EVERY_MINUTES={keep("SUB2TEST_PROXY_ASSIGN_EVERY_MINUTES", "60")}
# 代理分配任务 systemd RandomizedDelaySec
SUB2TEST_PROXY_ASSIGN_RANDOMIZED_DELAY_SECONDS={keep("SUB2TEST_PROXY_ASSIGN_RANDOMIZED_DELAY_SECONDS", "120")}
# 代理分配模式：index / random
SUB2TEST_PROXY_ASSIGN_MODE={keep("SUB2TEST_PROXY_ASSIGN_MODE", "index")}
# 代理分配模式为 index 时，按 id ASC 取第几个 active 代理（从 1 开始）
SUB2TEST_PROXY_ASSIGN_INDEX={keep("SUB2TEST_PROXY_ASSIGN_INDEX", "1")}
# 是否启用 systemd 定时任务：true / false
SUB2TEST_ENABLED={keep("SUB2TEST_ENABLED", "false")}
# 兼容旧配置：hourly / daily / weekly
SUB2TEST_SCHEDULE={keep("SUB2TEST_SCHEDULE", "daily")}
# 每天执行时间，格式 HH:MM；设置后优先于 SUB2TEST_SCHEDULE
SUB2TEST_DAILY_AT={keep("SUB2TEST_DAILY_AT", "")}
# 每隔几小时执行一次（1-23）；设置后优先于 SUB2TEST_SCHEDULE
SUB2TEST_EVERY_HOURS={keep("SUB2TEST_EVERY_HOURS", "")}
# systemd RandomizedDelaySec，默认 120；如需精确时间可设为 0
SUB2TEST_RANDOMIZED_DELAY_SECONDS={keep("SUB2TEST_RANDOMIZED_DELAY_SECONDS", "120")}
# 每批并发测试的账号数
SUB2TEST_CONCURRENCY={keep("SUB2TEST_CONCURRENCY", "3")}
# 单个账号测试接口超时时间（秒）
SUB2TEST_TIMEOUT_SECONDS={keep("SUB2TEST_TIMEOUT_SECONDS", "30")}
# 批次之间最小暂停秒数
SUB2TEST_SLEEP_MIN_SECONDS={keep("SUB2TEST_SLEEP_MIN_SECONDS", "3")}
# 批次之间最大暂停秒数
SUB2TEST_SLEEP_MAX_SECONDS={keep("SUB2TEST_SLEEP_MAX_SECONDS", "10")}
'''
config_path.write_text(content, encoding='utf-8')
PY_CONFIG

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

systemd_non_negative_int_for() {
  local value="$1"
  local label="$2"
  python3 - "$value" "$label" <<'PY_NON_NEGATIVE_INT'
import sys
value = (sys.argv[1] or '').strip()
label = sys.argv[2]
try:
    number = int(value)
except Exception:
    print(f'{label} must be a non-negative integer', file=sys.stderr)
    sys.exit(1)
if number < 0:
    print(f'{label} must be >= 0', file=sys.stderr)
    sys.exit(1)
print(number)
PY_NON_NEGATIVE_INT
}

systemd_positive_int_for() {
  local value="$1"
  local label="$2"
  python3 - "$value" "$label" <<'PY_POSITIVE_INT'
import sys
value = (sys.argv[1] or '').strip()
label = sys.argv[2]
try:
    number = int(value)
except Exception:
    print(f'{label} must be a positive integer', file=sys.stderr)
    sys.exit(1)
if number < 1:
    print(f'{label} must be >= 1', file=sys.stderr)
    sys.exit(1)
print(number)
PY_POSITIVE_INT
}

systemd_calendar_for() {
  local daily_at="$1"
  local every_hours="$2"
  local fallback_schedule="$3"
  local every_30_minutes="${4:-false}"

  if [ "$every_30_minutes" = "true" ]; then
    echo "*:0/30"
    return 0
  fi

  if [ -n "$daily_at" ]; then
    python3 - "$daily_at" <<'PY_DAILY_AT'
import re
import sys
value = (sys.argv[1] or '').strip()
match = re.fullmatch(r'([01]?\d|2[0-3]):([0-5]\d)', value)
if not match:
    print('daily time must use HH:MM (00:00-23:59)', file=sys.stderr)
    sys.exit(1)
hour, minute = match.groups()
print(f"*-*-* {int(hour):02d}:{int(minute):02d}:00")
PY_DAILY_AT
    return 0
  fi

  if [ -n "$every_hours" ]; then
    python3 - "$every_hours" <<'PY_EVERY_HOURS'
import sys
value = (sys.argv[1] or '').strip()
try:
    hours = int(value)
except Exception:
    print('every-hours must be an integer between 1 and 23', file=sys.stderr)
    sys.exit(1)
if hours < 1 or hours > 23:
    print('every-hours must be between 1 and 23', file=sys.stderr)
    sys.exit(1)
print(f"*-*-* 0/{hours}:00:00")
PY_EVERY_HOURS
    return 0
  fi

  case "$fallback_schedule" in
    hourly) echo "hourly" ;;
    daily) echo "daily" ;;
    weekly) echo "weekly" ;;
    *) echo "daily" ;;
  esac
}

systemd_calendar() {
  systemd_calendar_for "${SUB2TEST_DAILY_AT:-}" "${SUB2TEST_EVERY_HOURS:-}" "${SUB2TEST_SCHEDULE:-daily}" "false"
}

systemd_randomized_delay_for() {
  systemd_non_negative_int_for "$1" "randomized delay"
}

systemd_minutes_calendar_for() {
  local value="$1"
  local label="${2:-interval}"
  python3 - "$value" "$label" <<'PY_EVERY_MINUTES'
import sys
value = (sys.argv[1] or '').strip()
label = (sys.argv[2] or 'interval').strip() or 'interval'
try:
    minutes = int(value)
except Exception:
    print(f'{label} must be an integer between 5 and 720', file=sys.stderr)
    sys.exit(1)
if minutes < 5 or minutes > 720:
    print(f'{label} must be between 5 and 720', file=sys.stderr)
    sys.exit(1)
print(minutes)
PY_EVERY_MINUTES
}

systemd_lock_wait_seconds() {
  systemd_non_negative_int_for "$1" "lock wait seconds"
}

validate_runtime_numeric_config() {
  systemd_lock_wait_seconds "${SUB2TEST_LOCK_WAIT_SECONDS:-3600}" >/dev/null
  systemd_randomized_delay_for "${SUB2TEST_RANDOMIZED_DELAY_SECONDS:-120}" >/dev/null
  systemd_randomized_delay_for "${SUB2TEST_UNTESTED_RANDOMIZED_DELAY_SECONDS:-120}" >/dev/null
  systemd_randomized_delay_for "${SUB2TEST_DUPLICATES_RANDOMIZED_DELAY_SECONDS:-120}" >/dev/null
  systemd_minutes_calendar_for "${SUB2TEST_UNTESTED_EVERY_MINUTES:-30}" "untested every-minutes" >/dev/null
  systemd_minutes_calendar_for "${SUB2TEST_DUPLICATES_EVERY_MINUTES:-60}" "duplicates every-minutes" >/dev/null
  systemd_randomized_delay_for "${SUB2TEST_PROXY_ASSIGN_RANDOMIZED_DELAY_SECONDS:-120}" >/dev/null
  systemd_minutes_calendar_for "${SUB2TEST_PROXY_ASSIGN_EVERY_MINUTES:-60}" "proxy-assign every-minutes" >/dev/null
  if [ -n "${SUB2TEST_EVERY_HOURS:-}" ]; then
    systemd_calendar_for "" "${SUB2TEST_EVERY_HOURS:-}" "daily" "false" >/dev/null
  fi
  systemd_positive_int_for "${SUB2TEST_CONCURRENCY:-3}" "concurrency" >/dev/null
  systemd_positive_int_for "${SUB2TEST_TIMEOUT_SECONDS:-30}" "timeout seconds" >/dev/null
  systemd_positive_int_for "${SUB2TEST_ERROR_STREAK_THRESHOLD:-3}" "error streak threshold" >/dev/null
  local sleep_min
  local sleep_max
  sleep_min="$(systemd_non_negative_int_for "${SUB2TEST_SLEEP_MIN_SECONDS:-3}" "sleep min seconds")"
  sleep_max="$(systemd_non_negative_int_for "${SUB2TEST_SLEEP_MAX_SECONDS:-10}" "sleep max seconds")"
  python3 - "$sleep_min" "$sleep_max" <<'PY_SLEEP_RANGE'
import sys
sleep_min = int(sys.argv[1])
sleep_max = int(sys.argv[2])
if sleep_max < sleep_min:
    print('sleep max seconds must be >= sleep min seconds', file=sys.stderr)
    sys.exit(1)
PY_SLEEP_RANGE
}

systemd_randomized_delay() {
  systemd_randomized_delay_for "${SUB2TEST_RANDOMIZED_DELAY_SECONDS:-120}"
}

render_timer() {
  cat > /etc/systemd/system/sub2test.timer <<EOF_TIMER
[Unit]
Description=Run sub2test periodically

[Timer]
OnCalendar=$(systemd_calendar)
Persistent=true
RandomizedDelaySec=$(systemd_randomized_delay)
Unit=sub2test.service

[Install]
WantedBy=timers.target
EOF_TIMER
}

render_untested_timer() {
  cat > /etc/systemd/system/sub2test-untested.timer <<EOF_TIMER
[Unit]
Description=Run sub2test for untested active accounts periodically

[Timer]
OnBootSec=2min
OnUnitActiveSec=$(systemd_minutes_calendar_for "${SUB2TEST_UNTESTED_EVERY_MINUTES:-30}" "untested every-minutes")min
AccuracySec=1s
Persistent=true
RandomizedDelaySec=$(systemd_randomized_delay_for "${SUB2TEST_UNTESTED_RANDOMIZED_DELAY_SECONDS:-120}")
Unit=sub2test-untested.service

[Install]
WantedBy=timers.target
EOF_TIMER
}

render_duplicates_timer() {
  cat > /etc/systemd/system/sub2test-duplicates.timer <<EOF_TIMER
[Unit]
Description=Run sub2test duplicate-account check periodically

[Timer]
OnBootSec=2min
OnUnitActiveSec=$(systemd_minutes_calendar_for "${SUB2TEST_DUPLICATES_EVERY_MINUTES:-60}" "duplicates every-minutes")min
AccuracySec=1s
Persistent=true
RandomizedDelaySec=$(systemd_randomized_delay_for "${SUB2TEST_DUPLICATES_RANDOMIZED_DELAY_SECONDS:-120}")
Unit=sub2test-duplicates.service

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

def shell_quote(value: str) -> str:
    value = '' if value is None else str(value)
    return "'" + value.replace("'", "'\"'\"'") + "'"


def output(host, port, user, password, dbname, sslmode, container=''):
    print(f"SUB2TEST_DB_HOST={shell_quote(host)}")
    print(f"SUB2TEST_DB_PORT={shell_quote(port)}")
    print(f"SUB2TEST_DB_USER={shell_quote(user)}")
    print(f"SUB2TEST_DB_PASSWORD={shell_quote(password)}")
    print(f"SUB2TEST_DB_NAME={shell_quote(dbname)}")
    print(f"SUB2TEST_DB_SSLMODE={shell_quote(sslmode)}")
    print(f"SUB2TEST_DB_CONTAINER={shell_quote(container)}")

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
    env_file_values = {}
    default_env_path = path.parent / '.env'
    if default_env_path.exists():
        env_file_values.update(load_dotenv(default_env_path))

    env_file_match = re.search(r'^\s*env_file:\s*([^\n#]+)$', text, re.MULTILINE)
    if env_file_match:
        env_file_path = env_file_match.group(1).strip().strip('"').strip("'")
        if env_file_path:
            candidate = (path.parent / env_file_path).resolve() if not Path(env_file_path).is_absolute() else Path(env_file_path)
            env_file_values.update(load_dotenv(candidate))

    env_match = re.search(r'\n\s+db:\n([\s\S]*?)(?:\n\S|\Z)', text)
    body = env_match.group(1) if env_match else text

    def resolve_env_reference(value: str) -> str:
        value = value.strip().strip('"').strip("'")
        exact = re.fullmatch(r'\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\}', value)
        if exact:
            var_name = exact.group(1)
            default_value = exact.group(2)
            return env_file_values.get(var_name, os.getenv(var_name, default_value or ''))
        return value

    def env_value(key):
        patterns = [
            rf'^\s+-\s*{key}=(.+)$',
            rf'^\s+{key}:\s*["\']?(.+?)["\']?$',
        ]
        for pattern in patterns:
            match = re.search(pattern, text, re.MULTILINE | re.DOTALL)
            if match:
                return resolve_env_reference(match.group(1))
        inline_match = re.search(rf'^\s+{key}:\s*(.+)$', body, re.MULTILINE)
        if inline_match:
            return resolve_env_reference(inline_match.group(1))
        if key in env_file_values:
            return env_file_values[key]
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

  python3 - <<'PY_PREFLIGHT_API'
import os
import sys

value = os.getenv('SUB2TEST_ADMIN_API_KEY', '')
if not value.isascii():
    print('SUB2TEST_ADMIN_API_KEY must contain ASCII characters only', file=sys.stderr)
    sys.exit(1)
PY_PREFLIGHT_API
}

preflight_runtime() {
  require_python_module yaml python3-yaml
  require_python_module psycopg2 python3-psycopg2
  validate_runtime_numeric_config
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
    printf '%s\n' "$columns" | grep -qx 'rate_limit_reset_at' || { echo "accounts table columns missing: rate_limit_reset_at" >&2; exit 1; }
    printf '%s\n' "$columns" | grep -qx 'temp_unschedulable_until' || { echo "accounts table columns missing: temp_unschedulable_until" >&2; exit 1; }
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
required_columns = {'deleted_at', 'status', 'platform', 'type', 'rate_limit_reset_at', 'temp_unschedulable_until'}
missing_columns = sorted(required_columns - columns)
if missing_columns:
    print('accounts table columns missing: ' + ', '.join(missing_columns), file=sys.stderr)
    sys.exit(1)
cur.close()
conn.close()
print('preflight checks passed')
PY_PREFLIGHT_RUNTIME
}

render_proxy_assign_timer() {
  cat > /etc/systemd/system/sub2test-proxy-assign.timer <<EOF_TIMER
[Unit]
Description=Run sub2test proxy assignment periodically

[Timer]
OnBootSec=2min
OnUnitActiveSec=$(systemd_minutes_calendar_for "${SUB2TEST_PROXY_ASSIGN_EVERY_MINUTES:-60}" "proxy-assign every-minutes")min
AccuracySec=1s
Persistent=true
RandomizedDelaySec=$(systemd_randomized_delay_for "${SUB2TEST_PROXY_ASSIGN_RANDOMIZED_DELAY_SECONDS:-120}")
Unit=sub2test-proxy-assign.service

[Install]
WantedBy=timers.target
EOF_TIMER
}

build_unauthorized_group_exclusion_clause() {
  local configured_ids=()
  local raw value
  for raw in \
    "${SUB2TEST_UNAUTHORIZED_GROUP_OPENAI:-}" \
    "${SUB2TEST_UNAUTHORIZED_GROUP_ANTHROPIC:-}" \
    "${SUB2TEST_UNAUTHORIZED_GROUP_GEMINI:-}" \
    "${SUB2TEST_UNAUTHORIZED_GROUP_ANTIGRAVITY:-}"; do
    value="$(printf '%s' "$raw" | tr -d '[:space:]')"
    case "$value" in
      ''|*[!0-9]*)
        continue
        ;;
    esac
    [ "$value" -gt 0 ] || continue
    case " ${configured_ids[*]} " in
      *" $value "*)
        continue
        ;;
    esac
    configured_ids+=("$value")
  done

  if [ "${#configured_ids[@]}" -eq 0 ]; then
    printf '%s' 'TRUE'
    return 0
  fi

  local joined_ids
  joined_ids="$(IFS=,; printf '%s' "${configured_ids[*]}")"
  printf "%s" "NOT EXISTS (SELECT 1 FROM account_groups ag WHERE ag.account_id = accounts.id AND ag.group_id IN (${joined_ids}))"
}

build_account_where_clause() {
  local unauthorized_exclusion
  unauthorized_exclusion="$(build_unauthorized_group_exclusion_clause)"
  case "${1:-all}" in
    error)
      printf "%s" "(status = 'error' AND ${unauthorized_exclusion})"
      ;;
    disabled)
      printf "%s" "(status = 'inactive' AND ${unauthorized_exclusion})"
      ;;
    temp_unschedulable)
      printf "%s" "(status = 'temp_unschedulable' AND ${unauthorized_exclusion})"
      ;;
    untested)
      printf "%s" "(status = 'active' AND schedulable = TRUE AND (rate_limit_reset_at IS NULL OR rate_limit_reset_at <= NOW()) AND (temp_unschedulable_until IS NULL OR temp_unschedulable_until <= NOW()) AND ${unauthorized_exclusion})"
      ;;
    *)
      printf "%s" "((status = 'error' OR (status = 'active' AND schedulable = TRUE AND (rate_limit_reset_at IS NULL OR rate_limit_reset_at <= NOW()) AND (temp_unschedulable_until IS NULL OR temp_unschedulable_until <= NOW()))) AND ${unauthorized_exclusion})"
      ;;
  esac
}

build_account_order_clause() {
  case "${1:-all}" in
    error|disabled|temp_unschedulable|untested)
      printf "%s" "priority ASC, id ASC"
      ;;
    *)
      printf "%s" "CASE WHEN status = 'error' THEN 0 ELSE 1 END, priority ASC, id ASC"
      ;;
  esac
}

run_proxy_assign() {
  preflight_runtime
  local rows_json=""
  local rows_tsv=""
  rows_json="$(mktemp)"
  cleanup_run_proxy_assign() {
    rm -f -- "${rows_json:-}" "${rows_tsv:-}"
  }
  trap cleanup_run_proxy_assign RETURN

  if [ -n "${SUB2TEST_DB_CONTAINER:-}" ]; then
    rows_tsv="$(mktemp)"
    docker exec \
      -e PGPASSWORD="$SUB2TEST_DB_PASSWORD" \
      "$SUB2TEST_DB_CONTAINER" \
      psql -U "$SUB2TEST_DB_USER" -d "$SUB2TEST_DB_NAME" -F $'\t' -Atqc "SELECT id, proxy_id FROM accounts WHERE deleted_at IS NULL AND proxy_id IS NULL ORDER BY id ASC" > "$rows_tsv"
    python3 - "$rows_tsv" "$rows_json" <<'PY_EXPORT_CONTAINER_PROXY_ASSIGN'
import json
import sys

input_path = sys.argv[1]
output_path = sys.argv[2]
accounts = []

with open(input_path, 'r', encoding='utf-8') as src:
    for raw_line in src:
        line = raw_line.rstrip(chr(10))
        if not line:
            continue
        parts = line.split(chr(9), 1)
        if len(parts) != 2:
            continue
        account_id, proxy_id = parts
        accounts.append({'id': int(account_id), 'proxy_id': None if proxy_id in ('', chr(92) + 'N') else int(proxy_id)})

with open(output_path, 'w', encoding='utf-8') as out:
    out.write(json.dumps({'accounts': accounts}, ensure_ascii=False))
PY_EXPORT_CONTAINER_PROXY_ASSIGN
  else
    python3 - "$rows_json" <<'PY_EXPORT_PROXY_ASSIGN'
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
    SELECT id, proxy_id
    FROM accounts
    WHERE deleted_at IS NULL
      AND proxy_id IS NULL
    ORDER BY id ASC
    """
)
accounts = [{'id': account_id, 'proxy_id': proxy_id} for account_id, proxy_id in cur.fetchall()]
cur.close()
conn.close()

with open(output_path, 'w', encoding='utf-8') as fh:
    fh.write(json.dumps({'accounts': accounts}, ensure_ascii=False))
PY_EXPORT_PROXY_ASSIGN
  fi

  python3 - "$rows_json" <<'PY_RUN_PROXY_ASSIGN'
import json
import os
import random
import sys
import urllib.error
import urllib.request

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass

rows_path = sys.argv[1]
api_base_url = (os.getenv('SUB2TEST_API_BASE_URL', '') or '').strip().rstrip('/')
admin_api_key = (os.getenv('SUB2TEST_ADMIN_API_KEY', '') or '').strip()
timeout_seconds = int((os.getenv('SUB2TEST_TIMEOUT_SECONDS', '30') or '30').strip())
mode = (os.getenv('SUB2TEST_PROXY_ASSIGN_MODE', 'index') or 'index').strip().lower()
index_raw = (os.getenv('SUB2TEST_PROXY_ASSIGN_INDEX', '1') or '1').strip()
db_container = (os.getenv('SUB2TEST_DB_CONTAINER', '') or '').strip()

with open(rows_path, 'r', encoding='utf-8') as fh:
    payload = json.load(fh)

accounts = payload.get('accounts') or []
headers = {
    'x-api-key': admin_api_key,
    'Content-Type': 'application/json',
    'Accept': 'application/json',
}

if mode not in ('index', 'random'):
    print(f'proxy_assign_summary candidates={len(accounts)} assigned=0 skipped_existing=0 failed=0 reason=invalid_mode mode={mode}')
    sys.exit(1)

try:
    proxy_index = int(index_raw)
except Exception:
    print(f'proxy_assign_summary candidates={len(accounts)} assigned=0 skipped_existing=0 failed=0 reason=invalid_index index={index_raw}')
    sys.exit(1)
if proxy_index < 1:
    print(f'proxy_assign_summary candidates={len(accounts)} assigned=0 skipped_existing=0 failed=0 reason=invalid_index index={proxy_index}')
    sys.exit(1)


def shorten_detail(detail: str) -> str:
    detail = '' if detail is None else str(detail)
    detail = detail.encode('utf-8', errors='replace').decode('utf-8', errors='replace')
    detail = detail.replace(chr(10), ' ')
    detail = ' '.join(detail.split())
    return detail[:180]


def response_error_detail(status_code, body_bytes):
    try:
        body = body_bytes.decode('utf-8', errors='replace').strip() if body_bytes else ''
    except Exception:
        body = ''
    if body:
        return shorten_detail(body)
    return shorten_detail(f'HTTP {status_code}')


def safe_exception_text(exc: Exception) -> str:
    try:
        text = str(exc)
    except Exception:
        text = repr(exc)
    if not text:
        text = exc.__class__.__name__
    return shorten_detail(text)


def update_account_fields(account_id: int, update_payload: dict):
    body = json.dumps(update_payload, ensure_ascii=False).encode('utf-8')
    for method in ('PATCH', 'PUT'):
        req = urllib.request.Request(
            f'{api_base_url}/admin/accounts/{account_id}',
            data=body,
            headers=headers,
            method=method,
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout_seconds) as response:
                return True, getattr(response, 'status', None) or response.getcode(), ''
        except urllib.error.HTTPError as err:
            if method == 'PATCH' and err.code in (404, 405):
                continue
            return False, err.code, response_error_detail(err.code, err.read())
        except Exception as exc:
            return False, None, safe_exception_text(exc)
    return False, None, 'update request failed'


def load_active_proxy_ids() -> list[int]:
    if db_container:
        import subprocess
        command = [
            'docker', 'exec', '-e', f'PGPASSWORD={os.getenv("SUB2TEST_DB_PASSWORD", "")}', db_container,
            'psql', '-U', os.environ['SUB2TEST_DB_USER'], '-d', os.environ['SUB2TEST_DB_NAME'], '-F', '\t', '-Atqc',
            "SELECT id FROM proxies WHERE deleted_at IS NULL AND status = 'active' ORDER BY id ASC",
        ]
        result = subprocess.run(command, capture_output=True, text=True, encoding='utf-8')
        if result.returncode != 0:
            print(f'proxy_assign_summary candidates={len(accounts)} assigned=0 skipped_existing=0 failed=0 reason=load_proxy_failed detail={shorten_detail(result.stderr)}')
            sys.exit(1)
        return [int(line.strip()) for line in result.stdout.splitlines() if line.strip()]

    import psycopg2
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
        SELECT id
        FROM proxies
        WHERE deleted_at IS NULL
          AND status = 'active'
        ORDER BY id ASC
        """
    )
    proxy_ids = [proxy_id for (proxy_id,) in cur.fetchall()]
    cur.close()
    conn.close()
    return proxy_ids


def select_proxy_id(active_proxy_ids: list[int]) -> int | None:
    if not active_proxy_ids:
        return None
    if mode == 'random':
        return random.choice(active_proxy_ids)
    if proxy_index > len(active_proxy_ids):
        return None
    return active_proxy_ids[proxy_index - 1]

proxy_ids = load_active_proxy_ids()
selected_proxy_id = select_proxy_id(proxy_ids)
candidate_count = len(accounts)
skipped_existing = 0
assigned_count = 0
failed_count = 0

if not proxy_ids:
    print(f'proxy_assign_summary candidates={candidate_count} assigned=0 skipped_existing=0 failed=0 reason=no_available_proxy mode={mode}')
    sys.exit(0)

if selected_proxy_id is None:
    print(f'proxy_assign_summary candidates={candidate_count} assigned=0 skipped_existing=0 failed=0 reason=proxy_index_out_of_range mode={mode} index={proxy_index} active_proxy_count={len(proxy_ids)}')
    sys.exit(0)

for row in accounts:
    account_id = int(row.get('id'))
    current_proxy_id = row.get('proxy_id')
    if current_proxy_id not in (None, ''):
        skipped_existing += 1
        print(f'proxy_assign_skip account={account_id} reason=existing_proxy proxy_id={current_proxy_id}')
        continue
    success, status_code, detail = update_account_fields(account_id, {'proxy_id': selected_proxy_id})
    if success:
        assigned_count += 1
        print(f'proxy_assign account={account_id} proxy={selected_proxy_id} mode={mode}')
    else:
        failed_count += 1
        print(f'proxy_assign account={account_id} proxy={selected_proxy_id} mode={mode} status=failed http_status={status_code or "unknown"} detail={shorten_detail(detail)}')

print(f'proxy_assign_summary candidates={candidate_count} assigned={assigned_count} skipped_existing={skipped_existing} failed={failed_count} mode={mode} selected_proxy={selected_proxy_id}')
PY_RUN_PROXY_ASSIGN
}

run_duplicate_check() {
  preflight_runtime
  local rows_json=""
  local rows_tsv=""
  rows_json="$(mktemp)"
  cleanup_run_duplicate_check() {
    rm -f -- "${rows_json:-}" "${rows_tsv:-}"
  }
  trap cleanup_run_duplicate_check RETURN

  if [ -n "${SUB2TEST_DB_CONTAINER:-}" ]; then
    rows_tsv="$(mktemp)"
    docker exec \
      -e PGPASSWORD="$SUB2TEST_DB_PASSWORD" \
      "$SUB2TEST_DB_CONTAINER" \
      psql -U "$SUB2TEST_DB_USER" -d "$SUB2TEST_DB_NAME" -F $'\t' -Atqc "SELECT id, COALESCE(name, ''), status FROM accounts WHERE deleted_at IS NULL ORDER BY name ASC, id ASC" > "$rows_tsv"
    python3 - "$rows_tsv" "$rows_json" <<'PY_EXPORT_CONTAINER_DUPLICATES'
import json
import sys

input_path = sys.argv[1]
output_path = sys.argv[2]

with open(input_path, 'r', encoding='utf-8') as src, open(output_path, 'w', encoding='utf-8') as out:
    for raw_line in src:
        line = raw_line.rstrip('\\n')
        if not line:
            continue
        parts = line.split('\t', 2)
        if len(parts) != 3:
            continue
        account_id, name, status = parts
        out.write(json.dumps({
            'id': int(account_id),
            'name': name,
            'status': status,
        }, ensure_ascii=False) + '\n')
PY_EXPORT_CONTAINER_DUPLICATES
  else
    python3 - "$rows_json" <<'PY_EXPORT_DUPLICATES'
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
    SELECT id, COALESCE(name, ''), status
    FROM accounts
    WHERE deleted_at IS NULL
    ORDER BY name ASC, id ASC
    """
)
rows = cur.fetchall()
cur.close()
conn.close()

with open(output_path, 'w', encoding='utf-8') as fh:
    for account_id, name, status in rows:
        fh.write(json.dumps({
            'id': account_id,
            'name': name or '',
            'status': status,
        }, ensure_ascii=False) + '\n')
PY_EXPORT_DUPLICATES
  fi

  python3 - "$rows_json" <<'PY_RUN_DUPLICATE_CHECK'
import json
import os
import sys
import urllib.error
import urllib.request
from collections import defaultdict

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass

rows_path = sys.argv[1]
skip_inactive = (os.getenv('SUB2TEST_DUPLICATES_SKIP_INACTIVE', 'true') or 'true').strip().lower() == 'true'
api_base_url = (os.getenv('SUB2TEST_API_BASE_URL', '') or '').strip().rstrip('/')
admin_api_key = (os.getenv('SUB2TEST_ADMIN_API_KEY', '') or '').strip()
timeout_seconds = int((os.getenv('SUB2TEST_TIMEOUT_SECONDS', '30') or '30').strip())

with open(rows_path, 'r', encoding='utf-8') as fh:
    rows = [json.loads(line) for line in fh if line.strip()]

headers = {
    'x-api-key': admin_api_key,
    'Content-Type': 'application/json',
    'Accept': 'application/json',
}

def shorten_detail(detail: str) -> str:
    detail = '' if detail is None else str(detail)
    detail = detail.encode('utf-8', errors='replace').decode('utf-8', errors='replace')
    detail = detail.replace(chr(10), ' ')
    detail = ' '.join(detail.split())
    return detail[:180]


def response_error_detail(status_code, body_bytes):
    try:
        body = body_bytes.decode('utf-8', errors='replace').strip() if body_bytes else ''
    except Exception:
        body = ''
    if body:
        return shorten_detail(body)
    return shorten_detail(f'HTTP {status_code}')


def safe_exception_text(exc: Exception) -> str:
    try:
        text = str(exc)
    except Exception:
        text = repr(exc)
    if not text:
        text = exc.__class__.__name__
    return shorten_detail(text)


def update_account_fields(account_id: int, payload: dict):
    body = json.dumps(payload, ensure_ascii=False).encode('utf-8')
    for method in ('PATCH', 'PUT'):
        req = urllib.request.Request(
            f'{api_base_url}/admin/accounts/{account_id}',
            data=body,
            headers=headers,
            method=method,
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout_seconds) as response:
                return True, getattr(response, 'status', None) or response.getcode(), ''
        except urllib.error.HTTPError as err:
            if method == 'PATCH' and err.code in (404, 405):
                continue
            return False, err.code, response_error_detail(err.code, err.read())
        except Exception as exc:
            return False, None, safe_exception_text(exc)
    return False, None, 'update request failed'


def detect_note_field() -> str | None:
    if not rows:
        return None
    sample_id = int(rows[0]['id'])
    unknown_markers = ('unknown field', 'unknown_fields', 'extra fields', 'not allowed', 'unrecognized')
    for field_name in ('note', 'remarks', 'remark', 'comment', 'description'):
        success, status_code, detail = update_account_fields(sample_id, {field_name: '账号重复'})
        detail_lower = (detail or '').lower()
        if success:
            rollback_success, rollback_status, rollback_detail = update_account_fields(sample_id, {field_name: ''})
            if rollback_success:
                print(f'duplicate_note_field field={field_name}')
                return field_name
            print(f'duplicate_note_field field={field_name} rollback_failed status={rollback_status or "unknown"} detail={shorten_detail(rollback_detail)}')
            return field_name
        if status_code in (400, 422) and any(marker in detail_lower for marker in unknown_markers):
            continue
    print('duplicate_note_field field=none')
    return None


groups = defaultdict(list)
for row in rows:
    name = (row.get('name') or '').strip()
    if not name:
        continue
    if skip_inactive and (row.get('status') or '').strip() == 'inactive':
        continue
    groups[name].append(row)

duplicate_groups = []
for name in sorted(groups):
    members = sorted(groups[name], key=lambda item: int(item.get('id', 0)))
    if len(members) > 1:
        duplicate_groups.append((name, members))

note_field = detect_note_field() if duplicate_groups else None
note_value = '账号重复'
disabled_count = 0
failed_count = 0

for name, members in duplicate_groups:
    keep = members[0]
    disable_members = members[1:]
    disable_ids = ','.join(str(int(item['id'])) for item in disable_members)
    print(f'duplicate name={name} keep_id={int(keep["id"])} disable_ids={disable_ids}')
    for item in disable_members:
        payload = {'status': 'inactive'}
        if note_field:
            payload[note_field] = note_value
        success, status_code, detail = update_account_fields(int(item['id']), payload)
        if success:
            disabled_count += 1
            print(f'duplicate_disable id={int(item["id"])} status=success note={(note_value if note_field else "none")}')
        else:
            failed_count += 1
            print(f'duplicate_disable id={int(item["id"])} status=failed http_status={status_code or "unknown"} detail={shorten_detail(detail)}')

print(f'duplicate_summary groups={len(duplicate_groups)} disabled={disabled_count} failed={failed_count} skip_inactive={str(skip_inactive).lower()} note_field={note_field or "none"}')
PY_RUN_DUPLICATE_CHECK
}

run_health_check() {
  preflight_runtime
  local mode="${1:-all}"
  local where_clause=""
  local order_clause=""
  local query_sql=""
  local accounts_json=""
  local accounts_tsv=""
  where_clause="$(build_account_where_clause "$mode")"
  order_clause="$(build_account_order_clause "$mode")"
  query_sql="SELECT id, COALESCE(name, ''), platform, type, status FROM accounts WHERE deleted_at IS NULL AND ${where_clause} ORDER BY ${order_clause}"
  cleanup_run_health_check() {
    rm -f -- "${accounts_json:-}" "${accounts_tsv:-}"
  }
  trap cleanup_run_health_check RETURN
  accounts_json="$(mktemp)"

  if [ -n "${SUB2TEST_DB_CONTAINER:-}" ]; then
    accounts_tsv="$(mktemp)"
    docker exec \
      -e PGPASSWORD="$SUB2TEST_DB_PASSWORD" \
      "$SUB2TEST_DB_CONTAINER" \
      psql -U "$SUB2TEST_DB_USER" -d "$SUB2TEST_DB_NAME" -F $'\t' -Atqc "$query_sql" > "$accounts_tsv"
    python3 - "$accounts_tsv" "$accounts_json" <<'PY_EXPORT_CONTAINER_ACCOUNTS'
import json
import sys

input_path = sys.argv[1]
output_path = sys.argv[2]

with open(input_path, 'r', encoding='utf-8') as src, open(output_path, 'w', encoding='utf-8') as out:
    for raw_line in src:
        line = raw_line.rstrip('\\n')
        if not line:
            continue
        parts = line.split('\t', 4)
        if len(parts) != 5:
            continue
        account_id, name, platform, account_type, status = parts
        out.write(json.dumps({
            'id': int(account_id),
            'name': name,
            'platform': platform,
            'type': account_type,
            'status': status,
        }, ensure_ascii=False) + '\n')
PY_EXPORT_CONTAINER_ACCOUNTS
  else
    python3 - "$accounts_json" "$mode" <<'PY_EXPORT_ACCOUNTS'
import json
import os
import sys

import psycopg2

output_path = sys.argv[1]
mode = sys.argv[2]

configured_group_ids = []
for env_name in (
    'SUB2TEST_UNAUTHORIZED_GROUP_OPENAI',
    'SUB2TEST_UNAUTHORIZED_GROUP_ANTHROPIC',
    'SUB2TEST_UNAUTHORIZED_GROUP_GEMINI',
    'SUB2TEST_UNAUTHORIZED_GROUP_ANTIGRAVITY',
):
    raw_value = (os.getenv(env_name, '') or '').strip()
    if not raw_value:
        continue
    try:
        group_id = int(raw_value)
    except Exception:
        continue
    if group_id <= 0 or group_id in configured_group_ids:
        continue
    configured_group_ids.append(group_id)

exclusion_clause = 'TRUE'
if configured_group_ids:
    exclusion_clause = f"NOT EXISTS (SELECT 1 FROM account_groups ag WHERE ag.account_id = accounts.id AND ag.group_id IN ({','.join(str(group_id) for group_id in configured_group_ids)}))"

if mode == 'error':
    where_clause = f"(status = 'error' AND {exclusion_clause})"
    order_clause = "priority ASC, id ASC"
elif mode == 'disabled':
    where_clause = f"(status = 'inactive' AND {exclusion_clause})"
    order_clause = "priority ASC, id ASC"
elif mode == 'temp_unschedulable':
    where_clause = f"(status = 'temp_unschedulable' AND {exclusion_clause})"
    order_clause = "priority ASC, id ASC"
elif mode == 'untested':
    where_clause = f"(status = 'active' AND schedulable = TRUE AND (rate_limit_reset_at IS NULL OR rate_limit_reset_at <= NOW()) AND (temp_unschedulable_until IS NULL OR temp_unschedulable_until <= NOW()) AND {exclusion_clause})"
    order_clause = "priority ASC, id ASC"
else:
    where_clause = f"""
    (
      (
        status = 'error'
        OR (
          status = 'active'
          AND schedulable = TRUE
          AND (rate_limit_reset_at IS NULL OR rate_limit_reset_at <= NOW())
          AND (temp_unschedulable_until IS NULL OR temp_unschedulable_until <= NOW())
        )
      )
      AND {exclusion_clause}
    )
    """
    order_clause = "CASE WHEN status = 'error' THEN 0 ELSE 1 END, priority ASC, id ASC"

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
    f"""
    SELECT id, name, platform, type, status
    FROM accounts
    WHERE deleted_at IS NULL
      AND {where_clause}
    ORDER BY {order_clause}
    """
)
rows = cur.fetchall()
cur.close()
conn.close()

with open(output_path, 'w', encoding='utf-8') as fh:
    for account_id, name, platform, account_type, status in rows:
        fh.write(json.dumps({
            'id': account_id,
            'name': name or '',
            'platform': platform,
            'type': account_type,
            'status': status,
        }, ensure_ascii=False) + '\n')
PY_EXPORT_ACCOUNTS
  fi

  python3 - "$accounts_json" "$mode" <<'PY_RUN_HEALTH_CHECK'
import json
import os
import random
import signal
import sys
import time
import urllib.error
import urllib.request
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass

def get_env(name: str, default: str = '') -> str:
    return (os.getenv(name, default) or '').strip()

def shorten_detail(detail: str) -> str:
    detail = '' if detail is None else str(detail)
    detail = detail.encode('utf-8', errors='replace').decode('utf-8', errors='replace')
    detail = detail.strip().replace('\\\\n', ' ')
    detail = ' '.join(detail.split())
    return detail[:180]


def safe_exception_text(exc: Exception) -> str:
    parts = [exc.__class__.__name__]
    for attr in ('reason', 'object', 'encoding', 'start', 'end'):
        if not hasattr(exc, attr):
            continue
        try:
            value = getattr(exc, attr)
        except Exception:
            continue
        if value in (None, ''):
            continue
        if attr == 'object':
            value = type(value).__name__
        parts.append(f"{attr}={value!r}")
    try:
        text = str(exc)
    except Exception:
        text = repr(exc)
    if text:
        parts.append(text)
    return shorten_detail(' | '.join(str(part) for part in parts if part))


def response_error_detail(status_code, body_bytes):
    try:
        body = body_bytes.decode('utf-8', errors='replace').strip() if body_bytes else ''
    except Exception:
        body = ''
    if body:
        return shorten_detail(body)
    return shorten_detail(f'HTTP {status_code}')

def parse_int_env(name: str, default: int, minimum: int | None = None) -> int:
    raw = get_env(name, str(default)) or str(default)
    try:
        value = int(raw)
    except Exception:
        print(f'{name} must be an integer, got: {raw}', file=sys.stderr)
        sys.exit(1)
    if minimum is not None and value < minimum:
        print(f'{name} must be >= {minimum}, got: {value}', file=sys.stderr)
        sys.exit(1)
    return value

sleep_min = parse_int_env('SUB2TEST_SLEEP_MIN_SECONDS', 3, 0)
sleep_max = parse_int_env('SUB2TEST_SLEEP_MAX_SECONDS', 10, 0)
if sleep_max < sleep_min:
    print(f'SUB2TEST_SLEEP_MAX_SECONDS must be >= SUB2TEST_SLEEP_MIN_SECONDS, got: {sleep_max} < {sleep_min}', file=sys.stderr)
    sys.exit(1)
timeout_seconds = parse_int_env('SUB2TEST_TIMEOUT_SECONDS', 30, 1)
batch_size = parse_int_env('SUB2TEST_CONCURRENCY', 3, 1)
error_streak_threshold = parse_int_env('SUB2TEST_ERROR_STREAK_THRESHOLD', 3, 1)
state_file = Path(get_env('SUB2TEST_STATE_FILE', '/opt/sub2test/state.json') or '/opt/sub2test/state.json')
rows_file = sys.argv[1]
mode = sys.argv[2]
with open(rows_file, 'r', encoding='utf-8') as fh:
    rows = [json.loads(line) for line in fh if line.strip()]
print(f'loaded {len(rows)} accounts (batch_size={batch_size})')
if not rows:
    sys.exit(0)

counts = Counter()
status_counts = Counter()
pipe_closed = False
state_warning = ''


def load_state(path: Path):
    global state_warning
    try:
        if not path.exists():
            return {'accounts': {}}
        data = json.loads(path.read_text(encoding='utf-8'))
    except Exception as exc:
        state_warning = f'state_load_warning={safe_exception_text(exc)}'
        return {'accounts': {}}
    if not isinstance(data, dict):
        state_warning = 'state_load_warning=invalid state file root; resetting state'
        return {'accounts': {}}
    accounts = data.get('accounts')
    if not isinstance(accounts, dict):
        state_warning = 'state_load_warning=invalid accounts section; resetting state'
        accounts = {}
    return {'accounts': accounts}


def save_state(path: Path, state: dict):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = path.with_name(path.name + '.tmp')
    tmp_path.write_text(json.dumps(state, ensure_ascii=False, indent=2, sort_keys=True) + '\n', encoding='utf-8')
    tmp_path.replace(path)


def get_account_state(state: dict, account_id) -> dict:
    key = str(account_id)
    accounts = state.setdefault('accounts', {})
    current = accounts.get(key)
    if not isinstance(current, dict):
        current = {}
        accounts[key] = current
    return current


def normalize_int(value, default=0):
    try:
        return int(value)
    except Exception:
        return default


def should_disable_account(account_state: dict, source_status: str, native_status: str, threshold: int):
    prior_streak = max(normalize_int(account_state.get('consecutive_error_count'), 0), 0)
    streak_count = prior_streak
    already_disabled = bool(account_state.get('disabled_by_sub2test_at'))

    if source_status == 'inactive':
        streak_count = 0
    elif native_status == 'success':
        streak_count = 0
    elif native_status == 'error':
        streak_count = prior_streak + 1

    disable_needed = source_status != 'inactive' and native_status == 'error' and streak_count >= threshold and not already_disabled
    return prior_streak, streak_count, disable_needed


def apply_account_state(account_state: dict, native_status: str, streak_count: int, disable_success: bool, enable_success: bool):
    account_state['consecutive_error_count'] = max(streak_count, 0)
    account_state['last_native_status'] = native_status
    if disable_success:
        account_state['consecutive_error_count'] = 0
        account_state['disabled_by_sub2test_at'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    if enable_success:
        account_state.pop('disabled_by_sub2test_at', None)


def update_account_fields(account_id: int, payload: dict):
    body = json.dumps(payload, ensure_ascii=False).encode('utf-8')
    headers = {
        'x-api-key': get_env('SUB2TEST_ADMIN_API_KEY'),
        'Content-Type': 'application/json',
        'Accept': 'application/json',
    }
    for method in ('PATCH', 'PUT'):
        req = urllib.request.Request(
            f"{get_env('SUB2TEST_API_BASE_URL').rstrip('/')}/admin/accounts/{account_id}",
            data=body,
            headers=headers,
            method=method,
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout_seconds) as response:
                return True, getattr(response, 'status', None) or response.getcode(), ''
        except urllib.error.HTTPError as err:
            if method == 'PATCH' and err.code in (404, 405):
                continue
            return False, err.code, response_error_detail(err.code, err.read())
        except Exception as exc:
            return False, None, safe_exception_text(exc)
    return False, None, 'update request failed'


def update_account_status(account_id: int, status: str):
    return update_account_fields(account_id, {'status': status})


def mark_account_error(account_id: int):
    return update_account_status(account_id, 'error')


def get_platform_unauthorized_group_id(platform: str) -> int | None:
    platform_key = (platform or '').strip().lower()
    if not platform_key:
        return None
    env_name = f"SUB2TEST_UNAUTHORIZED_GROUP_{platform_key.upper()}"
    raw = get_env(env_name)
    if not raw:
        return None
    try:
        value = int(raw)
    except Exception:
        print(f'{env_name} must be an integer, got: {raw}', file=sys.stderr)
        return None
    return value if value > 0 else None


def fetch_account_group_ids(account_id: int):
    headers = {
        'x-api-key': get_env('SUB2TEST_ADMIN_API_KEY'),
        'Accept': 'application/json',
    }
    req = urllib.request.Request(
        f"{get_env('SUB2TEST_API_BASE_URL').rstrip('/')}/admin/accounts/{account_id}",
        headers=headers,
        method='GET',
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout_seconds) as response:
            body = response.read().decode('utf-8', errors='replace')
            payload = json.loads(body) if body else {}
    except urllib.error.HTTPError as err:
        return None, False, err.code, response_error_detail(err.code, err.read())
    except Exception as exc:
        return None, False, None, safe_exception_text(exc)

    account_payload = payload.get('data') if isinstance(payload, dict) else None
    if not isinstance(account_payload, dict):
        account_payload = payload if isinstance(payload, dict) else {}

    group_ids_raw = account_payload.get('group_ids')
    if not isinstance(group_ids_raw, list):
        group_ids_raw = []

    normalized_group_ids = []
    seen = set()
    for item in group_ids_raw:
        try:
            group_id = int(item)
        except Exception:
            continue
        if group_id <= 0 or group_id in seen:
            continue
        seen.add(group_id)
        normalized_group_ids.append(group_id)

    return normalized_group_ids, True, None, ''


def merge_group_ids(existing_group_ids, extra_group_id: int | None):
    merged = []
    seen = set()
    for item in existing_group_ids or []:
        try:
            group_id = int(item)
        except Exception:
            continue
        if group_id <= 0 or group_id in seen:
            continue
        seen.add(group_id)
        merged.append(group_id)
    if extra_group_id is not None and extra_group_id > 0 and extra_group_id not in seen:
        merged.append(extra_group_id)
    return merged


def mark_account_token_expired(account_id: int, platform: str):
    existing_group_ids, fetch_success, fetch_status, fetch_detail = fetch_account_group_ids(account_id)
    if not fetch_success:
        return False, fetch_status, fetch_detail
    merged_group_ids = merge_group_ids(existing_group_ids, get_platform_unauthorized_group_id(platform))
    return update_account_fields(account_id, {
        'status': 'inactive',
        'schedulable': False,
        'group_ids': merged_group_ids,
    })


def disable_account(account_id: int):
    return update_account_fields(account_id, {
        'status': 'inactive',
        'schedulable': False,
    })


def enable_account(account_id: int):
    return update_account_fields(account_id, {
        'status': 'active',
        'schedulable': True,
    })


state = load_state(state_file)
processed_account_ids = set()

if mode == 'untested':
    initial_count = len(rows)
    known_accounts = state.get('accounts', {}) if isinstance(state.get('accounts'), dict) else {}
    rows = [row for row in rows if str(row.get('id', '')) not in known_accounts]
    print(f'mode=untested candidates={initial_count} pending={len(rows)}')


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


def parse_sse_events(lines):
    event_buffer = []
    for raw_line in lines:
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


def classify_error_text(http_status: int | None, text: str) -> str:
    raw = shorten_detail(text).lower()
    if http_status == 429 or any(keyword in raw for keyword in ('429', 'rate_limit', 'rate limit', 'too many request')):
        return 'rate_limited'
    if 'token_expired' in raw or 'token expired' in raw:
        return 'token_expired'
    if 'token_invalidated' in raw:
        return 'error'
    if http_status in (401, 403) or any(keyword in raw for keyword in ('401', '403', 'unauthorized', 'forbidden', 'invalid token', 'token invalid', 'login again', 'sign in again', 'authentication token', 'no access token available')):
        return 'error'
    if raw:
        return 'unknown'
    return 'unknown'


def has_success_text(text: str) -> bool:
    raw = shorten_detail(text).lower()
    return any(keyword in raw for keyword in (
        'hi — what can i help',
        'hi - what can i help',
        'what can i help with',
        'what can i help you with',
        'hello',
        'success',
        'passed',
    ))


def extract_plain_response_text(payload, raw_body: str) -> str:
    if isinstance(payload, dict):
        error_value = payload.get('error')
        if isinstance(error_value, dict):
            return str(error_value.get('message') or error_value.get('type') or error_value.get('code') or raw_body)
        return str(payload.get('message') or payload.get('detail') or payload.get('text') or error_value or raw_body)
    return raw_body


def classify_api_result(http_status: int | None, saw_success: bool, error_text: str) -> str:
    if saw_success:
        return 'success'
    return classify_error_text(http_status, error_text)


def run_account_test(row):
    account_id = row.get('id', '')
    name = row.get('name', '')
    platform = row.get('platform', '')
    account_type = row.get('type', '')
    source_status = row.get('status', '')
    started = time.time()
    result_text = ''
    saw_success = False
    http_status = None
    error_text = ''

    try:
        body = json.dumps({}).encode('utf-8')
        req = urllib.request.Request(
            f"{get_env('SUB2TEST_API_BASE_URL').rstrip('/')}/admin/accounts/{account_id}/test",
            data=body,
            headers={
                'x-api-key': get_env('SUB2TEST_ADMIN_API_KEY'),
                'Content-Type': 'application/json',
                'Accept': 'text/event-stream',
            },
            method='POST',
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout_seconds) as response:
                http_status = getattr(response, 'status', None) or response.getcode()
                content_type = str(response.headers.get('Content-Type', '')).lower()
                raw_body = response.read().decode('utf-8', errors='replace')
                if http_status != 200:
                    error_text = response_error_detail(http_status, raw_body.encode('utf-8'))
                elif 'text/event-stream' in content_type:
                    line_stream = raw_body.splitlines()
                    for chunk in parse_sse_events(line_stream):
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
                else:
                    payload = None
                    try:
                        payload = json.loads(raw_body)
                    except Exception:
                        payload = None
                    text = extract_plain_response_text(payload, raw_body)
                    result_text = result_text or shorten_detail(text)
                    if has_success_text(text):
                        saw_success = True
                    else:
                        error_text = error_text or shorten_detail(text)
        except urllib.error.HTTPError as err:
            http_status = err.code
            error_text = response_error_detail(err.code, err.read())
    except Exception as exc:
        error_text = safe_exception_text(exc)

    latency_ms = int((time.time() - started) * 1000)
    native_status = classify_api_result(http_status, saw_success, error_text)
    account_state = get_account_state(state, account_id)
    _, streak_count, disable_needed = should_disable_account(account_state, source_status, native_status, error_streak_threshold)
    disable_attempted = False
    disable_success = False
    disable_detail = ''
    disable_status = None
    mark_error_attempted = False
    mark_error_success = False
    mark_error_detail = ''
    mark_error_status = None
    mark_token_expired_attempted = False
    mark_token_expired_success = False
    mark_token_expired_detail = ''
    mark_token_expired_status = None
    enable_attempted = False
    enable_success = False
    enable_detail = ''
    enable_status = None
    keep_inactive_attempted = False
    keep_inactive_success = False
    keep_inactive_detail = ''
    keep_inactive_status = None

    if source_status == 'inactive' and native_status == 'success':
        enable_attempted = True
        enable_success, enable_status, enable_detail = enable_account(int(account_id))
        if not enable_success:
            enable_detail = shorten_detail(enable_detail or (f'HTTP {enable_status}' if enable_status else 'enable request failed'))
    elif source_status == 'inactive' and native_status != 'success':
        if native_status == 'token_expired':
            mark_token_expired_attempted = True
            mark_token_expired_success, mark_token_expired_status, mark_token_expired_detail = mark_account_token_expired(int(account_id), platform)
            if not mark_token_expired_success:
                mark_token_expired_detail = shorten_detail(mark_token_expired_detail or (f'HTTP {mark_token_expired_status}' if mark_token_expired_status else 'mark token_expired request failed'))
        else:
            keep_inactive_attempted = True
            keep_inactive_success, keep_inactive_status, keep_inactive_detail = disable_account(int(account_id))
            if not keep_inactive_success:
                keep_inactive_detail = shorten_detail(keep_inactive_detail or (f'HTTP {keep_inactive_status}' if keep_inactive_status else 'keep inactive request failed'))
    elif native_status == 'token_expired':
        mark_token_expired_attempted = True
        mark_token_expired_success, mark_token_expired_status, mark_token_expired_detail = mark_account_token_expired(int(account_id), platform)
        if not mark_token_expired_success:
            mark_token_expired_detail = shorten_detail(mark_token_expired_detail or (f'HTTP {mark_token_expired_status}' if mark_token_expired_status else 'mark token_expired request failed'))
    elif source_status != 'inactive' and native_status == 'error':
        mark_error_attempted = True
        mark_error_success, mark_error_status, mark_error_detail = mark_account_error(int(account_id))
        if not mark_error_success:
            mark_error_detail = shorten_detail(mark_error_detail or (f'HTTP {mark_error_status}' if mark_error_status else 'mark error request failed'))
    elif disable_needed:
        disable_attempted = True
        disable_success, disable_status, disable_detail = disable_account(int(account_id))
        if not disable_success:
            disable_detail = shorten_detail(disable_detail or (f'HTTP {disable_status}' if disable_status else 'disable request failed'))

    if source_status == 'inactive' and native_status != 'success' and native_status != 'token_expired':
        mark_error_attempted = False
        mark_error_success = False
        mark_error_status = None
        mark_error_detail = ''
        disable_attempted = False
        disable_success = False
        disable_status = None
        disable_detail = ''
        if not keep_inactive_attempted:
            keep_inactive_attempted = True
            keep_inactive_success, keep_inactive_status, keep_inactive_detail = disable_account(int(account_id))
            if not keep_inactive_success:
                keep_inactive_detail = shorten_detail(keep_inactive_detail or (f'HTTP {keep_inactive_status}' if keep_inactive_status else 'keep inactive request failed'))

    return {
        'account_id': account_id,
        'name': name,
        'platform': platform,
        'account_type': account_type,
        'source_status': source_status,
        'saw_success': saw_success,
        'latency_ms': latency_ms,
        'native_status': native_status,
        'detail': shorten_detail(result_text if saw_success else error_text),
        'streak_count': streak_count,
        'disable_attempted': disable_attempted,
        'disable_success': disable_success,
        'disable_status': disable_status,
        'disable_detail': disable_detail,
        'mark_error_attempted': mark_error_attempted,
        'mark_error_success': mark_error_success,
        'mark_error_status': mark_error_status,
        'mark_error_detail': mark_error_detail,
        'mark_token_expired_attempted': mark_token_expired_attempted,
        'mark_token_expired_success': mark_token_expired_success,
        'mark_token_expired_status': mark_token_expired_status,
        'mark_token_expired_detail': mark_token_expired_detail,
        'enable_attempted': enable_attempted,
        'enable_success': enable_success,
        'enable_status': enable_status,
        'enable_detail': enable_detail,
        'keep_inactive_attempted': keep_inactive_attempted,
        'keep_inactive_success': keep_inactive_success,
        'keep_inactive_status': keep_inactive_status,
        'keep_inactive_detail': keep_inactive_detail,
    }


for batch_start in range(0, len(rows), batch_size):
    batch = rows[batch_start:batch_start + batch_size]
    with ThreadPoolExecutor(max_workers=batch_size) as executor:
        batch_results = list(executor.map(run_account_test, batch))

    for item in batch_results:
        counts['success' if item['saw_success'] else 'failed'] += 1
        status_counts[item['native_status']] += 1
        processed_account_ids.add(item['account_id'])
        account_state = get_account_state(state, item['account_id'])
        apply_account_state(account_state, item['native_status'], item['streak_count'], item['disable_success'], item['enable_success'])
        if item['mark_error_success']:
            account_state['last_native_status'] = 'error'
        result = 'success' if item['saw_success'] else 'failed'
        display_name = (item['name'] or '').strip() or f"account-{item['account_id']}"
        try:
            message = f"[{result}] account={item['account_id']} name={display_name} platform={item['platform']} type={item['account_type']} source_status={item['source_status']} latency_ms={item['latency_ms']} status={item['native_status']} streak={item['streak_count']} detail={item['detail']}"
            if item['mark_error_attempted']:
                if item['mark_error_success']:
                    message += ' mark_error=success'
                else:
                    message += f" mark_error=failed mark_error_detail={item['mark_error_detail']}"
            if item['mark_token_expired_attempted']:
                if item['mark_token_expired_success']:
                    message += ' mark_token_expired=success'
                else:
                    message += f" mark_token_expired=failed mark_token_expired_detail={item['mark_token_expired_detail']}"
            if item['enable_attempted']:
                if item['enable_success']:
                    message += ' enable=success'
                else:
                    message += f" enable=failed enable_detail={item['enable_detail']}"
            if item['keep_inactive_attempted']:
                if item['keep_inactive_success']:
                    message += ' keep_inactive=success'
                else:
                    message += f" keep_inactive=failed keep_inactive_detail={item['keep_inactive_detail']}"
            if item['disable_attempted']:
                if item['disable_success']:
                    message += ' disable=success'
                else:
                    message += f" disable=failed disable_detail={item['disable_detail']}"
            print(message)
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
        save_state(state_file, state)
    except Exception as exc:
        print(f"state_save_warning={safe_exception_text(exc)}")
    try:
        if state_warning:
            print(state_warning)
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

python3 - "$BIN_FILE" "$CONFIG_FILE" "$DEFAULT_COMPOSE_FILE" "$DEFAULT_APP_CONFIG_FILE" "$LINK_FILE" "$INSTALL_ROOT" "$SUB2TEST_VERSION" "$SUB2TEST_PROJECT_URL" <<'PY'
from pathlib import Path
import sys

bin_path = Path(sys.argv[1])
config_file = sys.argv[2]
compose_file = sys.argv[3]
app_config_file = sys.argv[4]
link_file = sys.argv[5]
install_root = sys.argv[6]
script_version = sys.argv[7]
project_url = sys.argv[8]

content = '''#!/bin/bash
set -euo pipefail

SUB2TEST_VERSION="__SCRIPT_VERSION__"
SUB2TEST_PROJECT_URL="__PROJECT_URL__"
export SUB2TEST_CONFIG_FILE="${SUB2TEST_CONFIG_FILE:-__CONFIG_FILE__}"
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || printf '%s\n' "$0")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
. "$SCRIPT_DIR/lib.sh"
[ -f "$SUB2TEST_CONFIG_FILE" ] && . "$SUB2TEST_CONFIG_FILE"

t() {
  local key="$1"
  local lang="${SUB2TEST_LANGUAGE:-zh}"
  case "$lang:$key" in
    en:menu_title) echo "sub2test menu" ;;
    en:current_tasks) echo "Current automatic tasks:" ;;
    en:full_task) echo "Full run" ;;
    en:untested_task) echo "Untested run" ;;
    en:full_scope) echo " (checks error accounts first, then schedulable active accounts)" ;;
    en:untested_scope) echo " (checks only active accounts not yet seen in state.json)" ;;
    en:not_enabled) echo "Disabled" ;;
    en:enabled_every_30_no_delay) echo "Enabled: runs every 30 minutes%s, with no random delay" ;;
    en:enabled_every_30_with_delay) echo "Enabled: runs every 30 minutes%s, plus a random delay up to %s seconds" ;;
    en:enabled_daily) echo "Enabled: runs every day at %s%s" ;;
    en:enabled_daily_with_delay) echo "Enabled: runs every day at %s%s, plus a random delay up to %s seconds" ;;
    en:enabled_every_hours) echo "Enabled: runs every %s hours%s" ;;
    en:enabled_every_hours_with_delay) echo "Enabled: runs every %s hours%s, plus a random delay up to %s seconds" ;;
    en:enabled_every_minutes) echo "Enabled: runs every %s minutes%s" ;;
    en:enabled_every_minutes_with_delay) echo "Enabled: runs every %s minutes%s, plus a random delay up to %s seconds" ;;
    en:enabled_hourly) echo "Enabled: runs hourly%s" ;;
    en:enabled_weekly) echo "Enabled: runs weekly%s" ;;
    en:enabled_daily_fallback) echo "Enabled: runs daily%s" ;;
    en:config_intro) echo "Current task summary:" ;;
    en:runtime_overview_title) echo "Runtime overview:" ;;
    en:runtime_status_label) echo "Current status" ;;
    en:runtime_last_run_label) echo "Last run" ;;
    en:runtime_last_result_label) echo "Last summary" ;;
    en:runtime_never_ran) echo "No execution record" ;;
    en:runtime_no_summary) echo "No summary recorded" ;;
    en:runtime_status_running) echo "Running" ;;
    en:runtime_status_waiting) echo "Waiting for lock" ;;
    en:runtime_status_starting) echo "Starting" ;;
    en:runtime_status_failed) echo "Failed" ;;
    en:runtime_status_interrupted) echo "Interrupted" ;;
    en:runtime_status_inactive) echo "Idle" ;;
    en:runtime_status_unknown) echo "Unknown" ;;
    en:manual_lock_starting) echo "Starting manual run with lock." ;;
    en:manual_lock_failed) echo "Manual run failed to acquire the lock or exited with an error." ;;
    en:edit_intro) echo "Starting interactive edit. Press Enter to keep the current value." ;;
    en:config_after) echo "Updated task summary:" ;;
    en:invalid_option) echo "Invalid option" ;;
    en:manual_conflict_full_running) echo "Full automatic task is currently running." ;;
    en:manual_conflict_full_waiting) echo "Full automatic task is queued and waiting for its lock." ;;
    en:manual_conflict_untested_running) echo "Untested automatic task is currently running." ;;
    en:manual_conflict_untested_waiting) echo "Untested automatic task is queued and waiting for its lock." ;;
    en:manual_conflict_duplicates_running) echo "Duplicate-account automatic task is currently running." ;;
    en:manual_conflict_duplicates_waiting) echo "Duplicate-account automatic task is queued and waiting for its lock." ;;
    en:manual_conflict_proxy_assign_running) echo "Proxy-assignment automatic task is currently running." ;;
    en:manual_conflict_proxy_assign_waiting) echo "Proxy-assignment automatic task is queued and waiting for its lock." ;;
    en:menu_enable_proxy_assign) echo "Enable proxy-assignment task" ;;
    en:menu_disable_proxy_assign) echo "Disable proxy-assignment task" ;;
    en:proxy_assign_menu_title) echo "Proxy-assignment task menu" ;;
    en:proxy_assign_menu_config) echo "Edit proxy-assignment config" ;;
    en:proxy_assign_menu_enable) echo "Enable proxy-assignment task" ;;
    en:proxy_assign_menu_disable) echo "Disable proxy-assignment task" ;;
    en:proxy_assign_menu_run) echo "Run once (assign proxies to accounts without proxy)" ;;
    en:proxy_assign_menu_show_log) echo "Show last proxy-assignment log" ;;
    en:proxy_assign_config_title) echo "Current proxy-assignment task parameters:" ;;
    en:proxy_assign_task) echo "Proxy assignment" ;;
    en:proxy_assign_scope) echo " (assigns active proxies to accounts without proxy)" ;;
    en:label_proxy_assign_enabled) echo "Enable proxy-assignment task" ;;
    en:label_proxy_assign_every_minutes) echo "Run proxy-assignment task every N minutes (5-720)" ;;
    en:label_proxy_assign_delay) echo "Proxy-assignment random delay seconds" ;;
    en:label_proxy_assign_mode) echo "Proxy-assignment mode (index/random)" ;;
    en:label_proxy_assign_index) echo "Proxy-assignment index (1-based for index mode)" ;;
    en:last_proxy_assign_log_title) echo "Last proxy-assignment log:" ;;
    en:menu_groups_task) echo "Unauthorized-group menu" ;;
    en:groups_menu_title) echo "Unauthorized-group menu" ;;
    en:groups_menu_list) echo "List active groups" ;;
    en:groups_menu_set_openai) echo "Set OpenAI unauthorized group" ;;
    en:groups_menu_set_anthropic) echo "Set Anthropic unauthorized group" ;;
    en:groups_menu_set_gemini) echo "Set Gemini unauthorized group" ;;
    en:groups_menu_set_antigravity) echo "Set Antigravity unauthorized group" ;;
    en:groups_menu_edit_all) echo "Edit all unauthorized groups" ;;
    en:groups_config_title) echo "Current unauthorized-group parameters:" ;;
    en:groups_list_title) echo "Active groups:" ;;
    en:groups_list_empty) echo "No active groups found." ;;
    en:groups_list_failed) echo "Failed to fetch groups." ;;
    en:label_unauthorized_group_openai) echo "OpenAI unauthorized group ID" ;;
    en:label_unauthorized_group_anthropic) echo "Anthropic unauthorized group ID" ;;
    en:label_unauthorized_group_gemini) echo "Gemini unauthorized group ID" ;;
    en:label_unauthorized_group_antigravity) echo "Antigravity unauthorized group ID" ;;
    en:manual_conflict_prompt) echo "Stop the running or queued automatic task(s) and continue with this manual run? [y/N]" ;;
    en:manual_conflict_cancelled) echo "Manual run cancelled." ;;
    en:manual_conflict_stopping) echo "Stopping automatic task(s)..." ;;
    en:manual_conflict_stopped) echo "Automatic task(s) stopped. Starting manual run." ;;
    en:manual_conflict_stop_failed) echo "Automatic task(s) are still stopping or waiting. Please try again." ;;
    en:menu_enable_full) echo "Enable full automatic task" ;;
    en:menu_disable_full) echo "Disable full automatic task" ;;
    en:menu_edit) echo "Edit global config" ;;
    en:menu_enable_duplicates) echo "Enable duplicate-account check" ;;
    en:menu_disable_duplicates) echo "Disable duplicate-account check" ;;
    en:duplicates_menu_title) echo "Duplicate-account task menu" ;;
    en:duplicates_menu_config) echo "Edit duplicate-account config" ;;
    en:duplicates_menu_enable) echo "Enable duplicate-account task" ;;
    en:duplicates_menu_disable) echo "Disable duplicate-account task" ;;
    en:duplicates_menu_show_log) echo "Show last duplicate-account log" ;;
    en:duplicates_config_title) echo "Current duplicate-account task parameters:" ;;
    en:duplicates_task) echo "Duplicate-account check" ;;
    en:duplicates_scope) echo " (checks duplicate names and disables extra accounts)" ;;
    en:label_duplicates_enabled) echo "Enable duplicate-account task" ;;
    en:label_duplicates_every_minutes) echo "Run duplicate-account check every N minutes (5-720)" ;;
    en:label_duplicates_delay) echo "Duplicate-account random delay seconds" ;;
    en:label_duplicates_skip_inactive) echo "Skip inactive accounts when checking duplicates" ;;
    en:last_duplicates_log_title) echo "Last duplicate-account log:" ;;
    en:menu_full_task) echo "Full task menu" ;;
    en:menu_duplicates_task) echo "Duplicate-account task menu" ;;
    en:menu_untested_task) echo "Untested task menu" ;;
    en:menu_manual_run) echo "Manual run menu" ;;
    en:menu_back) echo "Back (0)" ;;
    en:full_menu_title) echo "Full task menu" ;;
    en:untested_menu_title) echo "Untested task menu" ;;
    en:manual_menu_title) echo "Manual run menu" ;;
    en:full_menu_config) echo "Edit full task config" ;;
    en:full_menu_enable) echo "Enable full automatic task" ;;
    en:full_menu_disable) echo "Disable full automatic task" ;;
    en:full_menu_run_all) echo "Run once (active + error accounts)" ;;
    en:full_menu_run_error) echo "Run once (error accounts only)" ;;
    en:full_menu_run_disabled) echo "Run once (disabled accounts only)" ;;
    en:full_menu_show_log) echo "Show last full-task log" ;;
    en:untested_menu_config) echo "Edit untested task config" ;;
    en:untested_menu_enable) echo "Enable untested automatic task" ;;
    en:untested_menu_disable) echo "Disable untested automatic task" ;;
    en:untested_menu_run) echo "Run once (untested active accounts only)" ;;
    en:untested_menu_show_log) echo "Show last untested-task log" ;;
    en:global_config_title) echo "Current global parameters:" ;;
    en:full_config_title) echo "Current full task parameters:" ;;
    en:untested_config_title) echo "Current untested task parameters:" ;;
    en:menu_run_all) echo "Run once (all)" ;;
    en:menu_run_error) echo "Run error accounts only" ;;
    en:menu_run_disabled) echo "Run disabled accounts only" ;;
    en:menu_run_untested) echo "Run untested active accounts only" ;;
    en:menu_show_config) echo "Show current config" ;;
    en:menu_show_full_log) echo "Show last full-task log" ;;
    en:menu_show_untested_log) echo "Show last untested-task log" ;;
    en:menu_switch_language) echo "Switch language" ;;
    en:last_full_log_title) echo "Last full automatic task log:" ;;
    en:last_untested_log_title) echo "Last untested automatic task log:" ;;
    en:language_menu_title) echo "Choose interface language:" ;;
    en:language_option_zh) echo "Chinese" ;;
    en:language_option_en) echo "English" ;;
    en:language_saved) echo "Interface language updated." ;;
    en:menu_uninstall) echo "Uninstall script and timers" ;;
    en:menu_exit) echo "Exit (0)" ;;
    en:label_deploy_mode) echo "Deploy mode (usually keep compose)" ;;
    en:label_compose_file) echo "Path to docker-compose.yml" ;;
    en:label_app_config_file) echo "Path to Sub2API config file" ;;
    en:label_db_host) echo "Database host (leave blank for auto-detect)" ;;
    en:label_db_port) echo "Database port" ;;
    en:label_db_user) echo "Database user (leave blank for auto-detect)" ;;
    en:label_db_password) echo "Database password (leave blank for auto-detect)" ;;
    en:label_db_name) echo "Database name (leave blank for auto-detect)" ;;
    en:label_db_sslmode) echo "Database SSL mode" ;;
    en:label_db_container) echo "Database container name (prefer container query when set)" ;;
    en:label_api_base_url) echo "Admin API base URL" ;;
    en:label_admin_api_key) echo "Admin API key" ;;
    en:label_error_threshold) echo "Disable after this many consecutive errors" ;;
    en:label_state_file) echo "Local state file path" ;;
    en:label_lock_wait_seconds) echo "Shared lock wait seconds (0 means fail immediately)" ;;
    en:label_untested_enabled) echo "Enable automatic task for untested accounts" ;;
    en:label_untested_every_minutes) echo "Run untested task every N minutes (5-720)" ;;
    en:label_untested_delay) echo "Untested task random delay seconds" ;;
    en:label_full_schedule) echo "Full task schedule mode" ;;
    en:label_full_daily_at) echo "Full task daily run time (HH:MM, leave blank to disable)" ;;
    en:label_full_every_hours) echo "Full task every N hours (1-23, leave blank to disable)" ;;
    en:label_full_delay) echo "Full task random delay seconds" ;;
    en:schedule_mode_title) echo "Choose full task schedule mode:" ;;
    en:schedule_mode_hourly) echo "Hourly" ;;
    en:schedule_mode_daily) echo "Daily" ;;
    en:schedule_mode_weekly) echo "Weekly" ;;
    en:schedule_mode_every_hours) echo "Every N hours" ;;
    en:schedule_mode_daily_at) echo "Daily at fixed time" ;;
    en:label_concurrency) echo "How many accounts to test per batch" ;;
    en:label_timeout) echo "Timeout per account test in seconds" ;;
    en:label_sleep_min) echo "Minimum pause between batches in seconds" ;;
    en:label_sleep_max) echo "Maximum pause between batches in seconds" ;;
    zh:menu_title) echo "sub2test 菜单" ;;
    zh:current_tasks) echo "当前自动任务：" ;;
    zh:full_task) echo "全量任务" ;;
    zh:untested_task) echo "未测任务" ;;
    zh:full_scope) echo "（优先测 error，再测可调度的 active 账号）" ;;
    zh:untested_scope) echo "（只测 state.json 里还没出现过的 active 账号）" ;;
    zh:not_enabled) echo "未启用" ;;
    zh:enabled_every_30_no_delay) echo "已启用：每 30 分钟自动执行一次%s，不加随机延迟" ;;
    zh:enabled_every_30_with_delay) echo "已启用：每 30 分钟自动执行一次%s，并额外随机延后 %s 秒" ;;
    zh:enabled_daily) echo "已启用：每天 %s 自动执行一次%s" ;;
    zh:enabled_daily_with_delay) echo "已启用：每天 %s 自动执行一次%s，并额外随机延后 %s 秒" ;;
    zh:enabled_every_hours) echo "已启用：每 %s 小时自动执行一次%s" ;;
    zh:enabled_every_hours_with_delay) echo "已启用：每 %s 小时自动执行一次%s，并额外随机延后 %s 秒" ;;
    zh:enabled_every_minutes) echo "已启用：每 %s 分钟自动执行一次%s" ;;
    zh:enabled_every_minutes_with_delay) echo "已启用：每 %s 分钟自动执行一次%s，并额外随机延后 %s 秒" ;;
    zh:enabled_hourly) echo "已启用：每小时自动执行一次%s" ;;
    zh:enabled_weekly) echo "已启用：每周自动执行一次%s" ;;
    zh:enabled_daily_fallback) echo "已启用：每天自动执行一次%s" ;;
    zh:config_intro) echo "当前自动任务说明：" ;;
    zh:runtime_overview_title) echo "运行概览：" ;;
    zh:runtime_status_label) echo "当前状态" ;;
    zh:runtime_last_run_label) echo "上次执行时间" ;;
    zh:runtime_last_result_label) echo "上次汇总结果" ;;
    zh:runtime_never_ran) echo "暂无执行记录" ;;
    zh:runtime_no_summary) echo "最近一次未产生汇总" ;;
    zh:runtime_status_running) echo "正在执行" ;;
    zh:runtime_status_waiting) echo "排队等待锁" ;;
    zh:runtime_status_starting) echo "启动中" ;;
    zh:runtime_status_failed) echo "执行失败" ;;
    zh:runtime_status_interrupted) echo "已中断" ;;
    zh:runtime_status_inactive) echo "空闲" ;;
    zh:runtime_status_unknown) echo "未知" ;;
    zh:manual_lock_starting) echo "开始通过锁执行手动任务。" ;;
    zh:manual_lock_failed) echo "手动任务获取锁失败或执行出错。" ;;
    zh:edit_intro) echo "下面开始逐项编辑；直接回车表示保持当前值。" ;;
    zh:config_after) echo "修改后的自动任务说明：" ;;
    zh:invalid_option) echo "无效选项" ;;
    zh:manual_conflict_full_running) echo "全量自动任务正在执行。" ;;
    zh:manual_conflict_full_waiting) echo "全量自动任务正在排队等待它的锁。" ;;
    zh:manual_conflict_untested_running) echo "未测自动任务正在执行。" ;;
    zh:manual_conflict_untested_waiting) echo "未测自动任务正在排队等待它的锁。" ;;
    zh:manual_conflict_duplicates_running) echo "重复账号排查自动任务正在执行。" ;;
    zh:manual_conflict_duplicates_waiting) echo "重复账号排查自动任务正在排队等待它的锁。" ;;
    zh:manual_conflict_proxy_assign_running) echo "代理分配自动任务正在执行。" ;;
    zh:manual_conflict_proxy_assign_waiting) echo "代理分配自动任务正在排队等待它的锁。" ;;
    zh:menu_enable_proxy_assign) echo "启用代理分配任务" ;;
    zh:menu_disable_proxy_assign) echo "禁用代理分配任务" ;;
    zh:proxy_assign_menu_title) echo "代理分配任务菜单" ;;
    zh:proxy_assign_menu_config) echo "编辑代理分配任务配置" ;;
    zh:proxy_assign_menu_enable) echo "启用代理分配任务" ;;
    zh:proxy_assign_menu_disable) echo "禁用代理分配任务" ;;
    zh:proxy_assign_menu_run) echo "立即执行一次（给无代理账号分配代理）" ;;
    zh:proxy_assign_menu_show_log) echo "查看上次代理分配日志" ;;
    zh:proxy_assign_config_title) echo "当前代理分配任务参数：" ;;
    zh:proxy_assign_task) echo "代理分配" ;;
    zh:proxy_assign_scope) echo "（给无代理账号分配 active 代理）" ;;
    zh:label_proxy_assign_enabled) echo "是否启用代理分配任务" ;;
    zh:label_proxy_assign_every_minutes) echo "代理分配任务每隔多少分钟执行一次（5-720）" ;;
    zh:label_proxy_assign_delay) echo "代理分配任务随机延迟秒数" ;;
    zh:label_proxy_assign_mode) echo "代理分配模式（index/random）" ;;
    zh:label_proxy_assign_index) echo "代理分配序号（index 模式从 1 开始）" ;;
    zh:last_proxy_assign_log_title) echo "上次代理分配日志：" ;;
    zh:menu_groups_task) echo "未授权分组菜单" ;;
    zh:groups_menu_title) echo "未授权分组菜单" ;;
    zh:groups_menu_list) echo "查看 active 分组" ;;
    zh:groups_menu_set_openai) echo "配置 OpenAI 未授权分组" ;;
    zh:groups_menu_set_anthropic) echo "配置 Anthropic 未授权分组" ;;
    zh:groups_menu_set_gemini) echo "配置 Gemini 未授权分组" ;;
    zh:groups_menu_set_antigravity) echo "配置 Antigravity 未授权分组" ;;
    zh:groups_menu_edit_all) echo "编辑全部未授权分组" ;;
    zh:groups_config_title) echo "当前未授权分组参数：" ;;
    zh:groups_list_title) echo "Active 分组列表：" ;;
    zh:groups_list_empty) echo "没有查到 active 分组。" ;;
    zh:groups_list_failed) echo "获取分组失败。" ;;
    zh:label_unauthorized_group_openai) echo "OpenAI 未授权分组 ID" ;;
    zh:label_unauthorized_group_anthropic) echo "Anthropic 未授权分组 ID" ;;
    zh:label_unauthorized_group_gemini) echo "Gemini 未授权分组 ID" ;;
    zh:label_unauthorized_group_antigravity) echo "Antigravity 未授权分组 ID" ;;
    zh:menu_proxy_assign_task) echo "代理分配任务菜单" ;;
    zh:menu_run_proxy_assign) echo "立即执行代理分配一次" ;;
    zh:manual_conflict_prompt) echo "是否停止这些正在执行或排队的自动任务，并继续本次手动执行？[y/N]" ;;
    zh:manual_conflict_cancelled) echo "已取消本次手动执行。" ;;
    zh:manual_conflict_stopping) echo "正在停止自动任务..." ;;
    zh:manual_conflict_stopped) echo "自动任务已停止，开始执行手动任务。" ;;
    zh:manual_conflict_stop_failed) echo "自动任务仍在停止或等待中，请稍后重试。" ;;
    zh:menu_enable_full) echo "启用自动任务" ;;
    zh:menu_disable_full) echo "禁用自动任务" ;;
    zh:menu_edit) echo "编辑全局配置" ;;
    zh:menu_enable_duplicates) echo "启用重复账号排查任务" ;;
    zh:menu_disable_duplicates) echo "禁用重复账号排查任务" ;;
    zh:duplicates_menu_title) echo "重复账号任务菜单" ;;
    zh:duplicates_menu_config) echo "编辑重复账号任务配置" ;;
    zh:duplicates_menu_enable) echo "启用重复账号排查任务" ;;
    zh:duplicates_menu_disable) echo "禁用重复账号排查任务" ;;
    zh:duplicates_menu_show_log) echo "查看上次重复账号排查日志" ;;
    zh:duplicates_config_title) echo "当前重复账号任务参数：" ;;
    zh:duplicates_task) echo "重复账号排查" ;;
    zh:duplicates_scope) echo "（排查同名重复账号并停用多余记录）" ;;
    zh:label_duplicates_enabled) echo "是否启用重复账号排查任务" ;;
    zh:label_duplicates_every_minutes) echo "重复账号排查每隔多少分钟执行一次（5-720）" ;;
    zh:label_duplicates_delay) echo "重复账号任务随机延迟秒数" ;;
    zh:label_duplicates_skip_inactive) echo "排查重复时是否跳过停用账号" ;;
    zh:last_duplicates_log_title) echo "上次重复账号排查日志：" ;;
    zh:menu_full_task) echo "全量任务菜单" ;;
    zh:menu_duplicates_task) echo "重复账号任务菜单" ;;
    zh:menu_untested_task) echo "未测任务菜单" ;;
    zh:menu_manual_run) echo "手动执行菜单" ;;
    zh:menu_back) echo "返回上一级（0）" ;;
    zh:full_menu_title) echo "全量任务菜单" ;;
    zh:untested_menu_title) echo "未测任务菜单" ;;
    zh:manual_menu_title) echo "手动执行菜单" ;;
    zh:full_menu_config) echo "编辑全量任务配置" ;;
    zh:full_menu_enable) echo "启用全量自动任务" ;;
    zh:full_menu_disable) echo "禁用全量自动任务" ;;
    zh:full_menu_run_all) echo "立即执行一次（生效 + error 账号）" ;;
    zh:full_menu_run_error) echo "立即执行一次（仅 error 账号）" ;;
    zh:full_menu_run_disabled) echo "立即执行一次（仅 disabled 账号）" ;;
    zh:full_menu_show_log) echo "查看上次全量自动任务日志" ;;
    zh:untested_menu_config) echo "编辑未测任务配置" ;;
    zh:untested_menu_enable) echo "启用未测自动任务" ;;
    zh:untested_menu_disable) echo "禁用未测自动任务" ;;
    zh:untested_menu_run) echo "立即执行一次（仅未测 active 账号）" ;;
    zh:untested_menu_show_log) echo "查看上次未测自动任务日志" ;;
    zh:global_config_title) echo "当前全局参数：" ;;
    zh:full_config_title) echo "当前全量任务参数：" ;;
    zh:untested_config_title) echo "当前未测任务参数：" ;;
    zh:menu_run_all) echo "立即执行一次（生效 + error）" ;;
    zh:menu_run_error) echo "仅测试 error 账号" ;;
    zh:menu_run_disabled) echo "仅测试 disabled 账号" ;;
    zh:menu_run_untested) echo "仅测试未测试 active 账号" ;;
    zh:menu_show_config) echo "查看当前配置" ;;
    zh:menu_show_full_log) echo "查看上次全量自动任务日志" ;;
    zh:menu_show_untested_log) echo "查看上次未测自动任务日志" ;;
    zh:menu_switch_language) echo "切换语言" ;;
    zh:last_full_log_title) echo "上次全量自动任务日志：" ;;
    zh:last_untested_log_title) echo "上次未测自动任务日志：" ;;
    zh:language_menu_title) echo "选择界面语言：" ;;
    zh:language_option_zh) echo "中文" ;;
    zh:language_option_en) echo "English" ;;
    zh:language_saved) echo "界面语言已更新。" ;;
    zh:menu_uninstall) echo "卸载脚本和定时器" ;;
    zh:menu_exit) echo "退出（0）" ;;
    zh:label_deploy_mode) echo "部署方式（一般保持 compose）" ;;
    zh:label_compose_file) echo "docker-compose.yml 路径" ;;
    zh:label_app_config_file) echo "Sub2API 配置文件路径" ;;
    zh:label_db_host) echo "数据库主机地址（留空表示自动识别）" ;;
    zh:label_db_port) echo "数据库端口" ;;
    zh:label_db_user) echo "数据库用户名（留空表示自动识别）" ;;
    zh:label_db_password) echo "数据库密码（留空表示自动识别）" ;;
    zh:label_db_name) echo "数据库名（留空表示自动识别）" ;;
    zh:label_db_sslmode) echo "数据库 SSL 模式" ;;
    zh:label_db_container) echo "数据库容器名（设置后优先走容器查库）" ;;
    zh:label_api_base_url) echo "管理端 API 地址" ;;
    zh:label_admin_api_key) echo "管理端 API Key" ;;
    zh:label_error_threshold) echo "连续报错多少次后停用账号" ;;
    zh:label_state_file) echo "本地状态文件路径" ;;
    zh:label_lock_wait_seconds) echo "等待锁最多多少秒（0 表示不等待）" ;;
    zh:label_untested_enabled) echo "是否启用未测账号自动任务" ;;
    zh:label_untested_every_minutes) echo "未测任务每隔多少分钟执行一次（5-720）" ;;
    zh:label_untested_delay) echo "未测任务随机延迟秒数" ;;
    zh:label_full_schedule) echo "全量任务调度模式" ;;
    zh:label_full_daily_at) echo "全量任务每天几点执行（HH:MM，留空表示不用这个）" ;;
    zh:label_full_every_hours) echo "全量任务每隔几小时执行一次（1-23，留空表示不用这个）" ;;
    zh:label_full_delay) echo "全量任务随机延迟秒数" ;;
    zh:schedule_mode_title) echo "请选择全量任务调度模式：" ;;
    zh:schedule_mode_hourly) echo "每小时一次" ;;
    zh:schedule_mode_daily) echo "每天一次" ;;
    zh:schedule_mode_weekly) echo "每周一次" ;;
    zh:schedule_mode_every_hours) echo "每隔几小时执行一次" ;;
    zh:schedule_mode_daily_at) echo "每天固定时间执行" ;;
    zh:label_concurrency) echo "每批同时测试几个账号" ;;
    zh:label_timeout) echo "单个账号测试超时秒数" ;;
    zh:label_sleep_min) echo "批次之间最少暂停几秒" ;;
    zh:label_sleep_max) echo "批次之间最多暂停几秒" ;;
    *) echo "$key" ;;
  esac
}

show_config() {
  echo "SUB2TEST_VERSION=$SUB2TEST_VERSION    # 当前脚本版本"
  echo "SUB2TEST_PROJECT_URL=$SUB2TEST_PROJECT_URL    # 项目地址"
  echo "SUB2TEST_DEPLOY_MODE=${SUB2TEST_DEPLOY_MODE:-compose}    # 运行模式：compose=自动识别数据库配置"
  echo "SUB2TEST_COMPOSE_FILE=${SUB2TEST_COMPOSE_FILE:-__COMPOSE_FILE__}    # docker-compose.yml 路径"
  echo "SUB2API_CONFIG_FILE=${SUB2API_CONFIG_FILE:-__APP_CONFIG_FILE__}    # Sub2API config.yaml 路径"
  echo "SUB2TEST_DB_HOST=${SUB2TEST_DB_HOST:-}    # 数据库主机"
  echo "SUB2TEST_DB_PORT=${SUB2TEST_DB_PORT:-5432}    # 数据库端口"
  echo "SUB2TEST_DB_USER=${SUB2TEST_DB_USER:-}    # 数据库用户名"
  echo "SUB2TEST_DB_NAME=${SUB2TEST_DB_NAME:-}    # 数据库名"
  echo "SUB2TEST_DB_SSLMODE=${SUB2TEST_DB_SSLMODE:-disable}    # 数据库 SSL 模式"
  echo "SUB2TEST_DB_CONTAINER=${SUB2TEST_DB_CONTAINER:-}    # 数据库容器名（设置后优先容器查库）"
  echo "SUB2TEST_API_BASE_URL=${SUB2TEST_API_BASE_URL:-}    # 管理端 API 基础地址"
  echo "SUB2TEST_ADMIN_API_KEY=${SUB2TEST_ADMIN_API_KEY:+***set***}    # 管理端 API Key"
  echo "SUB2TEST_UNAUTHORIZED_GROUP_OPENAI=${SUB2TEST_UNAUTHORIZED_GROUP_OPENAI:-}    # OpenAI token_expired 未授权分组 ID"
  echo "SUB2TEST_UNAUTHORIZED_GROUP_ANTHROPIC=${SUB2TEST_UNAUTHORIZED_GROUP_ANTHROPIC:-}    # Anthropic token_expired 未授权分组 ID"
  echo "SUB2TEST_UNAUTHORIZED_GROUP_GEMINI=${SUB2TEST_UNAUTHORIZED_GROUP_GEMINI:-}    # Gemini token_expired 未授权分组 ID"
  echo "SUB2TEST_UNAUTHORIZED_GROUP_ANTIGRAVITY=${SUB2TEST_UNAUTHORIZED_GROUP_ANTIGRAVITY:-}    # Antigravity token_expired 未授权分组 ID"
  echo "SUB2TEST_ERROR_STREAK_THRESHOLD=${SUB2TEST_ERROR_STREAK_THRESHOLD:-3}    # 连续 error 停用阈值"
  echo "SUB2TEST_STATE_FILE=${SUB2TEST_STATE_FILE:-/opt/sub2test/state.json}    # 本地状态文件路径"
  echo "SUB2TEST_LOCK_WAIT_SECONDS=${SUB2TEST_LOCK_WAIT_SECONDS:-3600}    # 等待锁最多秒数，0 表示不等待"
  echo "SUB2TEST_PROXY_ASSIGN_ENABLED=${SUB2TEST_PROXY_ASSIGN_ENABLED:-false}    # 是否启用代理分配任务"
  echo "SUB2TEST_PROXY_ASSIGN_EVERY_MINUTES=${SUB2TEST_PROXY_ASSIGN_EVERY_MINUTES:-60}    # 代理分配任务每隔多少分钟执行一次"
  echo "SUB2TEST_PROXY_ASSIGN_RANDOMIZED_DELAY_SECONDS=${SUB2TEST_PROXY_ASSIGN_RANDOMIZED_DELAY_SECONDS:-120}    # 代理分配任务 systemd 随机延迟秒数"
  echo "SUB2TEST_PROXY_ASSIGN_MODE=${SUB2TEST_PROXY_ASSIGN_MODE:-index}    # 代理分配模式：index/random"
  echo "SUB2TEST_PROXY_ASSIGN_INDEX=${SUB2TEST_PROXY_ASSIGN_INDEX:-1}    # 代理分配模式为 index 时的序号"
  echo "SUB2TEST_DUPLICATES_ENABLED=${SUB2TEST_DUPLICATES_ENABLED:-false}    # 是否启用重复账号排查任务"
  echo "SUB2TEST_DUPLICATES_EVERY_MINUTES=${SUB2TEST_DUPLICATES_EVERY_MINUTES:-60}    # 重复账号排查每隔多少分钟执行一次"
  echo "SUB2TEST_DUPLICATES_RANDOMIZED_DELAY_SECONDS=${SUB2TEST_DUPLICATES_RANDOMIZED_DELAY_SECONDS:-120}    # 重复账号排查 systemd 随机延迟秒数"
  echo "SUB2TEST_DUPLICATES_SKIP_INACTIVE=${SUB2TEST_DUPLICATES_SKIP_INACTIVE:-true}    # 排查重复时是否跳过停用账号"
  echo "SUB2TEST_UNTESTED_ENABLED=${SUB2TEST_UNTESTED_ENABLED:-false}    # 是否启用未测试 active 账号独立定时任务"
  echo "SUB2TEST_UNTESTED_EVERY_MINUTES=${SUB2TEST_UNTESTED_EVERY_MINUTES:-30}    # 未测试 active 账号每隔多少分钟执行一次"
  echo "SUB2TEST_UNTESTED_RANDOMIZED_DELAY_SECONDS=${SUB2TEST_UNTESTED_RANDOMIZED_DELAY_SECONDS:-120}    # 未测试 active 账号 systemd 随机延迟秒数"
  echo "SUB2TEST_ENABLED=${SUB2TEST_ENABLED:-false}    # 是否启用全量自动任务"
  echo "SUB2TEST_SCHEDULE=${SUB2TEST_SCHEDULE:-daily}    # 兼容旧定时频率"
  echo "SUB2TEST_DAILY_AT=${SUB2TEST_DAILY_AT:-}    # 每天执行时间，格式 HH:MM"
  echo "SUB2TEST_EVERY_HOURS=${SUB2TEST_EVERY_HOURS:-}    # 每隔几小时执行一次"
  echo "SUB2TEST_RANDOMIZED_DELAY_SECONDS=${SUB2TEST_RANDOMIZED_DELAY_SECONDS:-120}    # systemd 随机延迟秒数"
  echo "SUB2TEST_CONCURRENCY=${SUB2TEST_CONCURRENCY:-3}    # 每批并发账号数"
  echo "SUB2TEST_TIMEOUT_SECONDS=${SUB2TEST_TIMEOUT_SECONDS:-30}    # 单账号测试超时秒数"
  echo "SUB2TEST_SLEEP_MIN_SECONDS=${SUB2TEST_SLEEP_MIN_SECONDS:-3}    # 批间最小暂停秒数"
  echo "SUB2TEST_SLEEP_MAX_SECONDS=${SUB2TEST_SLEEP_MAX_SECONDS:-10}    # 批间最大暂停秒数"
}

show_global_config() {
  echo "$(t global_config_title)"
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
  echo "SUB2TEST_UNAUTHORIZED_GROUP_OPENAI=${SUB2TEST_UNAUTHORIZED_GROUP_OPENAI:-}"
  echo "SUB2TEST_UNAUTHORIZED_GROUP_ANTHROPIC=${SUB2TEST_UNAUTHORIZED_GROUP_ANTHROPIC:-}"
  echo "SUB2TEST_UNAUTHORIZED_GROUP_GEMINI=${SUB2TEST_UNAUTHORIZED_GROUP_GEMINI:-}"
  echo "SUB2TEST_UNAUTHORIZED_GROUP_ANTIGRAVITY=${SUB2TEST_UNAUTHORIZED_GROUP_ANTIGRAVITY:-}"
  echo "SUB2TEST_ERROR_STREAK_THRESHOLD=${SUB2TEST_ERROR_STREAK_THRESHOLD:-3}"
  echo "SUB2TEST_STATE_FILE=${SUB2TEST_STATE_FILE:-/opt/sub2test/state.json}"
  echo "SUB2TEST_LOCK_WAIT_SECONDS=${SUB2TEST_LOCK_WAIT_SECONDS:-3600}"
  echo "SUB2TEST_PROXY_ASSIGN_ENABLED=${SUB2TEST_PROXY_ASSIGN_ENABLED:-false}"
  echo "SUB2TEST_PROXY_ASSIGN_EVERY_MINUTES=${SUB2TEST_PROXY_ASSIGN_EVERY_MINUTES:-60}"
  echo "SUB2TEST_PROXY_ASSIGN_RANDOMIZED_DELAY_SECONDS=${SUB2TEST_PROXY_ASSIGN_RANDOMIZED_DELAY_SECONDS:-120}"
  echo "SUB2TEST_PROXY_ASSIGN_MODE=${SUB2TEST_PROXY_ASSIGN_MODE:-index}"
  echo "SUB2TEST_PROXY_ASSIGN_INDEX=${SUB2TEST_PROXY_ASSIGN_INDEX:-1}"
  echo "SUB2TEST_DUPLICATES_ENABLED=${SUB2TEST_DUPLICATES_ENABLED:-false}"
  echo "SUB2TEST_DUPLICATES_EVERY_MINUTES=${SUB2TEST_DUPLICATES_EVERY_MINUTES:-60}"
  echo "SUB2TEST_DUPLICATES_RANDOMIZED_DELAY_SECONDS=${SUB2TEST_DUPLICATES_RANDOMIZED_DELAY_SECONDS:-120}"
  echo "SUB2TEST_DUPLICATES_SKIP_INACTIVE=${SUB2TEST_DUPLICATES_SKIP_INACTIVE:-true}"
  echo "SUB2TEST_CONCURRENCY=${SUB2TEST_CONCURRENCY:-3}"
  echo "SUB2TEST_TIMEOUT_SECONDS=${SUB2TEST_TIMEOUT_SECONDS:-30}"
  echo "SUB2TEST_SLEEP_MIN_SECONDS=${SUB2TEST_SLEEP_MIN_SECONDS:-3}"
  echo "SUB2TEST_SLEEP_MAX_SECONDS=${SUB2TEST_SLEEP_MAX_SECONDS:-10}"
}

show_full_task_config() {
  echo "$(t full_config_title)"
  echo "SUB2TEST_ENABLED=${SUB2TEST_ENABLED:-false}"
  echo "SUB2TEST_SCHEDULE=${SUB2TEST_SCHEDULE:-daily}"
  echo "SUB2TEST_DAILY_AT=${SUB2TEST_DAILY_AT:-}"
  echo "SUB2TEST_EVERY_HOURS=${SUB2TEST_EVERY_HOURS:-}"
  echo "SUB2TEST_RANDOMIZED_DELAY_SECONDS=${SUB2TEST_RANDOMIZED_DELAY_SECONDS:-120}"
}

show_untested_task_config() {
  echo "$(t untested_config_title)"
  echo "SUB2TEST_UNTESTED_ENABLED=${SUB2TEST_UNTESTED_ENABLED:-false}"
  echo "SUB2TEST_UNTESTED_EVERY_MINUTES=${SUB2TEST_UNTESTED_EVERY_MINUTES:-30}"
  echo "SUB2TEST_UNTESTED_RANDOMIZED_DELAY_SECONDS=${SUB2TEST_UNTESTED_RANDOMIZED_DELAY_SECONDS:-120}"
}

show_proxy_assign_task_config() {
  echo "$(t proxy_assign_config_title)"
  echo "SUB2TEST_PROXY_ASSIGN_ENABLED=${SUB2TEST_PROXY_ASSIGN_ENABLED:-false}"
  echo "SUB2TEST_PROXY_ASSIGN_EVERY_MINUTES=${SUB2TEST_PROXY_ASSIGN_EVERY_MINUTES:-60}"
  echo "SUB2TEST_PROXY_ASSIGN_RANDOMIZED_DELAY_SECONDS=${SUB2TEST_PROXY_ASSIGN_RANDOMIZED_DELAY_SECONDS:-120}"
  echo "SUB2TEST_PROXY_ASSIGN_MODE=${SUB2TEST_PROXY_ASSIGN_MODE:-index}"
  echo "SUB2TEST_PROXY_ASSIGN_INDEX=${SUB2TEST_PROXY_ASSIGN_INDEX:-1}"
}

show_groups_task_config() {
  echo "$(t groups_config_title)"
  echo "SUB2TEST_UNAUTHORIZED_GROUP_OPENAI=${SUB2TEST_UNAUTHORIZED_GROUP_OPENAI:-}"
  echo "SUB2TEST_UNAUTHORIZED_GROUP_ANTHROPIC=${SUB2TEST_UNAUTHORIZED_GROUP_ANTHROPIC:-}"
  echo "SUB2TEST_UNAUTHORIZED_GROUP_GEMINI=${SUB2TEST_UNAUTHORIZED_GROUP_GEMINI:-}"
  echo "SUB2TEST_UNAUTHORIZED_GROUP_ANTIGRAVITY=${SUB2TEST_UNAUTHORIZED_GROUP_ANTIGRAVITY:-}"
}

show_duplicates_task_config() {
  echo "$(t duplicates_config_title)"
  echo "SUB2TEST_DUPLICATES_ENABLED=${SUB2TEST_DUPLICATES_ENABLED:-false}"
  echo "SUB2TEST_DUPLICATES_EVERY_MINUTES=${SUB2TEST_DUPLICATES_EVERY_MINUTES:-60}"
  echo "SUB2TEST_DUPLICATES_RANDOMIZED_DELAY_SECONDS=${SUB2TEST_DUPLICATES_RANDOMIZED_DELAY_SECONDS:-120}"
  echo "SUB2TEST_DUPLICATES_SKIP_INACTIVE=${SUB2TEST_DUPLICATES_SKIP_INACTIVE:-true}"
}

schedule_summary() {
  local enabled="$1"
  local daily_at="$2"
  local every_hours="$3"
  local fallback_schedule="$4"
  local every_30_minutes="${5:-false}"
  local randomized_delay="$6"
  local scope="$7"

  if [ "$enabled" != "true" ]; then
    t not_enabled
    return 0
  fi

  if [ "$every_30_minutes" = "true" ]; then
    if [ -n "$randomized_delay" ] && [ "$randomized_delay" != "0" ]; then
      printf "$(t enabled_every_30_with_delay)" "$scope" "$randomized_delay"
    else
      printf "$(t enabled_every_30_no_delay)" "$scope"
    fi
    return 0
  fi

  if [ -n "$daily_at" ]; then
    if [ -n "$randomized_delay" ] && [ "$randomized_delay" != "0" ]; then
      printf "$(t enabled_daily_with_delay)" "$daily_at" "$scope" "$randomized_delay"
    else
      printf "$(t enabled_daily)" "$daily_at" "$scope"
    fi
    return 0
  fi

  if [ -n "$every_hours" ]; then
    if [ -n "$randomized_delay" ] && [ "$randomized_delay" != "0" ]; then
      printf "$(t enabled_every_hours_with_delay)" "$every_hours" "$scope" "$randomized_delay"
    else
      printf "$(t enabled_every_hours)" "$every_hours" "$scope"
    fi
    return 0
  fi

  case "$fallback_schedule" in
    hourly)
      printf "$(t enabled_hourly)" "$scope"
      ;;
    weekly)
      printf "$(t enabled_weekly)" "$scope"
      ;;
    *)
      printf "$(t enabled_daily_fallback)" "$scope"
      ;;
  esac
}

untested_schedule_summary() {
  local enabled="$1"
  local every_minutes="$2"
  local randomized_delay="$3"
  local scope="$4"
  local invalid_label_zh="未测任务分钟间隔配置无效"
  local invalid_label_en="Invalid untested interval"

  if [ "$enabled" != "true" ]; then
    t not_enabled
    return 0
  fi

  local validated_minutes
  if ! validated_minutes="$(systemd_minutes_calendar_for "$every_minutes" 2>/dev/null)"; then
    if [ "${SUB2TEST_LANGUAGE:-zh}" = "en" ]; then
      printf "%s%s" "$invalid_label_en" "$scope"
    else
      printf "%s%s" "$invalid_label_zh" "$scope"
    fi
    return 0
  fi

  if [ -n "$randomized_delay" ] && [ "$randomized_delay" != "0" ]; then
    printf "$(t enabled_every_minutes_with_delay)" "$validated_minutes" "$scope" "$randomized_delay"
  else
    printf "$(t enabled_every_minutes)" "$validated_minutes" "$scope"
  fi
}

periodic_minutes_schedule_summary() {
  local enabled="$1"
  local every_minutes="$2"
  local randomized_delay="$3"
  local scope="$4"
  local invalid_label_zh="$5"
  local invalid_label_en="$6"

  if [ "$enabled" != "true" ]; then
    t not_enabled
    return 0
  fi

  local validated_minutes
  if ! validated_minutes="$(systemd_minutes_calendar_for "$every_minutes" 2>/dev/null)"; then
    if [ "${SUB2TEST_LANGUAGE:-zh}" = "en" ]; then
      printf "%s%s" "$invalid_label_en" "$scope"
    else
      printf "%s%s" "$invalid_label_zh" "$scope"
    fi
    return 0
  fi

  if [ -n "$randomized_delay" ] && [ "$randomized_delay" != "0" ]; then
    printf "$(t enabled_every_minutes_with_delay)" "$validated_minutes" "$scope" "$randomized_delay"
  else
    printf "$(t enabled_every_minutes)" "$validated_minutes" "$scope"
  fi
}

edit_value() {
  local key="$1"
  local current="$2"
  local label="${3:-$key}"
  read -r -p "$label [$current]: " input
  if [ -n "$input" ]; then
    save_config_value "$key" "$input"
    . "$SUB2TEST_CONFIG_FILE"
  fi
}

choose_full_schedule_mode() {
  echo
  echo "$(t schedule_mode_title)"
  echo "1) $(t schedule_mode_hourly)"
  echo "2) $(t schedule_mode_daily)"
  echo "3) $(t schedule_mode_weekly)"
  echo "4) $(t schedule_mode_every_hours)"
  echo "5) $(t schedule_mode_daily_at)"
  read -r -p "> " choice
  case "$choice" in
    1)
      save_config_value SUB2TEST_SCHEDULE hourly
      save_config_value SUB2TEST_DAILY_AT ""
      save_config_value SUB2TEST_EVERY_HOURS ""
      ;;
    2)
      save_config_value SUB2TEST_SCHEDULE daily
      save_config_value SUB2TEST_DAILY_AT ""
      save_config_value SUB2TEST_EVERY_HOURS ""
      ;;
    3)
      save_config_value SUB2TEST_SCHEDULE weekly
      save_config_value SUB2TEST_DAILY_AT ""
      save_config_value SUB2TEST_EVERY_HOURS ""
      ;;
    4)
      save_config_value SUB2TEST_SCHEDULE daily
      save_config_value SUB2TEST_DAILY_AT ""
      save_config_value SUB2TEST_EVERY_HOURS ""
      edit_value SUB2TEST_EVERY_HOURS "${SUB2TEST_EVERY_HOURS:-}" "$(t label_full_every_hours)"
      ;;
    5)
      save_config_value SUB2TEST_SCHEDULE daily
      save_config_value SUB2TEST_EVERY_HOURS ""
      edit_value SUB2TEST_DAILY_AT "${SUB2TEST_DAILY_AT:-}" "$(t label_full_daily_at)"
      ;;
    *)
      echo "$(t invalid_option)"
      ;;
  esac
  . "$SUB2TEST_CONFIG_FILE"
}

reload_timers_if_enabled() {
  preflight_runtime
  render_timer
  render_untested_timer
  systemctl daemon-reload
  if systemctl is-enabled sub2test.timer >/dev/null 2>&1; then
    systemctl restart sub2test.timer
  fi
  if systemctl is-enabled sub2test-untested.timer >/dev/null 2>&1; then
    systemctl restart sub2test-untested.timer
  fi
  . "$SUB2TEST_CONFIG_FILE"
}

show_task_summaries() {
  echo "$(t config_intro)"
  echo "- $(t full_task)：$(schedule_summary "${SUB2TEST_ENABLED:-false}" "${SUB2TEST_DAILY_AT:-}" "${SUB2TEST_EVERY_HOURS:-}" "${SUB2TEST_SCHEDULE:-daily}" "false" "${SUB2TEST_RANDOMIZED_DELAY_SECONDS:-120}" "$(t full_scope)")"
  echo "- $(t untested_task)：$(untested_schedule_summary "${SUB2TEST_UNTESTED_ENABLED:-false}" "${SUB2TEST_UNTESTED_EVERY_MINUTES:-30}" "${SUB2TEST_UNTESTED_RANDOMIZED_DELAY_SECONDS:-120}" "$(t untested_scope)")"
  echo "- $(t proxy_assign_task)：$(periodic_minutes_schedule_summary "${SUB2TEST_PROXY_ASSIGN_ENABLED:-false}" "${SUB2TEST_PROXY_ASSIGN_EVERY_MINUTES:-60}" "${SUB2TEST_PROXY_ASSIGN_RANDOMIZED_DELAY_SECONDS:-120}" "$(t proxy_assign_scope)" "代理分配任务分钟间隔配置无效" "Invalid proxy-assignment interval")"
  echo "- $(t duplicates_task)：$(periodic_minutes_schedule_summary "${SUB2TEST_DUPLICATES_ENABLED:-false}" "${SUB2TEST_DUPLICATES_EVERY_MINUTES:-60}" "${SUB2TEST_DUPLICATES_RANDOMIZED_DELAY_SECONDS:-120}" "$(t duplicates_scope)" "重复账号排查分钟间隔配置无效" "Invalid duplicate-account interval")"
  echo "$(t runtime_overview_title)"
  show_service_runtime_summary sub2test.service "$(t full_task)"
  show_service_runtime_summary sub2test-untested.service "$(t untested_task)"
  show_service_runtime_summary sub2test-proxy-assign.service "$(t proxy_assign_task)"
  show_service_runtime_summary sub2test-duplicates.service "$(t duplicates_task)"
}

edit_global_config() {
  . "$SUB2TEST_CONFIG_FILE"
  echo
  show_global_config
  echo
  echo "$(t edit_intro)"
  echo
  edit_value SUB2TEST_DEPLOY_MODE "${SUB2TEST_DEPLOY_MODE:-compose}" "$(t label_deploy_mode)"
  edit_value SUB2TEST_COMPOSE_FILE "${SUB2TEST_COMPOSE_FILE:-__COMPOSE_FILE__}" "$(t label_compose_file)"
  edit_value SUB2API_CONFIG_FILE "${SUB2API_CONFIG_FILE:-__APP_CONFIG_FILE__}" "$(t label_app_config_file)"
  edit_value SUB2TEST_DB_HOST "${SUB2TEST_DB_HOST:-}" "$(t label_db_host)"
  edit_value SUB2TEST_DB_PORT "${SUB2TEST_DB_PORT:-5432}" "$(t label_db_port)"
  edit_value SUB2TEST_DB_USER "${SUB2TEST_DB_USER:-}" "$(t label_db_user)"
  edit_value SUB2TEST_DB_PASSWORD "${SUB2TEST_DB_PASSWORD:-}" "$(t label_db_password)"
  edit_value SUB2TEST_DB_NAME "${SUB2TEST_DB_NAME:-}" "$(t label_db_name)"
  edit_value SUB2TEST_DB_SSLMODE "${SUB2TEST_DB_SSLMODE:-disable}" "$(t label_db_sslmode)"
  edit_value SUB2TEST_DB_CONTAINER "${SUB2TEST_DB_CONTAINER:-}" "$(t label_db_container)"
  edit_value SUB2TEST_API_BASE_URL "${SUB2TEST_API_BASE_URL:-http://127.0.0.1:8080/api/v1}" "$(t label_api_base_url)"
  edit_value SUB2TEST_ADMIN_API_KEY "${SUB2TEST_ADMIN_API_KEY:-}" "$(t label_admin_api_key)"
  edit_value SUB2TEST_UNAUTHORIZED_GROUP_OPENAI "${SUB2TEST_UNAUTHORIZED_GROUP_OPENAI:-}" "$(t label_unauthorized_group_openai)"
  edit_value SUB2TEST_UNAUTHORIZED_GROUP_ANTHROPIC "${SUB2TEST_UNAUTHORIZED_GROUP_ANTHROPIC:-}" "$(t label_unauthorized_group_anthropic)"
  edit_value SUB2TEST_UNAUTHORIZED_GROUP_GEMINI "${SUB2TEST_UNAUTHORIZED_GROUP_GEMINI:-}" "$(t label_unauthorized_group_gemini)"
  edit_value SUB2TEST_UNAUTHORIZED_GROUP_ANTIGRAVITY "${SUB2TEST_UNAUTHORIZED_GROUP_ANTIGRAVITY:-}" "$(t label_unauthorized_group_antigravity)"
  edit_value SUB2TEST_ERROR_STREAK_THRESHOLD "${SUB2TEST_ERROR_STREAK_THRESHOLD:-3}" "$(t label_error_threshold)"
  edit_value SUB2TEST_STATE_FILE "${SUB2TEST_STATE_FILE:-/opt/sub2test/state.json}" "$(t label_state_file)"
  edit_value SUB2TEST_LOCK_WAIT_SECONDS "${SUB2TEST_LOCK_WAIT_SECONDS:-3600}" "$(t label_lock_wait_seconds)"
  edit_value SUB2TEST_PROXY_ASSIGN_MODE "${SUB2TEST_PROXY_ASSIGN_MODE:-index}" "$(t label_proxy_assign_mode)"
  edit_value SUB2TEST_PROXY_ASSIGN_INDEX "${SUB2TEST_PROXY_ASSIGN_INDEX:-1}" "$(t label_proxy_assign_index)"
  edit_value SUB2TEST_DUPLICATES_SKIP_INACTIVE "${SUB2TEST_DUPLICATES_SKIP_INACTIVE:-true}" "$(t label_duplicates_skip_inactive)"
  edit_value SUB2TEST_CONCURRENCY "${SUB2TEST_CONCURRENCY:-3}" "$(t label_concurrency)"
  edit_value SUB2TEST_TIMEOUT_SECONDS "${SUB2TEST_TIMEOUT_SECONDS:-30}" "$(t label_timeout)"
  edit_value SUB2TEST_SLEEP_MIN_SECONDS "${SUB2TEST_SLEEP_MIN_SECONDS:-3}" "$(t label_sleep_min)"
  edit_value SUB2TEST_SLEEP_MAX_SECONDS "${SUB2TEST_SLEEP_MAX_SECONDS:-10}" "$(t label_sleep_max)"
  reload_timers_if_enabled
  echo
  show_global_config
}

edit_proxy_assign_task_config() {
  . "$SUB2TEST_CONFIG_FILE"
  echo
  show_proxy_assign_task_config
  echo
  echo "$(t edit_intro)"
  echo
  edit_value SUB2TEST_PROXY_ASSIGN_ENABLED "${SUB2TEST_PROXY_ASSIGN_ENABLED:-false}" "$(t label_proxy_assign_enabled)"
  edit_value SUB2TEST_PROXY_ASSIGN_EVERY_MINUTES "${SUB2TEST_PROXY_ASSIGN_EVERY_MINUTES:-60}" "$(t label_proxy_assign_every_minutes)"
  edit_value SUB2TEST_PROXY_ASSIGN_RANDOMIZED_DELAY_SECONDS "${SUB2TEST_PROXY_ASSIGN_RANDOMIZED_DELAY_SECONDS:-120}" "$(t label_proxy_assign_delay)"
  edit_value SUB2TEST_PROXY_ASSIGN_MODE "${SUB2TEST_PROXY_ASSIGN_MODE:-index}" "$(t label_proxy_assign_mode)"
  edit_value SUB2TEST_PROXY_ASSIGN_INDEX "${SUB2TEST_PROXY_ASSIGN_INDEX:-1}" "$(t label_proxy_assign_index)"
  reload_timers_if_enabled
  preflight_runtime
  render_duplicates_timer
  render_proxy_assign_timer
  systemctl daemon-reload
  echo
  show_proxy_assign_task_config
  echo "- $(t proxy_assign_task)：$(periodic_minutes_schedule_summary "${SUB2TEST_PROXY_ASSIGN_ENABLED:-false}" "${SUB2TEST_PROXY_ASSIGN_EVERY_MINUTES:-60}" "${SUB2TEST_PROXY_ASSIGN_RANDOMIZED_DELAY_SECONDS:-120}" "$(t proxy_assign_scope)" "代理分配任务分钟间隔配置无效" "Invalid proxy-assignment interval")"
}

edit_full_task_config() {
  . "$SUB2TEST_CONFIG_FILE"
  echo
  show_full_task_config
  echo
  echo "$(t edit_intro)"
  echo
  choose_full_schedule_mode
  edit_value SUB2TEST_RANDOMIZED_DELAY_SECONDS "${SUB2TEST_RANDOMIZED_DELAY_SECONDS:-120}" "$(t label_full_delay)"
  reload_timers_if_enabled
  echo
  show_full_task_config
  echo "- $(t full_task)：$(schedule_summary "${SUB2TEST_ENABLED:-false}" "${SUB2TEST_DAILY_AT:-}" "${SUB2TEST_EVERY_HOURS:-}" "${SUB2TEST_SCHEDULE:-daily}" "false" "${SUB2TEST_RANDOMIZED_DELAY_SECONDS:-120}" "$(t full_scope)")"
}

edit_untested_task_config() {
  . "$SUB2TEST_CONFIG_FILE"
  echo
  show_untested_task_config
  echo
  echo "$(t edit_intro)"
  echo
  edit_value SUB2TEST_UNTESTED_EVERY_MINUTES "${SUB2TEST_UNTESTED_EVERY_MINUTES:-30}" "$(t label_untested_every_minutes)"
  edit_value SUB2TEST_UNTESTED_RANDOMIZED_DELAY_SECONDS "${SUB2TEST_UNTESTED_RANDOMIZED_DELAY_SECONDS:-120}" "$(t label_untested_delay)"
  reload_timers_if_enabled
  echo
  show_untested_task_config
  echo "- $(t untested_task)：$(untested_schedule_summary "${SUB2TEST_UNTESTED_ENABLED:-false}" "${SUB2TEST_UNTESTED_EVERY_MINUTES:-30}" "${SUB2TEST_UNTESTED_RANDOMIZED_DELAY_SECONDS:-120}" "$(t untested_scope)")"
}

fetch_active_groups() {
  . "$SUB2TEST_CONFIG_FILE"
  local groups_failed_msg="$(t groups_list_failed)"
  local groups_empty_msg="$(t groups_list_empty)"
  local groups_title_msg="$(t groups_list_title)"
  export SUB2TEST_API_BASE_URL SUB2TEST_ADMIN_API_KEY SUB2TEST_TIMEOUT_SECONDS
  export SUB2TEST_GROUPS_FAILED_MSG="$groups_failed_msg" SUB2TEST_GROUPS_EMPTY_MSG="$groups_empty_msg" SUB2TEST_GROUPS_TITLE_MSG="$groups_title_msg"
  python3 - <<'PY_FETCH_ACTIVE_GROUPS'
import json
import os
import sys
import urllib.error
import urllib.request

api_base_url = (os.getenv('SUB2TEST_API_BASE_URL', '') or '').strip().rstrip('/')
admin_api_key = (os.getenv('SUB2TEST_ADMIN_API_KEY', '') or '').strip()
timeout_seconds = int((os.getenv('SUB2TEST_TIMEOUT_SECONDS', '30') or '30').strip())
groups_failed_msg = os.getenv('SUB2TEST_GROUPS_FAILED_MSG', 'Failed to fetch groups.')
groups_empty_msg = os.getenv('SUB2TEST_GROUPS_EMPTY_MSG', 'No active groups found.')
groups_title_msg = os.getenv('SUB2TEST_GROUPS_TITLE_MSG', 'Active groups:')

req = urllib.request.Request(
    f"{api_base_url}/admin/groups/all",
    headers={
        'x-api-key': admin_api_key,
        'Accept': 'application/json',
    },
    method='GET',
)

try:
    with urllib.request.urlopen(req, timeout=timeout_seconds) as response:
        body = response.read().decode('utf-8', errors='replace')
except urllib.error.HTTPError as err:
    detail = err.read().decode('utf-8', errors='replace').strip()
    print(f"{groups_failed_msg} HTTP {err.code} {detail}", file=sys.stderr)
    sys.exit(1)
except Exception as exc:
    print(f"{groups_failed_msg} {exc}", file=sys.stderr)
    sys.exit(1)

payload = json.loads(body) if body else {}
groups = payload.get('data') if isinstance(payload, dict) else payload
if not isinstance(groups, list):
    groups = []

active_groups = []
for item in groups:
    if not isinstance(item, dict):
        continue
    if str(item.get('status') or '').strip().lower() != 'active':
        continue
    active_groups.append(item)

if not active_groups:
    print(groups_empty_msg)
    sys.exit(0)

print(groups_title_msg)
for item in active_groups:
    print(f"- id={item.get('id')} name={item.get('name', '')} platform={item.get('platform', '')} status={item.get('status', '')}")
PY_FETCH_ACTIVE_GROUPS
}

edit_groups_task_config() {
  . "$SUB2TEST_CONFIG_FILE"
  echo
  show_groups_task_config
  echo
  echo "$(t edit_intro)"
  echo
  edit_value SUB2TEST_UNAUTHORIZED_GROUP_OPENAI "${SUB2TEST_UNAUTHORIZED_GROUP_OPENAI:-}" "$(t label_unauthorized_group_openai)"
  edit_value SUB2TEST_UNAUTHORIZED_GROUP_ANTHROPIC "${SUB2TEST_UNAUTHORIZED_GROUP_ANTHROPIC:-}" "$(t label_unauthorized_group_anthropic)"
  edit_value SUB2TEST_UNAUTHORIZED_GROUP_GEMINI "${SUB2TEST_UNAUTHORIZED_GROUP_GEMINI:-}" "$(t label_unauthorized_group_gemini)"
  edit_value SUB2TEST_UNAUTHORIZED_GROUP_ANTIGRAVITY "${SUB2TEST_UNAUTHORIZED_GROUP_ANTIGRAVITY:-}" "$(t label_unauthorized_group_antigravity)"
  echo
  show_groups_task_config
}

groups_task_menu() {
  while true; do
    . "$SUB2TEST_CONFIG_FILE"
    echo
    echo "$(t groups_menu_title)"
    echo
    echo "1) $(t groups_menu_list)"
    echo "2) $(t groups_menu_set_openai)"
    echo "3) $(t groups_menu_set_anthropic)"
    echo "4) $(t groups_menu_set_gemini)"
    echo "5) $(t groups_menu_set_antigravity)"
    echo "6) $(t groups_menu_edit_all)"
    echo "0) $(t menu_back)"
    read -r -p "> " choice
    case "$choice" in
      1) fetch_active_groups ;;
      2) edit_value SUB2TEST_UNAUTHORIZED_GROUP_OPENAI "${SUB2TEST_UNAUTHORIZED_GROUP_OPENAI:-}" "$(t label_unauthorized_group_openai)" ;;
      3) edit_value SUB2TEST_UNAUTHORIZED_GROUP_ANTHROPIC "${SUB2TEST_UNAUTHORIZED_GROUP_ANTHROPIC:-}" "$(t label_unauthorized_group_anthropic)" ;;
      4) edit_value SUB2TEST_UNAUTHORIZED_GROUP_GEMINI "${SUB2TEST_UNAUTHORIZED_GROUP_GEMINI:-}" "$(t label_unauthorized_group_gemini)" ;;
      5) edit_value SUB2TEST_UNAUTHORIZED_GROUP_ANTIGRAVITY "${SUB2TEST_UNAUTHORIZED_GROUP_ANTIGRAVITY:-}" "$(t label_unauthorized_group_antigravity)" ;;
      6) edit_groups_task_config ;;
      0) return 0 ;;
      *) echo "$(t invalid_option)" ;;
    esac
  done
}

duplicates_task_menu() {
  while true; do
    . "$SUB2TEST_CONFIG_FILE"
    echo
    echo "$(t duplicates_menu_title)"
    echo "- $(t duplicates_task)：$(periodic_minutes_schedule_summary "${SUB2TEST_DUPLICATES_ENABLED:-false}" "${SUB2TEST_DUPLICATES_EVERY_MINUTES:-60}" "${SUB2TEST_DUPLICATES_RANDOMIZED_DELAY_SECONDS:-120}" "$(t duplicates_scope)" "重复账号排查分钟间隔配置无效" "Invalid duplicate-account interval")"
    echo
    echo "1) $(t duplicates_menu_config)"
    echo "2) $(t duplicates_menu_enable)"
    echo "3) $(t duplicates_menu_disable)"
    echo "4) $(t duplicates_menu_show_log)"
    echo "0) $(t menu_back)"
    read -r -p "> " choice
    case "$choice" in
      1) edit_duplicates_task_config ;;
      2) enable_duplicates_task ;;
      3) disable_duplicates_task ;;
      4) show_last_duplicates_log ;;
      0) return 0 ;;
      *) echo "$(t invalid_option)" ;;
    esac
  done
}

edit_duplicates_task_config() {
  . "$SUB2TEST_CONFIG_FILE"
  echo
  show_duplicates_task_config
  echo
  echo "$(t edit_intro)"
  echo
  edit_value SUB2TEST_DUPLICATES_EVERY_MINUTES "${SUB2TEST_DUPLICATES_EVERY_MINUTES:-60}" "$(t label_duplicates_every_minutes)"
  edit_value SUB2TEST_DUPLICATES_RANDOMIZED_DELAY_SECONDS "${SUB2TEST_DUPLICATES_RANDOMIZED_DELAY_SECONDS:-120}" "$(t label_duplicates_delay)"
  edit_value SUB2TEST_DUPLICATES_SKIP_INACTIVE "${SUB2TEST_DUPLICATES_SKIP_INACTIVE:-true}" "$(t label_duplicates_skip_inactive)"
  reload_timers_if_enabled
  echo
  show_duplicates_task_config
  echo "- $(t duplicates_task)：$(untested_schedule_summary "${SUB2TEST_DUPLICATES_ENABLED:-false}" "${SUB2TEST_DUPLICATES_EVERY_MINUTES:-60}" "${SUB2TEST_DUPLICATES_RANDOMIZED_DELAY_SECONDS:-120}" "$(t duplicates_scope)")"
}

show_last_proxy_assign_log() {
  echo
  echo "$(t last_proxy_assign_log_title)"
  journalctl -u sub2test-proxy-assign.service -n 100 --no-pager || true
}

show_last_full_log() {
  echo
  echo "$(t last_full_log_title)"
  journalctl -u sub2test.service -n 100 --no-pager || true
}

show_last_untested_log() {
  echo
  echo "$(t last_untested_log_title)"
  journalctl -u sub2test-untested.service -n 100 --no-pager || true
}

show_last_duplicates_log() {
  echo
  echo "$(t last_duplicates_log_title)"
  journalctl -u sub2test-duplicates.service -n 100 --no-pager || true
}

switch_language() {
  echo
  echo "$(t language_menu_title)"
  echo "1) $(t language_option_zh)"
  echo "2) $(t language_option_en)"
  read -r -p "> " choice
  case "$choice" in
    1)
      save_config_value SUB2TEST_LANGUAGE zh
      . "$SUB2TEST_CONFIG_FILE"
      echo "$(t language_saved)"
      ;;
    2)
      save_config_value SUB2TEST_LANGUAGE en
      . "$SUB2TEST_CONFIG_FILE"
      echo "$(t language_saved)"
      ;;
    *)
      echo "$(t invalid_option)"
      ;;
  esac
}

service_active_state() {
  local service="$1"
  systemctl show "$service" --property=ActiveState --value 2>/dev/null || true
}

service_sub_state() {
  local service="$1"
  systemctl show "$service" --property=SubState --value 2>/dev/null || true
}

service_main_pid() {
  local service="$1"
  systemctl show "$service" --property=MainPID --value 2>/dev/null || true
}

service_main_command() {
  local service="$1"
  local main_pid
  main_pid="$(service_main_pid "$service")"
  [ -n "$main_pid" ] && [ "$main_pid" != "0" ] || return 1
  /usr/bin/ps -o command= -p "$main_pid" 2>/dev/null || true
}

service_is_running() {
  local service="$1"
  local active_state
  local sub_state
  local lock_path
  local main_command
  active_state="$(service_active_state "$service")"
  sub_state="$(service_sub_state "$service")"

  if [ "$active_state" = "active" ]; then
    return 0
  fi

  [ "$active_state" = "activating" ] && [ "$sub_state" = "start" ] || return 1
  lock_path="$(service_lock_path "$service" || true)"
  [ -n "$lock_path" ] || return 0
  /usr/sbin/fuser "$lock_path" >/dev/null 2>&1 || return 1
  main_command="$(service_main_command "$service")"
  printf '%s\n' "$main_command" | grep -q -- '/usr/local/bin/sub2test run-once\|/usr/local/bin/sub2test run-proxy-assign\|/usr/local/bin/sub2test run-duplicates\|/opt/sub2test/sub2test.sh run-once\|/opt/sub2test/sub2test.sh run-proxy-assign\|/opt/sub2test/sub2test.sh run-duplicates'
}

service_lock_path() {
  local service="$1"
  case "$service" in
    sub2test.service|sub2test-untested.service)
      printf '%s\n' "/opt/sub2test/run.lock"
      ;;
    sub2test-duplicates.service)
      printf '%s\n' "/opt/sub2test/duplicates.lock"
      ;;
    sub2test-proxy-assign.service)
      printf '%s\n' "/opt/sub2test/proxy-assign.lock"
      ;;
    *)
      return 1
      ;;
  esac
}

service_is_waiting() {
  local service="$1"
  local active_state
  local sub_state
  local lock_path
  local main_command
  active_state="$(service_active_state "$service")"
  sub_state="$(service_sub_state "$service")"
  [ "$active_state" = "activating" ] && [ "$sub_state" = "start" ] || return 1
  lock_path="$(service_lock_path "$service" || true)"
  [ -n "$lock_path" ] || return 1
  /usr/sbin/fuser "$lock_path" >/dev/null 2>&1 || return 1
  main_command="$(service_main_command "$service")"
  printf '%s\n' "$main_command" | grep -q -- '^/usr/bin/flock '
}

service_result() {
  local service="$1"
  systemctl show "$service" --property=Result --value 2>/dev/null || true
}

service_exec_main_status() {
  local service="$1"
  systemctl show "$service" --property=ExecMainStatus --value 2>/dev/null || true
}

service_runtime_status_label() {
  local service="$1"
  local active_state
  local result
  local exec_main_status
  active_state="$(service_active_state "$service")"

  if service_is_running "$service"; then
    t runtime_status_running
    return 0
  fi

  if service_is_waiting "$service"; then
    t runtime_status_waiting
    return 0
  fi

  case "$active_state" in
    activating)
      t runtime_status_starting
      ;;
    failed)
      result="$(service_result "$service")"
      exec_main_status="$(service_exec_main_status "$service")"
      if [ "$result" = "signal" ] && [ "$exec_main_status" = "15" ]; then
        t runtime_status_interrupted
      else
        t runtime_status_failed
      fi
      ;;
    inactive|deactivating|reloading|maintenance)
      t runtime_status_inactive
      ;;
    *)
      t runtime_status_unknown
      ;;
  esac
}

last_service_summary_entries() {
  local service="$1"
  journalctl -u "$service" -n 200 --no-pager -o short-iso 2>/dev/null | grep 'summary ' || true
}

last_service_summary_time() {
  local service="$1"
  local summary_line
  summary_line="$(last_service_main_summary_line "$service")"
  if [ -z "$summary_line" ]; then
    return 1
  fi
  printf '%s\n' "$summary_line" | cut -d' ' -f1-2
}

last_service_main_summary_line() {
  local service="$1"
  last_service_summary_entries "$service" | grep -E 'summary success=|proxy_assign_summary|duplicate_summary' | tail -n 1 || true
}

extract_summary_payload() {
  local raw_line="$1"
  python3 - "$raw_line" <<'PY_EXTRACT_SUMMARY'
import re
import sys

line = sys.argv[1]
match = re.search(r'(summary success=.*|proxy_assign_summary .*|duplicate_summary .*)', line)
if match:
    print(match.group(1))
PY_EXTRACT_SUMMARY
}

last_service_summary_text() {
  local service="$1"
  local raw_line
  local summary_line
  local timestamp
  local counts
  raw_line="$(last_service_main_summary_line "$service")"
  if [ -z "$raw_line" ]; then
    return 1
  fi

  timestamp="$(printf '%s\n' "$raw_line" | cut -d' ' -f1-2)"
  summary_line="$(extract_summary_payload "$raw_line")"
  [ -n "$summary_line" ] || return 1

  if printf '%s\n' "$summary_line" | grep -q '^summary success='; then
    counts="$(last_service_summary_entries "$service" | grep -F "$timestamp" | grep 'summary status_' | sed 's/^.*summary / /' | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
    if [ -n "$counts" ]; then
      printf '%s %s\n' "$summary_line" "$counts"
    else
      printf '%s\n' "$summary_line"
    fi
  else
    printf '%s\n' "$summary_line"
  fi
}

show_service_runtime_summary() {
  local service="$1"
  local label="$2"
  local status_text
  local last_run_text
  local last_result_text

  status_text="$(service_runtime_status_label "$service")"
  last_run_text="$(last_service_summary_time "$service" || true)"
  last_result_text="$(last_service_summary_text "$service" || true)"

  [ -n "$last_run_text" ] || last_run_text="$(t runtime_never_ran)"
  [ -n "$last_result_text" ] || last_result_text="$(t runtime_no_summary)"

  echo "- $label：$(t runtime_status_label)=$status_text | $(t runtime_last_run_label)=$last_run_text | $(t runtime_last_result_label)=$last_result_text"
}

print_automatic_task_conflicts() {
  local has_conflict=1
  if service_is_running sub2test.service; then
    echo "$(t manual_conflict_full_running)"
    has_conflict=0
  elif service_is_waiting sub2test.service; then
    echo "$(t manual_conflict_full_waiting)"
    has_conflict=0
  fi
  if service_is_running sub2test-untested.service; then
    echo "$(t manual_conflict_untested_running)"
    has_conflict=0
  elif service_is_waiting sub2test-untested.service; then
    echo "$(t manual_conflict_untested_waiting)"
    has_conflict=0
  fi
  if service_is_running sub2test-proxy-assign.service; then
    echo "$(t manual_conflict_proxy_assign_running)"
    has_conflict=0
  elif service_is_waiting sub2test-proxy-assign.service; then
    echo "$(t manual_conflict_proxy_assign_waiting)"
    has_conflict=0
  fi
  if service_is_running sub2test-duplicates.service; then
    echo "$(t manual_conflict_duplicates_running)"
    has_conflict=0
  elif service_is_waiting sub2test-duplicates.service; then
    echo "$(t manual_conflict_duplicates_waiting)"
    has_conflict=0
  fi
  return "$has_conflict"
}

automatic_tasks_conflicting() {
  if service_is_running sub2test.service || service_is_waiting sub2test.service; then
    return 0
  fi
  if service_is_running sub2test-untested.service || service_is_waiting sub2test-untested.service; then
    return 0
  fi
  if service_is_running sub2test-proxy-assign.service || service_is_waiting sub2test-proxy-assign.service; then
    return 0
  fi
  if service_is_running sub2test-duplicates.service || service_is_waiting sub2test-duplicates.service; then
    return 0
  fi
  return 1
}

confirm_yes() {
  local answer
  read -r -p "$1 " answer
  case "$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')" in
    y|yes) return 0 ;;
    *) return 1 ;;
  esac
}

stop_automatic_tasks_for_manual_run() {
  local attempt
  systemctl stop sub2test.service >/dev/null 2>&1 || true
  systemctl stop sub2test-untested.service >/dev/null 2>&1 || true
  systemctl stop sub2test-proxy-assign.service >/dev/null 2>&1 || true
  systemctl stop sub2test-duplicates.service >/dev/null 2>&1 || true
  for attempt in 1 2 3 4 5; do
    if ! automatic_tasks_conflicting; then
      return 0
    fi
    sleep 1
  done
  return 1
}

run_manual_once_with_lock() {
  local mode="$1"
  echo "$(t manual_lock_starting)"
  if ! /usr/bin/flock -w "${SUB2TEST_LOCK_WAIT_SECONDS:-3600}" /opt/sub2test/run.lock "$SCRIPT_PATH" run-once "$mode"; then
    echo "$(t manual_lock_failed)"
    return 1
  fi
}

run_manual_once() {
  local mode="$1"
  if ! automatic_tasks_conflicting; then
    run_manual_once_with_lock "$mode"
    return 0
  fi

  echo
  print_automatic_task_conflicts || true
  if ! confirm_yes "$(t manual_conflict_prompt)"; then
    echo "$(t manual_conflict_cancelled)"
    return 0
  fi

  echo "$(t manual_conflict_stopping)"
  if ! stop_automatic_tasks_for_manual_run; then
    echo "$(t manual_conflict_stop_failed)"
    return 1
  fi

  echo "$(t manual_conflict_stopped)"
  run_manual_once_with_lock "$mode"
}

enable_task() {
  save_config_value SUB2TEST_ENABLED true
  . "$SUB2TEST_CONFIG_FILE"
  preflight_runtime
  render_timer
  render_untested_timer
  systemctl daemon-reload
  systemctl enable --now sub2test.timer
  if [ "${SUB2TEST_UNTESTED_ENABLED:-false}" = "true" ]; then
    systemctl enable --now sub2test-untested.timer
  else
    systemctl disable --now sub2test-untested.timer >/dev/null 2>&1 || true
  fi
  echo "sub2test timer enabled"
}

enable_untested_task() {
  save_config_value SUB2TEST_UNTESTED_ENABLED true
  . "$SUB2TEST_CONFIG_FILE"
  preflight_runtime
  render_untested_timer
  systemctl daemon-reload
  systemctl enable --now sub2test-untested.timer
  echo "sub2test untested timer enabled"
}

enable_duplicates_task() {
  save_config_value SUB2TEST_DUPLICATES_ENABLED true
  . "$SUB2TEST_CONFIG_FILE"
  preflight_runtime
  render_duplicates_timer
  systemctl daemon-reload
  systemctl enable --now sub2test-duplicates.timer
  echo "sub2test duplicates timer enabled"
}

enable_proxy_assign_task() {
  save_config_value SUB2TEST_PROXY_ASSIGN_ENABLED true
  . "$SUB2TEST_CONFIG_FILE"
  preflight_runtime
  render_proxy_assign_timer
  systemctl daemon-reload
  systemctl enable --now sub2test-proxy-assign.timer
  echo "sub2test proxy-assign timer enabled"
}

disable_proxy_assign_task() {
  save_config_value SUB2TEST_PROXY_ASSIGN_ENABLED false
  . "$SUB2TEST_CONFIG_FILE"
  systemctl disable --now sub2test-proxy-assign.timer || true
  echo "sub2test proxy-assign timer disabled"
}

disable_task() {
  save_config_value SUB2TEST_ENABLED false
  . "$SUB2TEST_CONFIG_FILE"
  systemctl disable --now sub2test.timer || true
  echo "sub2test timer disabled"
}

disable_untested_task() {
  save_config_value SUB2TEST_UNTESTED_ENABLED false
  . "$SUB2TEST_CONFIG_FILE"
  systemctl disable --now sub2test-untested.timer || true
  echo "sub2test untested timer disabled"
}

disable_duplicates_task() {
  save_config_value SUB2TEST_DUPLICATES_ENABLED false
  . "$SUB2TEST_CONFIG_FILE"
  systemctl disable --now sub2test-duplicates.timer || true
  echo "sub2test duplicates timer disabled"
}

edit_config() {
  edit_global_config
}

proxy_assign_task_menu() {
  while true; do
    . "$SUB2TEST_CONFIG_FILE"
    echo
    echo "$(t proxy_assign_menu_title)"
    echo "- $(t proxy_assign_task)：$(periodic_minutes_schedule_summary "${SUB2TEST_PROXY_ASSIGN_ENABLED:-false}" "${SUB2TEST_PROXY_ASSIGN_EVERY_MINUTES:-60}" "${SUB2TEST_PROXY_ASSIGN_RANDOMIZED_DELAY_SECONDS:-120}" "$(t proxy_assign_scope)" "代理分配任务分钟间隔配置无效" "Invalid proxy-assignment interval")"
    echo
    echo "1) $(t proxy_assign_menu_config)"
    echo "2) $(t proxy_assign_menu_enable)"
    echo "3) $(t proxy_assign_menu_disable)"
    echo "4) $(t proxy_assign_menu_run)"
    echo "5) $(t proxy_assign_menu_show_log)"
    echo "0) $(t menu_back)"
    read -r -p "> " choice
    case "$choice" in
      1) edit_proxy_assign_task_config ;;
      2) enable_proxy_assign_task ;;
      3) disable_proxy_assign_task ;;
      4) run_proxy_assign_once ;;
      5) show_last_proxy_assign_log ;;
      0) return 0 ;;
      *) echo "$(t invalid_option)" ;;
    esac
  done
}

full_task_menu() {
  while true; do
    . "$SUB2TEST_CONFIG_FILE"
    echo
    echo "$(t full_menu_title)"
    echo "- $(t full_task)：$(schedule_summary "${SUB2TEST_ENABLED:-false}" "${SUB2TEST_DAILY_AT:-}" "${SUB2TEST_EVERY_HOURS:-}" "${SUB2TEST_SCHEDULE:-daily}" "false" "${SUB2TEST_RANDOMIZED_DELAY_SECONDS:-120}" "$(t full_scope)")"
    echo
    echo "1) $(t full_menu_config)"
    echo "2) $(t full_menu_enable)"
    echo "3) $(t full_menu_disable)"
    echo "4) $(t full_menu_show_log)"
    echo "0) $(t menu_back)"
    read -r -p "> " choice
    case "$choice" in
      1) edit_full_task_config ;;
      2) enable_task ;;
      3) disable_task ;;
      4) show_last_full_log ;;
      0) return 0 ;;
      *) echo "$(t invalid_option)" ;;
    esac
  done
}

untested_task_menu() {
  while true; do
    . "$SUB2TEST_CONFIG_FILE"
    echo
    echo "$(t untested_menu_title)"
    echo "- $(t untested_task)：$(untested_schedule_summary "${SUB2TEST_UNTESTED_ENABLED:-false}" "${SUB2TEST_UNTESTED_EVERY_MINUTES:-30}" "${SUB2TEST_UNTESTED_RANDOMIZED_DELAY_SECONDS:-120}" "$(t untested_scope)")"
    echo
    echo "1) $(t untested_menu_config)"
    echo "2) $(t untested_menu_enable)"
    echo "3) $(t untested_menu_disable)"
    echo "4) $(t untested_menu_show_log)"
    echo "0) $(t menu_back)"
    read -r -p "> " choice
    case "$choice" in
      1) edit_untested_task_config ;;
      2) enable_untested_task ;;
      3) disable_untested_task ;;
      4) show_last_untested_log ;;
      0) return 0 ;;
      *) echo "$(t invalid_option)" ;;
    esac
  done
}

manual_run_menu() {
  while true; do
    . "$SUB2TEST_CONFIG_FILE"
    echo
    echo "$(t manual_menu_title)"
    echo
    echo "1) $(t menu_run_all)"
    echo "2) $(t menu_run_error)"
    echo "3) $(t menu_run_disabled)"
    echo "4) $(t menu_run_untested)"
    echo "0) $(t menu_back)"
    read -r -p "> " choice
    case "$choice" in
      1) run_manual_once all ;;
      2) run_manual_once error ;;
      3) run_manual_once disabled ;;
      4) run_manual_once untested ;;
      0) return 0 ;;
      *) echo "$(t invalid_option)" ;;
    esac
  done
}

uninstall_self() {
  systemctl disable --now sub2test.timer || true
  systemctl disable --now sub2test-untested.timer || true
  systemctl disable --now sub2test-duplicates.timer || true
  systemctl disable --now sub2test-proxy-assign.timer || true
  rm -f /etc/systemd/system/sub2test.service /etc/systemd/system/sub2test.timer /etc/systemd/system/sub2test-untested.service /etc/systemd/system/sub2test-untested.timer /etc/systemd/system/sub2test-duplicates.service /etc/systemd/system/sub2test-duplicates.timer /etc/systemd/system/sub2test-proxy-assign.service /etc/systemd/system/sub2test-proxy-assign.timer "__LINK_FILE__"
  rm -rf "__INSTALL_ROOT__"
  echo "sub2test removed"
}

run_once() {
  . "$SUB2TEST_CONFIG_FILE"
  local mode="${1:-all}"
  case "$mode" in
    all|error|disabled|untested) ;;
    *)
      echo "Usage: sub2test run-once [all|error|disabled|untested]" >&2
      return 1
      ;;
  esac
  export SUB2TEST_DEPLOY_MODE SUB2TEST_COMPOSE_FILE SUB2API_CONFIG_FILE
  export SUB2TEST_DB_HOST SUB2TEST_DB_PORT SUB2TEST_DB_USER SUB2TEST_DB_PASSWORD SUB2TEST_DB_NAME SUB2TEST_DB_SSLMODE SUB2TEST_DB_CONTAINER
  export SUB2TEST_API_BASE_URL SUB2TEST_ADMIN_API_KEY SUB2TEST_ERROR_STREAK_THRESHOLD SUB2TEST_STATE_FILE
  export SUB2TEST_UNAUTHORIZED_GROUP_OPENAI SUB2TEST_UNAUTHORIZED_GROUP_ANTHROPIC SUB2TEST_UNAUTHORIZED_GROUP_GEMINI SUB2TEST_UNAUTHORIZED_GROUP_ANTIGRAVITY
  export SUB2TEST_CONCURRENCY SUB2TEST_TIMEOUT_SECONDS
  export SUB2TEST_SLEEP_MIN_SECONDS SUB2TEST_SLEEP_MAX_SECONDS
  run_health_check "$mode"
}

run_proxy_assign() {
  preflight_runtime
  local rows_json=""
  local rows_tsv=""
  rows_json="$(mktemp)"
  cleanup_run_proxy_assign() {
    rm -f -- "${rows_json:-}" "${rows_tsv:-}"
  }
  trap cleanup_run_proxy_assign RETURN

  if [ -n "${SUB2TEST_DB_CONTAINER:-}" ]; then
    rows_tsv="$(mktemp)"
    docker exec \
      -e PGPASSWORD="$SUB2TEST_DB_PASSWORD" \
      "$SUB2TEST_DB_CONTAINER" \
      psql -U "$SUB2TEST_DB_USER" -d "$SUB2TEST_DB_NAME" -F $'\t' -Atqc "SELECT id, proxy_id FROM accounts WHERE deleted_at IS NULL AND proxy_id IS NULL ORDER BY id ASC" > "$rows_tsv"
    python3 - "$rows_tsv" "$rows_json" <<'PY_EXPORT_CONTAINER_PROXY_ASSIGN'
import json
import sys

input_path = sys.argv[1]
output_path = sys.argv[2]
accounts = []

with open(input_path, 'r', encoding='utf-8') as src:
    for raw_line in src:
        line = raw_line.rstrip(chr(10))
        if not line:
            continue
        parts = line.split(chr(9), 1)
        if len(parts) != 2:
            continue
        account_id, proxy_id = parts
        accounts.append({'id': int(account_id), 'proxy_id': None if proxy_id in ('', chr(92) + 'N') else int(proxy_id)})

with open(output_path, 'w', encoding='utf-8') as out:
    out.write(json.dumps({'accounts': accounts}, ensure_ascii=False))
PY_EXPORT_CONTAINER_PROXY_ASSIGN
  else
    python3 - "$rows_json" <<'PY_EXPORT_PROXY_ASSIGN'
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
    SELECT id, proxy_id
    FROM accounts
    WHERE deleted_at IS NULL
      AND proxy_id IS NULL
    ORDER BY id ASC
    """
)
accounts = [{'id': account_id, 'proxy_id': proxy_id} for account_id, proxy_id in cur.fetchall()]
cur.close()
conn.close()

with open(output_path, 'w', encoding='utf-8') as fh:
    fh.write(json.dumps({'accounts': accounts}, ensure_ascii=False))
PY_EXPORT_PROXY_ASSIGN
  fi

  python3 - "$rows_json" <<'PY_RUN_PROXY_ASSIGN'
import json
import os
import random
import sys
import urllib.error
import urllib.request

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass

rows_path = sys.argv[1]
api_base_url = (os.getenv('SUB2TEST_API_BASE_URL', '') or '').strip().rstrip('/')
admin_api_key = (os.getenv('SUB2TEST_ADMIN_API_KEY', '') or '').strip()
timeout_seconds = int((os.getenv('SUB2TEST_TIMEOUT_SECONDS', '30') or '30').strip())
mode = (os.getenv('SUB2TEST_PROXY_ASSIGN_MODE', 'index') or 'index').strip().lower()
index_raw = (os.getenv('SUB2TEST_PROXY_ASSIGN_INDEX', '1') or '1').strip()
db_container = (os.getenv('SUB2TEST_DB_CONTAINER', '') or '').strip()

with open(rows_path, 'r', encoding='utf-8') as fh:
    payload = json.load(fh)

accounts = payload.get('accounts') or []
headers = {
    'x-api-key': admin_api_key,
    'Content-Type': 'application/json',
    'Accept': 'application/json',
}

if mode not in ('index', 'random'):
    print(f'proxy_assign_summary candidates={len(accounts)} assigned=0 skipped_existing=0 failed=0 reason=invalid_mode mode={mode}')
    sys.exit(1)

try:
    proxy_index = int(index_raw)
except Exception:
    print(f'proxy_assign_summary candidates={len(accounts)} assigned=0 skipped_existing=0 failed=0 reason=invalid_index index={index_raw}')
    sys.exit(1)
if proxy_index < 1:
    print(f'proxy_assign_summary candidates={len(accounts)} assigned=0 skipped_existing=0 failed=0 reason=invalid_index index={proxy_index}')
    sys.exit(1)


def shorten_detail(detail: str) -> str:
    detail = '' if detail is None else str(detail)
    detail = detail.encode('utf-8', errors='replace').decode('utf-8', errors='replace')
    detail = detail.replace(chr(10), ' ')
    detail = ' '.join(detail.split())
    return detail[:180]


def response_error_detail(status_code, body_bytes):
    try:
        body = body_bytes.decode('utf-8', errors='replace').strip() if body_bytes else ''
    except Exception:
        body = ''
    if body:
        return shorten_detail(body)
    return shorten_detail(f'HTTP {status_code}')


def safe_exception_text(exc: Exception) -> str:
    try:
        text = str(exc)
    except Exception:
        text = repr(exc)
    if not text:
        text = exc.__class__.__name__
    return shorten_detail(text)


def update_account_fields(account_id: int, update_payload: dict):
    body = json.dumps(update_payload, ensure_ascii=False).encode('utf-8')
    for method in ('PATCH', 'PUT'):
        req = urllib.request.Request(
            f'{api_base_url}/admin/accounts/{account_id}',
            data=body,
            headers=headers,
            method=method,
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout_seconds) as response:
                return True, getattr(response, 'status', None) or response.getcode(), ''
        except urllib.error.HTTPError as err:
            if method == 'PATCH' and err.code in (404, 405):
                continue
            return False, err.code, response_error_detail(err.code, err.read())
        except Exception as exc:
            return False, None, safe_exception_text(exc)
    return False, None, 'update request failed'


def load_active_proxy_ids() -> list[int]:
    if db_container:
        import subprocess
        command = [
            'docker', 'exec', '-e', f'PGPASSWORD={os.getenv("SUB2TEST_DB_PASSWORD", "")}', db_container,
            'psql', '-U', os.environ['SUB2TEST_DB_USER'], '-d', os.environ['SUB2TEST_DB_NAME'], '-F', '\t', '-Atqc',
            "SELECT id FROM proxies WHERE deleted_at IS NULL AND status = 'active' ORDER BY id ASC",
        ]
        result = subprocess.run(command, capture_output=True, text=True, encoding='utf-8')
        if result.returncode != 0:
            print(f'proxy_assign_summary candidates={len(accounts)} assigned=0 skipped_existing=0 failed=0 reason=load_proxy_failed detail={shorten_detail(result.stderr)}')
            sys.exit(1)
        return [int(line.strip()) for line in result.stdout.splitlines() if line.strip()]

    import psycopg2
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
        SELECT id
        FROM proxies
        WHERE deleted_at IS NULL
          AND status = 'active'
        ORDER BY id ASC
        """
    )
    proxy_ids = [proxy_id for (proxy_id,) in cur.fetchall()]
    cur.close()
    conn.close()
    return proxy_ids


def select_proxy_id(active_proxy_ids: list[int]) -> int | None:
    if not active_proxy_ids:
        return None
    if mode == 'random':
        return random.choice(active_proxy_ids)
    if proxy_index > len(active_proxy_ids):
        return None
    return active_proxy_ids[proxy_index - 1]


active_proxy_ids = load_active_proxy_ids()
selected_proxy_id = select_proxy_id(active_proxy_ids)

if not active_proxy_ids:
    print(f'proxy_assign_summary candidates={len(accounts)} assigned=0 skipped_existing=0 failed=0 reason=no_available_proxy mode={mode}')
    sys.exit(0)
if selected_proxy_id is None:
    print(f'proxy_assign_summary candidates={len(accounts)} assigned=0 skipped_existing=0 failed=0 reason=proxy_index_out_of_range mode={mode} index={proxy_index} available={len(active_proxy_ids)}')
    sys.exit(0)

assigned = 0
failed = 0
skipped_existing = 0

for account in accounts:
    account_id = int(account.get('id'))
    current_proxy_id = account.get('proxy_id')
    if current_proxy_id not in (None, ''):
        skipped_existing += 1
        print(f'proxy_assign_skip account={account_id} reason=has_proxy proxy={current_proxy_id}')
        continue

    ok, status_code, detail = update_account_fields(account_id, {'proxy_id': int(selected_proxy_id)})
    if ok:
        assigned += 1
        print(f'proxy_assign account={account_id} proxy={selected_proxy_id} mode={mode}')
    else:
        failed += 1
        detail_part = f' detail={detail}' if detail else ''
        status_part = f' status={status_code}' if status_code is not None else ''
        print(f'proxy_assign_failed account={account_id} proxy={selected_proxy_id} mode={mode}{status_part}{detail_part}')

print(f'proxy_assign_summary candidates={len(accounts)} assigned={assigned} skipped_existing={skipped_existing} failed={failed} mode={mode} selected_proxy={selected_proxy_id} available={len(active_proxy_ids)}')
PY_RUN_PROXY_ASSIGN
}

run_proxy_assign_once() {
  echo "$(t manual_lock_starting)"
  if ! /usr/bin/flock -w "${SUB2TEST_LOCK_WAIT_SECONDS:-3600}" /opt/sub2test/proxy-assign.lock "$SCRIPT_PATH" run-proxy-assign-now; then
    echo "$(t manual_lock_failed)"
    return 1
  fi
}

run_proxy_assign_now() {
  . "$SUB2TEST_CONFIG_FILE"
  export SUB2TEST_DEPLOY_MODE SUB2TEST_COMPOSE_FILE SUB2API_CONFIG_FILE
  export SUB2TEST_DB_HOST SUB2TEST_DB_PORT SUB2TEST_DB_USER SUB2TEST_DB_PASSWORD SUB2TEST_DB_NAME SUB2TEST_DB_SSLMODE SUB2TEST_DB_CONTAINER
  export SUB2TEST_API_BASE_URL SUB2TEST_ADMIN_API_KEY SUB2TEST_TIMEOUT_SECONDS
  export SUB2TEST_PROXY_ASSIGN_MODE SUB2TEST_PROXY_ASSIGN_INDEX
  run_proxy_assign
}

run_duplicates_once() {
  . "$SUB2TEST_CONFIG_FILE"
  export SUB2TEST_DEPLOY_MODE SUB2TEST_COMPOSE_FILE SUB2API_CONFIG_FILE
  export SUB2TEST_DB_HOST SUB2TEST_DB_PORT SUB2TEST_DB_USER SUB2TEST_DB_PASSWORD SUB2TEST_DB_NAME SUB2TEST_DB_SSLMODE SUB2TEST_DB_CONTAINER
  export SUB2TEST_API_BASE_URL SUB2TEST_ADMIN_API_KEY SUB2TEST_TIMEOUT_SECONDS SUB2TEST_DUPLICATES_SKIP_INACTIVE
  run_duplicate_check
}

menu() {
  while true; do
    . "$SUB2TEST_CONFIG_FILE"
    echo
    echo "$(t menu_title)"
    echo "Version: $SUB2TEST_VERSION"
    echo "Project: $SUB2TEST_PROJECT_URL"
    show_task_summaries
    echo
    echo "1) $(t menu_edit)"
    echo "2) $(t menu_full_task)"
    echo "3) $(t menu_untested_task)"
    echo "4) $(t menu_duplicates_task)"
    echo "5) $(t menu_proxy_assign_task)"
    echo "6) $(t menu_groups_task)"
    echo "7) $(t menu_manual_run)"
    echo "8) $(t menu_show_config)"
    echo "9) $(t menu_switch_language)"
    echo "10) $(t menu_uninstall)"
    echo "0) $(t menu_exit)"
    read -r -p "> " choice
    case "$choice" in
      1) edit_config ;;
      2) full_task_menu ;;
      3) untested_task_menu ;;
      4) duplicates_task_menu ;;
      5) proxy_assign_task_menu ;;
      6) groups_task_menu ;;
      7) manual_run_menu ;;
      8) show_config ;;
      9) switch_language ;;
      10) uninstall_self; exit 0 ;;
      0) exit 0 ;;
      *) echo "$(t invalid_option)" ;;
    esac
  done
}

case "${1:-menu}" in
  run-once) run_once "${2:-all}" ;;
  run-duplicates) run_duplicates_once ;;
  run-proxy-assign) run_proxy_assign_now ;;
  run-proxy-assign-now) run_proxy_assign_now ;;
  show-config) show_config ;;
  preflight) preflight_runtime ;;
  enable) enable_task ;;
  disable) disable_task ;;
  enable-untested) enable_untested_task ;;
  disable-untested) disable_untested_task ;;
  enable-duplicates) enable_duplicates_task ;;
  disable-duplicates) disable_duplicates_task ;;
  enable-proxy-assign) enable_proxy_assign_task ;;
  disable-proxy-assign) disable_proxy_assign_task ;;
  menu) menu ;;
  *) echo "Usage: sub2test [menu|run-once [all|error|disabled|untested]|run-duplicates|run-proxy-assign|show-config|preflight|enable|disable|enable-untested|disable-untested|enable-duplicates|disable-duplicates|enable-proxy-assign|disable-proxy-assign]" >&2; exit 1 ;;
esac
'''
content = content.replace('__CONFIG_FILE__', config_file)
content = content.replace('__COMPOSE_FILE__', compose_file)
content = content.replace('__APP_CONFIG_FILE__', app_config_file)
content = content.replace('__LINK_FILE__', link_file)
content = content.replace('__INSTALL_ROOT__', install_root)
content = content.replace('__SCRIPT_VERSION__', script_version)
content = content.replace('__PROJECT_URL__', project_url)
bin_path.write_text(content, encoding='utf-8')
PY
chmod +x "$BIN_FILE"

cat > "$SYSTEMD_SERVICE" <<EOF
[Unit]
Description=Sub2API external sub2test runner
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/flock -w ${SUB2TEST_LOCK_WAIT_SECONDS:-3600} /opt/sub2test/run.lock $LINK_FILE run-once
EOF

cat > /etc/systemd/system/sub2test-untested.service <<EOF
[Unit]
Description=Sub2API external sub2test untested runner
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/flock -w ${SUB2TEST_LOCK_WAIT_SECONDS:-3600} /opt/sub2test/run.lock $LINK_FILE run-once untested
EOF

cat > /etc/systemd/system/sub2test-duplicates.service <<EOF
[Unit]
Description=Sub2API external sub2test duplicate-account runner
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/flock -w ${SUB2TEST_LOCK_WAIT_SECONDS:-3600} /opt/sub2test/duplicates.lock $LINK_FILE run-duplicates
EOF

cat > /etc/systemd/system/sub2test-proxy-assign.service <<EOF
[Unit]
Description=Sub2API external sub2test proxy-assignment runner
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/flock -w ${SUB2TEST_LOCK_WAIT_SECONDS:-3600} /opt/sub2test/proxy-assign.lock $LINK_FILE run-proxy-assign-now
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

cat > /etc/systemd/system/sub2test-untested.timer <<'EOF'
[Unit]
Description=Run sub2test for untested active accounts periodically

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=120
Unit=sub2test-untested.service

[Install]
WantedBy=timers.target
EOF

cat > /etc/systemd/system/sub2test-duplicates.timer <<'EOF'
[Unit]
Description=Run sub2test duplicate-account check periodically

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=120
Unit=sub2test-duplicates.service

[Install]
WantedBy=timers.target
EOF

cat > /etc/systemd/system/sub2test-proxy-assign.timer <<'EOF'
[Unit]
Description=Run sub2test proxy assignment periodically

[Timer]
OnBootSec=2min
OnUnitActiveSec=60min
AccuracySec=1s
Persistent=true
RandomizedDelaySec=120
Unit=sub2test-proxy-assign.service

[Install]
WantedBy=timers.target
EOF

ln -sf "$BIN_FILE" "$LINK_FILE"
systemctl daemon-reload
/usr/local/bin/sub2test show-config >/dev/null 2>&1 || true
/usr/local/bin/sub2test preflight >/dev/null 2>&1 || true
/usr/local/bin/sub2test enable >/dev/null 2>&1 || true
if grep -q '^SUB2TEST_UNTESTED_ENABLED=true$' "$CONFIG_FILE"; then
  /usr/local/bin/sub2test enable-untested >/dev/null 2>&1 || true
fi
if grep -q '^SUB2TEST_DUPLICATES_ENABLED=true$' "$CONFIG_FILE"; then
  /usr/local/bin/sub2test enable-duplicates >/dev/null 2>&1 || true
fi
if grep -q '^SUB2TEST_PROXY_ASSIGN_ENABLED=true$' "$CONFIG_FILE"; then
  /usr/local/bin/sub2test enable-proxy-assign >/dev/null 2>&1 || true
fi

echo "sub2test installed"
echo "Config: $CONFIG_FILE"
echo "Command: $LINK_FILE"
echo "Sub2API root: $DEFAULT_SUB2API_ROOT"
echo "Compose file: $DEFAULT_COMPOSE_FILE"
echo "App config: $DEFAULT_APP_CONFIG_FILE"
echo "Enable timer: systemctl enable --now sub2test.timer"
