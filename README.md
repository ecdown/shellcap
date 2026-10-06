# ShellCap

Shell command logging with SQLite and per-session tracking. Captures every command run in interactive shells, records pass/fail (exit codes) and duration, tracks sessions by terminal, and masks secrets.

## Features

- **SQLite storage**: Commands and sessions stored in SQLite for easy querying (WAL mode enabled)
- **Session tracking**: Each interactive shell session gets a unique UUID with tty, user, host, SSH info, login time
- **Exit code & duration tracking**: Records success/fail (pass/fail) and elapsed milliseconds for each command
- **Secret masking**: On by default; masks passwords/tokens in logged commands as `******`
- **Skip patterns**: Exclude specific commands from logging via case-insensitive regex patterns
- **Bash and Zsh support**: Works with both shells
- **Lightweight**: Python-based logger, minimal shell overhead
- **Query tool**: `shellcap-query` for browsing sessions and per-session command history

## Requirements

- Bash or Zsh
- Python 3 (uses the stdlib `sqlite3` module — no pip packages required)
- `uuidgen` or `/proc/sys/kernel/random/uuid` for session IDs (falls back to a timestamp+pid if neither is available)
- `sqlite3` CLI is optional; only needed for ad-hoc queries. `shellcap-query` works without it.

## Installation

1. Clone/copy this repo to a location (e.g., `/opt/shellcap` or your home)
2. Run the install script:

```bash
./install.sh
```

The script detects Python 3, creates the target directories, copies the files, rewrites the shebangs of the Python scripts to the detected interpreter, and adds a source line to `~/.bashrc` and `~/.zshrc` if those files exist.

Installed layout:

| Path | Contents |
| --- | --- |
| `~/.config/shellcap/shellcap.env` | Environment configuration |
| `~/.config/shellcap/shellcap.bash` | Generated bash loader (sources `shellcap.env` + `shellcap.bash.inc`) |
| `~/.config/shellcap/shellcap.bash.inc` | Bash integration (DEBUG trap + PROMPT_COMMAND) |
| `~/.config/shellcap/shellcap.zsh` | Zsh integration (preexec/precmd hooks) |
| `~/.local/lib/shellcap/shellcap_log.py` | Python SQLite logger |
| `~/.local/bin/shellcap-query` | Query utility |
| `~/.local/share/shellcap/` | Database directory |

To install manually, copy the files to those locations and source the integration from your shell rc:

```bash
# ~/.bashrc
[ -f ~/.config/shellcap/shellcap.bash ] && . ~/.config/shellcap/shellcap.bash

# ~/.zshrc
[ -f ~/.config/shellcap/shellcap.zsh ] && . ~/.config/shellcap/shellcap.zsh
```

3. Start a new shell session — logging begins automatically for interactive shells.

## File Structure

```
shellcap/
├── install.sh              # Installation script
├── README.md               # This file
├── shellcap.bash.inc       # Bash integration (DEBUG trap + PROMPT_COMMAND)
├── shellcap.zsh            # Zsh integration (preexec/precmd hooks)
├── shellcap_log.py         # Python SQLite logger
├── shellcap.env            # Environment configuration
└── shellcap-query          # Query utility
```

## Configuration

Edit `~/.config/shellcap/shellcap.env`:

```bash
# Database location
export SHELLCAP_DB="${SHELLCAP_DB:-$HOME/.local/share/shellcap/shellcap.db}"

# Logger script path
export SHELLCAP_LOGGER="$HOME/.local/lib/shellcap/shellcap_log.py"

# Skip logging when running as root (default: 1)
export SHELLCAP_SKIP_ROOT=1

# Mask secrets like passwords/tokens (default: 1; set to 0 to disable)
export SHELLCAP_MASK_SECRETS=1

# Skip logging commands matching these regex patterns (semicolon-separated)
export SHELLCAP_SKIP_PATTERNS=""
```

Additional variables honored at runtime (not normally set in `shellcap.env`):

| Variable | Purpose |
| --- | --- |
| `SHELLCAP_FORCE=1` | Log even in non-interactive shells (useful for testing) |
| `SHELLCAP_SESSION_ID` | Override the auto-generated session UUID |
| `SHELLCAP_TTY` | Override the detected tty |

### Skip patterns

Patterns are separated by semicolons and matched case-insensitively against the command line. A match anywhere in the command causes it to be dropped:

```bash
export SHELLCAP_SKIP_PATTERNS="^cd\s*$;^ls$;^clear$"
```

### Secret masking

With `SHELLCAP_MASK_SECRETS` enabled (the default), the logger rewrites sensitive values to `******` before writing to the database. Covered cases:

- `-p` / `--password` values, including `-p=value`, `--password=value`, and quoted forms
- Credentials embedded in URLs (`https://user:pass@host`)
- `sshpass -p <password>`
- `curl`-style `-u user:pass` and `--user user:pass`
- `PGPASSWORD=`, `MYSQL_PWD=`, `AWS_SECRET_ACCESS_KEY=`
- Generic `token=`, `secret=`, `apikey=`, `api_key=`, `auth=`, `credential=`

Masking is pattern-based and not exhaustive. Review the regexes in `shellcap_log.py` and extend them if you use other secret-bearing flags.

## Querying

`shellcap-query` reads the database from `SHELLCAP_DB`, or `~/.local/share/shellcap/shellcap.db` if unset.

