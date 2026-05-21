# sub2test-installer

Current release: `0.1.4`

- [中文](#中文)
- [English](#english)
- [Release notes](#release-notes)

---

## 中文

`sub2test-installer.sh` 当前发布版本为 `0.1.4`。

`sub2test-installer.sh` 用来给 Sub2API 部署一套独立的 `sub2test` 运行环境：自动发现数据库配置、调用管理端账号测活接口、把连续 `error` 的账号在达到阈值后自动设为 `disabled`，并可通过 systemd timer 定时执行。

### 30 秒快速开始

```bash
curl -fsSL https://raw.githubusercontent.com/SYFATP/sub2test-installer/master/sub2test-installer.sh -o /tmp/sub2test-installer.sh
chmod +x /tmp/sub2test-installer.sh
sudo bash /tmp/sub2test-installer.sh --force
sudo sub2test show-config
```

安装后会生成：

- 配置文件：`/etc/sub2api/sub2test.env`
- 状态文件：`/opt/sub2test/state.json`
- 命令入口：`/usr/local/bin/sub2test`
- timer：`/etc/systemd/system/sub2test.timer`

### 常用调度示例

#### 每天 00:00 执行

```bash
sudo sed -i 's/^SUB2TEST_DAILY_AT=.*/SUB2TEST_DAILY_AT=00:00/' /etc/sub2api/sub2test.env
sudo sed -i 's/^SUB2TEST_EVERY_HOURS=.*/SUB2TEST_EVERY_HOURS=/' /etc/sub2api/sub2test.env
sudo sed -i 's/^SUB2TEST_RANDOMIZED_DELAY_SECONDS=.*/SUB2TEST_RANDOMIZED_DELAY_SECONDS=0/' /etc/sub2api/sub2test.env
sudo sub2test enable
```

#### 每 6 小时执行一次

```bash
sudo sed -i 's/^SUB2TEST_DAILY_AT=.*/SUB2TEST_DAILY_AT=/' /etc/sub2api/sub2test.env
sudo sed -i 's/^SUB2TEST_EVERY_HOURS=.*/SUB2TEST_EVERY_HOURS=6/' /etc/sub2api/sub2test.env
sudo sed -i 's/^SUB2TEST_RANDOMIZED_DELAY_SECONDS=.*/SUB2TEST_RANDOMIZED_DELAY_SECONDS=0/' /etc/sub2api/sub2test.env
sudo sub2test enable
```

### 常用命令

```bash
sudo sub2test show-config
sudo sub2test run-once
sudo sub2test enable
sudo sub2test disable
sudo sub2test menu
```

### 功能概览

- 自动从 `docker-compose.yml` 或 `config.yaml` 推断数据库连接信息
- 调用管理端 `/admin/accounts/{id}/test` 做账号测活
- 本地持久化连续 `error` 次数到状态文件
- 达到阈值后调用管理端 `/admin/accounts/{id}` 把账号置为 `disabled`
- 支持固定每天某个时间执行
- 支持每隔 N 小时执行一次
- 保留旧的 `hourly / daily / weekly` 调度兼容方式

### 完整配置说明

配置文件路径：`/etc/sub2api/sub2test.env`

#### API 与状态

```env
SUB2TEST_API_BASE_URL=http://127.0.0.1:38080/api/v1
SUB2TEST_ADMIN_API_KEY=your-admin-api-key
SUB2TEST_ERROR_STREAK_THRESHOLD=3
SUB2TEST_STATE_FILE=/opt/sub2test/state.json
```

说明：

- `SUB2TEST_ERROR_STREAK_THRESHOLD`：连续多少次 `native_status=error` 后停用账号
- `SUB2TEST_STATE_FILE`：本地持久化文件路径，默认 `/opt/sub2test/state.json`

#### 调度配置

##### 方案 1：每天固定时间执行

```env
SUB2TEST_DAILY_AT=00:00
SUB2TEST_EVERY_HOURS=
SUB2TEST_RANDOMIZED_DELAY_SECONDS=0
```

说明：

- `SUB2TEST_DAILY_AT` 格式必须是 `HH:MM`
- 设置后优先级最高
- `SUB2TEST_RANDOMIZED_DELAY_SECONDS=0` 表示不做随机延迟，尽量准点执行

##### 方案 2：每隔几小时执行一次

```env
SUB2TEST_DAILY_AT=
SUB2TEST_EVERY_HOURS=6
SUB2TEST_RANDOMIZED_DELAY_SECONDS=0
```

说明：

- `SUB2TEST_EVERY_HOURS` 取值范围 `1-23`
- 例如 `6` 表示每 6 小时执行一次

##### 方案 3：兼容旧调度方式

```env
SUB2TEST_SCHEDULE=daily
```

可选值：

- `hourly`
- `daily`
- `weekly`

优先级：

1. `SUB2TEST_DAILY_AT`
2. `SUB2TEST_EVERY_HOURS`
3. `SUB2TEST_SCHEDULE`

### 查看和排障

#### 查看 timer 状态

```bash
systemctl status sub2test.timer --no-pager
systemctl list-timers --all | grep sub2test
sudo systemctl cat sub2test.timer
```

#### 查看执行日志

```bash
systemctl status sub2test.service --no-pager
journalctl -u sub2test.service -n 100 --no-pager
```

#### 查看状态文件

```bash
cat /opt/sub2test/state.json
```

### 工作机制

- `sub2test.timer` 负责按 systemd 时间规则触发
- `sub2test.service` 负责执行一次 `sub2test run-once`
- 脚本不是常驻业务进程，只在触发时运行，跑完退出

### 注意事项

- 如果重装前删除 `/opt/sub2test`，默认也会删除旧的 `state.json`，连续错误计数会重新开始
- `sub2test show-config` 中 `SUB2TEST_ADMIN_API_KEY=***set***` 只是脱敏显示，不代表真实值被改写
- `OnCalendar` 使用服务器本地时区，固定时间执行前请确认系统时区正确

### Release notes

#### v0.1.4

**中文**

- 修复 installer 本体在生成 service 时误调用运行时 helper，避免安装阶段出现 `systemd_lock_wait_seconds: command not found`
- 新增 `SUB2TEST_LOCK_WAIT_SECONDS` 配置项，让全量任务与未测任务的共享锁等待秒数可配置
- 给关键数值配置增加统一前置校验，并新增 `sub2test preflight`，让非法参数在安装、启用或重载前更早暴露
- 强化运行时数值解析错误提示，避免配置非法时只看到裸 `ValueError`

升级命令：

```bash
curl -fsSL https://raw.githubusercontent.com/SYFATP/sub2test-installer/master/sub2test-installer.sh -o /tmp/sub2test-installer.sh
chmod +x /tmp/sub2test-installer.sh
sudo bash /tmp/sub2test-installer.sh --force
sudo sub2test preflight
sudo systemctl daemon-reload
sudo systemctl restart sub2test.timer
sudo systemctl restart sub2test-untested.timer
```

注意：

- 重启 `sub2test.service` 或 `sub2test-untested.service` 会立即执行一次任务
- 如果只想刷新自动调度，不想立刻执行，请只重启对应的 `.timer`

**English**

- Fixed the installer shell mistakenly calling a runtime-only helper while rendering systemd services, so installation no longer fails with `systemd_lock_wait_seconds: command not found`
- Added `SUB2TEST_LOCK_WAIT_SECONDS` so the shared lock wait time is configurable for both full and untested tasks
- Added centralized preflight validation for critical numeric settings plus a new `sub2test preflight` command, so invalid values fail earlier during install, enable, or reload
- Improved runtime numeric parsing errors so invalid config no longer surfaces only as a bare `ValueError`

Upgrade command:

```bash
curl -fsSL https://raw.githubusercontent.com/SYFATP/sub2test-installer/master/sub2test-installer.sh -o /tmp/sub2test-installer.sh
chmod +x /tmp/sub2test-installer.sh
sudo bash /tmp/sub2test-installer.sh --force
sudo sub2test preflight
sudo systemctl daemon-reload
sudo systemctl restart sub2test.timer
sudo systemctl restart sub2test-untested.timer
```

Notes:

- Restarting `sub2test.service` or `sub2test-untested.service` will execute a task immediately
- If you only want to refresh scheduling without triggering a run, restart only the corresponding `.timer`

#### v0.1.3

**中文**

- 修复生成出来的 `sub2test` 运行脚本缺少版本号和项目地址变量的问题，避免 `show-config` 在 `set -u` 下报 `unbound variable`
- 全量任务调度模式改成子菜单选择，并补齐中英文翻译
- 选择全量任务调度模式后，只继续显示对应的下一级配置项
- 清理全量任务菜单里的手动执行入口，统一收口到“手动执行菜单”

升级命令：

```bash
curl -fsSL https://raw.githubusercontent.com/SYFATP/sub2test-installer/master/sub2test-installer.sh -o /tmp/sub2test-installer.sh
chmod +x /tmp/sub2test-installer.sh
sudo bash /tmp/sub2test-installer.sh --force
sudo systemctl daemon-reload
sudo systemctl restart sub2test.timer
sudo systemctl restart sub2test-untested.timer
```

注意：

- 重启 `sub2test.service` 或 `sub2test-untested.service` 会立即执行一次任务
- 如果只想刷新自动调度，不想立刻执行，请只重启对应的 `.timer`

**English**

- Fixed missing version and project URL variables in the generated `sub2test` runtime script so `show-config` no longer fails under `set -u`
- Changed full-task schedule mode selection to a translated submenu
- After choosing a full-task schedule mode, only the matching follow-up setting is prompted
- Removed manual execution entries from the full-task menu and kept them only in the shared manual-run menu

Upgrade command:

```bash
curl -fsSL https://raw.githubusercontent.com/SYFATP/sub2test-installer/master/sub2test-installer.sh -o /tmp/sub2test-installer.sh
chmod +x /tmp/sub2test-installer.sh
sudo bash /tmp/sub2test-installer.sh --force
sudo systemctl daemon-reload
sudo systemctl restart sub2test.timer
sudo systemctl restart sub2test-untested.timer
```

Notes:

- Restarting `sub2test.service` or `sub2test-untested.service` will execute a task immediately
- If you only want to refresh scheduling without triggering a run, restart only the corresponding `.timer`

#### v0.1.2

**中文**

- 新增主菜单版本号与项目地址显示，方便直接确认当前安装来源
- `show-config` 现在会显示脚本版本和项目地址
- 菜单结构重构为全局参数、全量任务、未测任务、手动执行四个独立入口
- 全量任务调度配置移入独立子菜单，未测任务配置与手动执行入口分离
- 未测任务自动调度统一为单一的分钟间隔配置 `SUB2TEST_UNTESTED_EVERY_MINUTES`（5-720）

升级命令：

```bash
curl -fsSL https://raw.githubusercontent.com/SYFATP/sub2test-installer/master/sub2test-installer.sh -o /tmp/sub2test-installer.sh
chmod +x /tmp/sub2test-installer.sh
sudo bash /tmp/sub2test-installer.sh --force
sudo systemctl daemon-reload
sudo systemctl restart sub2test.timer
sudo systemctl restart sub2test-untested.timer
```

注意：

- 重启 `sub2test.service` 或 `sub2test-untested.service` 会立即执行一次任务
- 如果只想刷新自动调度，不想立刻执行，请只重启对应的 `.timer`

**English**

- Added version and project URL to the main menu so the installed source is visible at a glance
- `show-config` now prints the script version and project URL
- Restructured the menu into separate global, full-task, untested-task, and manual-run entry points
- Moved full-task scheduling into its own submenu and separated untested-task config from manual execution
- Unified untested automatic scheduling into a single `SUB2TEST_UNTESTED_EVERY_MINUTES` setting (5-720)

Upgrade command:

```bash
curl -fsSL https://raw.githubusercontent.com/SYFATP/sub2test-installer/master/sub2test-installer.sh -o /tmp/sub2test-installer.sh
chmod +x /tmp/sub2test-installer.sh
sudo bash /tmp/sub2test-installer.sh --force
sudo systemctl daemon-reload
sudo systemctl restart sub2test.timer
sudo systemctl restart sub2test-untested.timer
```

Notes:

- Restarting `sub2test.service` or `sub2test-untested.service` will execute a task immediately
- If you only want to refresh scheduling without triggering a run, restart only the corresponding `.timer`

#### v0.1.1

**中文**

- 修复 `untested` 自动任务运行时报错 `NameError: mode is not defined`
- 修复普通非 SSE 响应分支的解析问题，避免全量任务和未测任务在共用运行路径上崩溃
- 保持 `untested` 模式按 `state.json` 过滤从未测试过的 active 账号
- 保持自动任务执行后正常写入 `state.json`
- 已在线验证全量自动任务与未测自动任务均可正常运行

升级命令：

```bash
curl -fsSL https://raw.githubusercontent.com/SYFATP/sub2test-installer/master/sub2test-installer.sh -o /tmp/sub2test-installer.sh
chmod +x /tmp/sub2test-installer.sh
sudo bash /tmp/sub2test-installer.sh --force
sudo systemctl daemon-reload
sudo systemctl restart sub2test.timer
sudo systemctl restart sub2test-untested.timer
```

注意：

- 重启 `sub2test.service` 或 `sub2test-untested.service` 会立即执行一次任务
- 如果只想刷新自动调度，不想立刻执行，请只重启对应的 `.timer`

**English**

- Fixed the `NameError: mode is not defined` crash in the `untested` scheduled task
- Fixed plain non-SSE response parsing so shared runtime paths no longer crash for full and untested runs
- Preserved `untested` filtering based on `state.json` for active accounts that have never been tested
- Preserved normal `state.json` updates after scheduled task execution
- Verified online that both full and untested scheduled tasks now run successfully

Upgrade command:

```bash
curl -fsSL https://raw.githubusercontent.com/SYFATP/sub2test-installer/master/sub2test-installer.sh -o /tmp/sub2test-installer.sh
chmod +x /tmp/sub2test-installer.sh
sudo bash /tmp/sub2test-installer.sh --force
sudo systemctl daemon-reload
sudo systemctl restart sub2test.timer
sudo systemctl restart sub2test-untested.timer
```

Notes:

- Restarting `sub2test.service` or `sub2test-untested.service` will execute a task immediately
- If you only want to refresh scheduling without triggering a run, restart only the corresponding `.timer`

---

## English

Current `sub2test-installer.sh` release: `0.1.4`.

`sub2test-installer.sh` installs an independent `sub2test` runtime for Sub2API. It can auto-discover database settings, call the admin account health-check API, disable accounts after a configurable consecutive `error` threshold, and run on a schedule via systemd timer.

### Quick start in 30 seconds

```bash
curl -fsSL https://raw.githubusercontent.com/SYFATP/sub2test-installer/master/sub2test-installer.sh -o /tmp/sub2test-installer.sh
chmod +x /tmp/sub2test-installer.sh
sudo bash /tmp/sub2test-installer.sh --force
sudo sub2test show-config
```

After installation, you get:

- Config file: `/etc/sub2api/sub2test.env`
- State file: `/opt/sub2test/state.json`
- Command entry: `/usr/local/bin/sub2test`
- Timer: `/etc/systemd/system/sub2test.timer`

### Common scheduling examples

#### Run every day at 00:00

```bash
sudo sed -i 's/^SUB2TEST_DAILY_AT=.*/SUB2TEST_DAILY_AT=00:00/' /etc/sub2api/sub2test.env
sudo sed -i 's/^SUB2TEST_EVERY_HOURS=.*/SUB2TEST_EVERY_HOURS=/' /etc/sub2api/sub2test.env
sudo sed -i 's/^SUB2TEST_RANDOMIZED_DELAY_SECONDS=.*/SUB2TEST_RANDOMIZED_DELAY_SECONDS=0/' /etc/sub2api/sub2test.env
sudo sub2test enable
```

#### Run every 6 hours

```bash
sudo sed -i 's/^SUB2TEST_DAILY_AT=.*/SUB2TEST_DAILY_AT=/' /etc/sub2api/sub2test.env
sudo sed -i 's/^SUB2TEST_EVERY_HOURS=.*/SUB2TEST_EVERY_HOURS=6/' /etc/sub2api/sub2test.env
sudo sed -i 's/^SUB2TEST_RANDOMIZED_DELAY_SECONDS=.*/SUB2TEST_RANDOMIZED_DELAY_SECONDS=0/' /etc/sub2api/sub2test.env
sudo sub2test enable
```

### Common commands

```bash
sudo sub2test show-config
sudo sub2test run-once
sudo sub2test enable
sudo sub2test disable
sudo sub2test menu
```

### Features

- Auto-detect database settings from `docker-compose.yml` or `config.yaml`
- Call `/admin/accounts/{id}/test` for account health checks
- Persist consecutive `error` counts in a local state file
- Disable accounts through `/admin/accounts/{id}` after reaching the threshold
- Support fixed daily execution time
- Support execution every N hours
- Keep backward compatibility with legacy `hourly / daily / weekly` scheduling

### Full configuration reference

Config file path: `/etc/sub2api/sub2test.env`

#### API and state

```env
SUB2TEST_API_BASE_URL=http://127.0.0.1:38080/api/v1
SUB2TEST_ADMIN_API_KEY=your-admin-api-key
SUB2TEST_ERROR_STREAK_THRESHOLD=3
SUB2TEST_STATE_FILE=/opt/sub2test/state.json
```

Notes:

- `SUB2TEST_ERROR_STREAK_THRESHOLD`: disable an account after this many consecutive `native_status=error` results
- `SUB2TEST_STATE_FILE`: local persistence file path, default is `/opt/sub2test/state.json`

#### Scheduling

##### Option 1: run at a fixed daily time

```env
SUB2TEST_DAILY_AT=00:00
SUB2TEST_EVERY_HOURS=
SUB2TEST_RANDOMIZED_DELAY_SECONDS=0
```

Notes:

- `SUB2TEST_DAILY_AT` must use `HH:MM`
- It has the highest priority
- `SUB2TEST_RANDOMIZED_DELAY_SECONDS=0` disables random delay for near-exact execution

##### Option 2: run every N hours

```env
SUB2TEST_DAILY_AT=
SUB2TEST_EVERY_HOURS=6
SUB2TEST_RANDOMIZED_DELAY_SECONDS=0
```

Notes:

- `SUB2TEST_EVERY_HOURS` must be between `1` and `23`
- Example: `6` means run every 6 hours

##### Option 3: legacy schedule compatibility

```env
SUB2TEST_SCHEDULE=daily
```

Supported values:

- `hourly`
- `daily`
- `weekly`

Priority order:

1. `SUB2TEST_DAILY_AT`
2. `SUB2TEST_EVERY_HOURS`
3. `SUB2TEST_SCHEDULE`

### Inspection and troubleshooting

#### Check timer status

```bash
systemctl status sub2test.timer --no-pager
systemctl list-timers --all | grep sub2test
sudo systemctl cat sub2test.timer
```

#### Check execution logs

```bash
systemctl status sub2test.service --no-pager
journalctl -u sub2test.service -n 100 --no-pager
```

#### Check the state file

```bash
cat /opt/sub2test/state.json
```

### How it works

- `sub2test.timer` handles time-based triggering via systemd
- `sub2test.service` runs one `sub2test run-once` execution
- The script is not a long-running business process; it starts on trigger and exits when done

### Notes

- If you delete `/opt/sub2test` before reinstalling, the old `state.json` will also be removed and streak counts restart from zero
- `SUB2TEST_ADMIN_API_KEY=***set***` in `sub2test show-config` is only a masked display, not the real stored value
- `OnCalendar` uses the server's local timezone, so verify system timezone before relying on fixed execution time
