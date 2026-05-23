# sub2test-installer

Current release: `0.1.6`

- [中文](#中文)
- [English](#english)

---

## 中文

`sub2test-installer.sh` 当前发布版本为 `0.1.6`。

`sub2test-installer.sh` 用来给 Sub2API 部署一套独立的 `sub2test` 运行环境：自动发现数据库配置、调用管理端账号测活接口、把连续 `error` 的账号在达到阈值后自动设为 `disabled`，并可通过 systemd timer 定时执行。

### 30 秒快速开始

```bash
curl -fsSL https://raw.githubusercontent.com/SYFATP/sub2test-installer/master/sub2test-installer.sh -o /tmp/sub2test-installer.sh
chmod +x /tmp/sub2test-installer.sh
sudo bash /tmp/sub2test-installer.sh --force
sudo sub2test show-config
```

### 常用命令

```bash
sudo sub2test show-config
sudo sub2test run-once
sudo sub2test run-proxy-assign-now
sudo sub2test enable
sudo sub2test disable
sudo sub2test menu
```

### 功能概览

- 自动发现数据库配置
- 账号测活与连续 error 自动停用
- 未测 / 重复账号 / 代理分配三类独立任务
- 支持 systemd timer 定时执行
- 支持手动执行与日志查看

### 查看和排障

```bash
systemctl status sub2test.timer --no-pager
journalctl -u sub2test.service -n 100 --no-pager
sudo sub2test run-proxy-assign-now
```

### 注意事项

- 删除 `/opt/sub2test` 会清空本地状态文件
- `SUB2TEST_ADMIN_API_KEY` 只在 `show-config` 中脱敏显示
- `OnCalendar` 使用服务器本地时区

## English

Current `sub2test-installer.sh` release: `0.1.6`.

`sub2test-installer.sh` installs an independent `sub2test` runtime for Sub2API. It can auto-discover database settings, call the admin account health-check API, disable accounts after a configurable consecutive `error` threshold, and run on a schedule via systemd timer.

### Quick start in 30 seconds

```bash
curl -fsSL https://raw.githubusercontent.com/SYFATP/sub2test-installer/master/sub2test-installer.sh -o /tmp/sub2test-installer.sh
chmod +x /tmp/sub2test-installer.sh
sudo bash /tmp/sub2test-installer.sh --force
sudo sub2test show-config
```

### Common commands

```bash
sudo sub2test show-config
sudo sub2test run-once
sudo sub2test run-proxy-assign-now
sudo sub2test enable
sudo sub2test disable
sudo sub2test menu
```

### Features

- Auto-detect database settings
- Account health checks and automatic disable on consecutive errors
- Separate untested / duplicate / proxy-assignment tasks
- Systemd timer scheduling
- Manual execution and log viewing

### Troubleshooting

```bash
systemctl status sub2test.timer --no-pager
journalctl -u sub2test.service -n 100 --no-pager
sudo sub2test run-proxy-assign-now
```

### Notes

- Removing `/opt/sub2test` clears local state
- `SUB2TEST_ADMIN_API_KEY` is masked in `show-config`
- `OnCalendar` uses the server's local timezone

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

Current `sub2test-installer.sh` release: `0.1.6`.

`sub2test-installer.sh` installs an independent `sub2test` runtime for Sub2API. It can auto-discover database settings, call the admin account health-check API, disable accounts after a configurable consecutive `error` threshold, and run on a schedule via systemd timer.

### Quick start in 30 seconds

```bash
curl -fsSL https://raw.githubusercontent.com/SYFATP/sub2test-installer/master/sub2test-installer.sh -o /tmp/sub2test-installer.sh
chmod +x /tmp/sub2test-installer.sh
sudo bash /tmp/sub2test-installer.sh --force
sudo sub2test show-config
```

### Common commands

```bash
sudo sub2test show-config
sudo sub2test run-once
sudo sub2test run-proxy-assign-now
sudo sub2test enable
sudo sub2test disable
sudo sub2test menu
```

### Features

- Auto-detect database settings
- Account health checks and automatic disable on consecutive errors
- Separate untested / duplicate / proxy-assignment tasks
- Systemd timer scheduling
- Manual execution and log viewing

### Troubleshooting

```bash
systemctl status sub2test.timer --no-pager
journalctl -u sub2test.service -n 100 --no-pager
sudo sub2test run-proxy-assign-now
```

### Notes

- Removing `/opt/sub2test` clears local state
- `SUB2TEST_ADMIN_API_KEY` is masked in `show-config`
- `OnCalendar` uses the server's local timezone

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
