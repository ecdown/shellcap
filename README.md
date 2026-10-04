# ShellCap

Shell command logging with SQLite and per-session tracking. Captures every command run in interactive shells, records pass/fail (exit codes), tracks sessions by terminal, and optionally masks secrets.

## Features

- **SQLite storage**: Commands and sessions stored in SQLite for easy querying
- **Session tracking**: Each interactive shell session gets a unique UUID with tty, user, host, SSH info, login time
- **Exit code tracking**: Records success/fail (pass/fail) for each command
- **Secret masking**: Configurable masking of passwords/tokens in logged commands
- **Skip patterns**: Exclude specific commands from logging via regex patterns
- **Bash and Zsh support**: Works with both shells
- **Lightweight**: Python-based logger, minimal shell overhead

## Installation

1. Clone/copy this repo to a location (e.g., `/opt/shellcap` or your home)
2. Run the install script:

```bash
./install.sh
```

Or manually:
- Copy files to appropriate locations (`~/.config/shellcap/`, `~/.local/lib/shellcap/`, `~/.local/bin/`)
- Add sourcing to `~/.bashrc` and optionally `~/.zshrc`

3. Start a new shell session - logging begins automatically for interactive shells.

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
export SHELLCAP_DB="$HOME/.local/share/shellcap/shellcap.db"

# Logger script path
export SHELLCAP_LOGGER="$HOME/.local/lib/shellcap/shellcap_log.py"

# Skip logging for root (default: 1)
export SHELLCAP_SKIP_ROOT=1

# Mask secrets like passwords/tokens (default: 1)
export SHELLCAP_MASK_SECRETS=1

# Skip logging commands matching these regex patterns (semicolon-separated)
export SHELLCAP_SKIP_PATTERNS=""
```

Example skip patterns:
```bash
export SHELLCAP_SKIP_PATTERNS="^cd\s*$;^ls$;^clear$"
```

## Querying

Use the `shellcap-query` tool:

```bash
# List all sessions
shellcap-query

# View commands for a specific session (by session ID prefix)
shellcap-query --session c56f1ca3
```

Or query SQLite directly:

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

-- Failed commands in last hour
SELECT * FROM commands
WHERE exit_code != 0 AND executed_at > datetime('now','-1 hour');

-- Commands containing 'git'
SELECT c.command, c.executed_at, c.exit_code
FROM commands c
WHERE c.command LIKE '%git%'
ORDER BY c.executed_at DESC;
```

## Schema

**sessions** table:
- `session_id` (TEXT PK): Unique session identifier
- `user`, `hostname`, `tty`: Session context
- `pid`, `ppid`, `shell`: Process info
- `login_time`, `end_time`: Timestamps (UTC)
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

## Security Notes

- The database may contain sensitive data in command lines. By default, secret masking is enabled (`SHELLCAP_MASK_SECRETS=1`). 
- Set appropriate file permissions on the database (`chmod 600 ~/.local/share/shellcap/shellcap.db` is recommended)
- Be aware of local policies/regulations regarding command logging
