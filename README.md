# sub2test-installer

- [中文](#中文)
- [English](#english)

---

## 中文

`sub2test-installer.sh` 用来给 Sub2API 部署一套独立的 `sub2test` 运行环境：自动发现数据库配置、调用管理端账号测活接口、把连续 `error` 的账号在达到阈值后自动设为 `disabled`，并可通过 systemd timer 定时执行。

### 功能概览

- 自动从 `docker-compose.yml` 或 `config.yaml` 推断数据库连接信息
- 调用管理端 `/admin/accounts/{id}/test` 做账号测活
- 本地持久化连续 `error` 次数到状态文件
- 达到阈值后调用管理端 `/admin/accounts/{id}` 把账号置为 `disabled`
- 支持固定每天某个时间执行
- 支持每隔 N 小时执行一次
- 保留旧的 `hourly / daily / weekly` 调度兼容方式

### 安装

```bash
curl -fsSL https://raw.githubusercontent.com/SYFATP/sub2test-installer/master/sub2test-installer.sh -o /tmp/sub2test-installer.sh
chmod +x /tmp/sub2test-installer.sh
sudo bash /tmp/sub2test-installer.sh --force
```

安装完成后会生成：

- 配置文件：`/etc/sub2api/sub2test.env`
- 脚本目录：`/opt/sub2test`
- 命令入口：`/usr/local/bin/sub2test`
- systemd service：`/etc/systemd/system/sub2test.service`
- systemd timer：`/etc/systemd/system/sub2test.timer`

### 常用命令

```bash
sudo sub2test show-config
sudo sub2test run-once
sudo sub2test enable
sudo sub2test disable
sudo sub2test menu
```

### 关键配置

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

### 启用定时任务

修改好配置后执行：

```bash
sudo sub2test enable
```

查看定时器状态：

```bash
systemctl status sub2test.timer --no-pager
systemctl list-timers --all | grep sub2test
```

### 状态文件

默认状态文件：

```bash
/opt/sub2test/state.json
```

主要用于记录：

- 每个账号的 `consecutive_error_count`
- 最近一次 `last_native_status`
- 是否已经由脚本触发过停用 `disabled_by_sub2test_at`

查看：

```bash
cat /opt/sub2test/state.json
```

### 工作机制

- `sub2test.timer` 负责按 systemd 时间规则触发
- `sub2test.service` 负责执行一次 `sub2test run-once`
- 脚本不是常驻业务进程，只在触发时运行，跑完退出

### 验证建议

#### 手动执行一次

```bash
sudo sub2test run-once
```

#### 查看配置

```bash
sudo sub2test show-config
```

#### 查看 timer 实际生效规则

```bash
sudo systemctl cat sub2test.timer
```

#### 查看执行日志

```bash
systemctl status sub2test.service --no-pager
journalctl -u sub2test.service -n 100 --no-pager
```

### 示例

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

### 注意事项

- 如果重装前删除 `/opt/sub2test`，默认也会删除旧的 `state.json`，连续错误计数会重新开始
- `sub2test show-config` 中 `SUB2TEST_ADMIN_API_KEY=***set***` 只是脱敏显示，不代表真实值被改写
- `OnCalendar` 使用服务器本地时区，固定时间执行前请确认系统时区正确

---

## English

`sub2test-installer.sh` installs an independent `sub2test` runtime for Sub2API. It can auto-discover database settings, call the admin account health-check API, disable accounts after a configurable consecutive `error` threshold, and run on a schedule via systemd timer.

### Features

- Auto-detect database settings from `docker-compose.yml` or `config.yaml`
- Call `/admin/accounts/{id}/test` for account health checks
- Persist consecutive `error` counts in a local state file
- Disable accounts through `/admin/accounts/{id}` after reaching the threshold
- Support fixed daily execution time
- Support execution every N hours
- Keep backward compatibility with legacy `hourly / daily / weekly` scheduling

### Installation

```bash
curl -fsSL https://raw.githubusercontent.com/SYFATP/sub2test-installer/master/sub2test-installer.sh -o /tmp/sub2test-installer.sh
chmod +x /tmp/sub2test-installer.sh
sudo bash /tmp/sub2test-installer.sh --force
```

The installer creates:

- Config file: `/etc/sub2api/sub2test.env`
- Script directory: `/opt/sub2test`
- Command entry: `/usr/local/bin/sub2test`
- systemd service: `/etc/systemd/system/sub2test.service`
- systemd timer: `/etc/systemd/system/sub2test.timer`

### Common commands

```bash
sudo sub2test show-config
sudo sub2test run-once
sudo sub2test enable
sudo sub2test disable
sudo sub2test menu
```

### Key configuration

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

### Enable the timer

After updating the config, run:

```bash
sudo sub2test enable
```

Check timer status:

```bash
systemctl status sub2test.timer --no-pager
systemctl list-timers --all | grep sub2test
```

### State file

Default state file:

```bash
/opt/sub2test/state.json
```

It mainly stores:

- `consecutive_error_count` for each account
- last observed `last_native_status`
- `disabled_by_sub2test_at` once the script has disabled the account

View it with:

```bash
cat /opt/sub2test/state.json
```

### How it works

- `sub2test.timer` handles time-based triggering via systemd
- `sub2test.service` runs one `sub2test run-once` execution
- The script is not a long-running business process; it starts on trigger and exits when done

### Validation

#### Run once manually

```bash
sudo sub2test run-once
```

#### Show current config

```bash
sudo sub2test show-config
```

#### Inspect the effective timer

```bash
sudo systemctl cat sub2test.timer
```

#### Inspect execution logs

```bash
systemctl status sub2test.service --no-pager
journalctl -u sub2test.service -n 100 --no-pager
```

### Examples

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

### Notes

- If you delete `/opt/sub2test` before reinstalling, the old `state.json` will also be removed and streak counts restart from zero
- `SUB2TEST_ADMIN_API_KEY=***set***` in `sub2test show-config` is only a masked display, not the real stored value
- `OnCalendar` uses the server's local timezone, so verify system timezone before relying on fixed execution time