```bash
# List recent sessions (default view, newest first)
shellcap-query

# Limit the number of sessions listed (default: 10)
shellcap-query --limit 25

# Show commands for a session, by 8-character session ID prefix
shellcap-query --id c56f1ca3

# Include timestamp, cwd, and exit code for each command
shellcap-query --id c56f1ca3 --all
```

Example output:

```
$ shellcap-query
Sessions:
1. c56f1ca3... tty=/dev/pts/2 user=ecdown login=2026-10-04T14:02:11Z ssh=10.0.0.5 51234 22

$ shellcap-query --id c56f1ca3
git status
mysql -u root:****** -p

$ shellcap-query --id c56f1ca3 --all
2026-10-04T14:02:15Z [/home/ecdown/projects/shellcap] (0) git status
2026-10-04T14:02:19Z [/home/ecdown/projects/shellcap] (1) mysql -u root:****** -p
```

Notes on `--id`:

- Only the first 8 characters of the session UUID are accepted; any other length prints `No Session: <id> found.`
- Commands are printed oldest-first. Without `--all`, only the command text is shown.

### Direct SQLite queries

The database defaults to `~/.local/share/shellcap/shellcap.db`:

```bash
sqlite3 ~/.local/share/shellcap/shellcap.db
```

Example queries:

```sql
-- All commands from a specific terminal
SELECT s.tty, s.login_time, c.executed_at, c.cwd, c.command, c.exit_code
FROM commands c JOIN sessions s ON s.session_id=c.session_id
WHERE s.tty='/dev/pts/2'
ORDER BY c.executed_at;

-- Failed commands in the last hour
-- Timestamps are stored as 'YYYY-MM-DDTHH:MM:SSZ', so strftime (not datetime)
-- is required for a correct comparison.
SELECT * FROM commands
WHERE exit_code != 0
  AND executed_at > strftime('%Y-%m-%dT%H:%M:%SZ','now','-1 hour');

-- Slowest commands in the current day
SELECT command, duration_ms, exit_code
FROM commands
WHERE duration_ms > 1000
ORDER BY duration_ms DESC
LIMIT 20;

-- Commands containing 'git'
SELECT c.command, c.executed_at, c.exit_code
FROM commands c
WHERE c.command LIKE '%git%'
ORDER BY c.executed_at DESC;

-- Sessions by SSH client, with command counts
SELECT s.ssh_client, s.ip, COUNT(c.id) AS commands
FROM sessions s LEFT JOIN commands c ON c.session_id=s.session_id
GROUP BY s.session_id
ORDER BY s.login_time DESC;
```

## Schema

**sessions** table:
- `session_id` (TEXT PK): Unique session identifier
- `user`, `hostname`, `tty`: Session context
- `pid`, `ppid`, `shell`: Process info
- `login_time`, `end_time`: Timestamps (UTC ISO8601). `end_time` is currently never populated
- `ssh_client`, `ip`, `xdg_session_id`: Connection info

**commands** table:
- `id` (INTEGER PK, autoincrement)
- `session_id` (FK): Links to sessions
- `executed_at` (TEXT): Command execution time (UTC ISO8601)
- `cwd` (TEXT): Current working directory
- `command` (TEXT): Full command line (with args, secrets masked if enabled)
- `exit_code` (INTEGER): Exit code (0=success/pass, non-zero=fail)
- `duration_ms` (INTEGER): Execution duration in milliseconds
- `shell_pid` (INTEGER): Shell process ID

Indexes: `idx_commands_session` (session_id), `idx_commands_time` (executed_at), `idx_commands_cmd` (command). The logger enables `journal_mode=WAL` and creates the schema on first write, so no manual migration is needed.

## How It Works

- **Bash**: a `DEBUG` trap captures the command before it runs and `PROMPT_COMMAND` logs it afterwards with the exit status and elapsed time.
- **Zsh**: `preexec` records the command and `precmd` logs it with `$EPOCHREALTIME`-derived duration.
- Each shell sends a JSON payload on stdin to `shellcap_log.py`, which opens the database, ensures the session row exists, applies masking and skip patterns, and inserts the command.
- Logging only runs for interactive shells, and by default is skipped when `id -u` is 0. The logger swallows all errors and always exits 0, so a logging failure never blocks or breaks your shell.

## Security Notes

- The database may contain sensitive data in command lines. By default, secret masking is enabled (`SHELLCAP_MASK_SECRETS=1`).
- Set appropriate file permissions on the database and its WAL sidecar files (`chmod 600 ~/.local/share/shellcap/shellcap.db*` is recommended).
- Secret masking is heuristic; treat the database as sensitive regardless of the setting.
- To remove shellcap, delete the installed files, the source lines added to `~/.bashrc`/`~/.zshrc`, and optionally `~/.local/share/shellcap/`.
- Be aware of local policies/regulations regarding command logging.
## Pause/Unpause

You can temporarily pause capture in the current shell session or globally:

```bash
# Pause current session
shellcap pause

# Unpause
shellcap unpause

# Check status
shellcap status

# Pause/unpause globally (affects all sessions)
shellcap pause --global
shellcap unpause --global

# Unpause everything
shellcap unpause --all

# Also available as standalone commands
shellcap-pause
shellcap-unpause
shellcap-status
shellcap-state status
```

The pause state is tracked via files in `~/.local/state/shellcap/paused/` (or `$SHELLCAP_STATE_DIR/paused/`). A session-specific marker is created for the current terminal; global pause takes precedence if set.
