#!/usr/bin/env python3
import os
import sys
import json
import sqlite3
from datetime import datetime
import pwd
import re

SENSITIVE_PATTERNS = [
    # -p with no space, or quoted
    re.compile(r'(^|\s)-p([\'"][^\'"]*[\'"]|[^\s\'"]+)', re.I),
    # --password=... or -p=...
    re.compile(r'(^|\s)(?:--password|-p)\s*=\s*([\'"][^\'"]*[\'"]|[^\s\'"]+)', re.I),
    # -p followed by space then password
    re.compile(r'(^|\s)(?:-p|--password)\s+([\'"][^\'"]*[\'"]|[^\s\'"]+)', re.I),
    # URLs with embedded creds
    re.compile(r'(https?://[^:]+:)([^@]+)(@)'),
    # sshpass
    re.compile(r'(sshpass\s+-p\s+)([\'"][^\'"]*[\'"]|[^\s]+)', re.I),
    # -u user:pass form (curl etc)
    re.compile(r'((?:-u|--user)\s+[^\s:]+:)([^\s]+)', re.I),
    # env vars
    re.compile(r'(PGPASSWORD=)([^\s]+)', re.I),
    re.compile(r'(MYSQL_PWD=)([^\s]+)', re.I),
    re.compile(r'(AWS_SECRET_ACCESS_KEY=)([^\s]+)', re.I),
    # generic key=value forms
    re.compile(r'((?:token|secret|apikey|api_key|auth|credential)\s*=\s*)([^\s\'"]+|[\'"][^\'"]*[\'"])', re.I),
]

def mask_command(cmd):
    if not cmd:
        return cmd
    masked = cmd
    for pat in SENSITIVE_PATTERNS:
        # For patterns that capture the password in group 2, keep group 1 and mask group 2
        try:
            masked = pat.sub(lambda m: m.group(1) + ('******' if len(m.groups()) >= 2 else '******'), masked)
        except Exception:
            pass
    # Also handle -p with no space more explicitly
    masked = re.sub(r'(^|\s)-p([^\s\'"]+)', r'\1-p******', masked, flags=re.I)
    return masked

def get_db_path():
    db = os.environ.get('SHELLCAP_DB')
    if db:
        return db
    return os.path.expanduser('~/.local/share/shellcap/shellcap.db')

def ensure_db_schema(conn):
    cur = conn.cursor()
    cur.execute('''CREATE TABLE IF NOT EXISTS sessions (
      session_id TEXT PRIMARY KEY,
      user TEXT NOT NULL,
      hostname TEXT,
      tty TEXT,
      pid INTEGER,
      ppid INTEGER,
      shell TEXT,
      login_time TEXT NOT NULL,
      end_time TEXT,
      ssh_client TEXT,
      ip TEXT,
      xdg_session_id TEXT
    )''')
    cur.execute('''CREATE TABLE IF NOT EXISTS commands (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT NOT NULL,
      executed_at TEXT NOT NULL,
      cwd TEXT,
      command TEXT,
      exit_code INTEGER,
      duration_ms INTEGER,
      shell_pid INTEGER,
      FOREIGN KEY (session_id) REFERENCES sessions(session_id)
    )''')
    cur.execute('CREATE INDEX IF NOT EXISTS idx_commands_session ON commands(session_id)')
    cur.execute('CREATE INDEX IF NOT EXISTS idx_commands_time ON commands(executed_at)')
    cur.execute('CREATE INDEX IF NOT EXISTS idx_commands_cmd ON commands(command)')
    conn.commit()

def get_user():
    try:
        return pwd.getpwuid(os.getuid()).pw_name
    except Exception:
        return os.environ.get('USER', 'unknown')

def ensure_session(conn, session_id):
    cur = conn.cursor()
    cur.execute('SELECT session_id FROM sessions WHERE session_id = ?', (session_id,))
    if cur.fetchone():
        return
    tty = os.environ.get('SHELLCAP_TTY', '')
    try:
        if not tty and sys.stdin.isatty():
            tty = os.ttyname(sys.stdin.fileno())
    except Exception:
        pass
    ssh_client = os.environ.get('SSH_CLIENT', '')
    ip = ''
    if ssh_client:
        try:
            ip = ssh_client.split()[0]
        except Exception:
            ip = ssh_client
    cur.execute('''INSERT INTO sessions (session_id, user, hostname, tty, pid, ppid, shell, login_time, ssh_client, ip, xdg_session_id)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
                (session_id,
                 get_user(),
                 os.uname().nodename,
                 tty,
                 os.getpid(),
                 os.getppid(),
                 os.environ.get('SHELL', '/bin/bash'),
                 datetime.utcnow().replace(microsecond=0).isoformat() + 'Z',
                 ssh_client,
                 ip,
                 os.environ.get('XDG_SESSION_ID', '')))
    conn.commit()

def insert_command(conn, data):
    cur = conn.cursor()
    cmd = data.get('command')
    if os.environ.get('SHELLCAP_MASK_SECRETS', '1') != '0':
        cmd = mask_command(cmd)
    skip_patterns = os.environ.get('SHELLCAP_SKIP_PATTERNS', '')
    if skip_patterns:
        try:
            for pat in [p.strip() for p in skip_patterns.split(';') if p.strip()]:
                if re.search(pat, cmd or '', re.I):
                    return
        except Exception:
            pass
    cur.execute('''INSERT INTO commands (session_id, executed_at, cwd, command, exit_code, duration_ms, shell_pid)
                   VALUES (?, ?, ?, ?, ?, ?, ?)''',
                (data.get('session_id'),
                 data.get('executed_at'),
                 data.get('cwd'),
                 cmd,
                 data.get('exit_code'),
                 data.get('duration_ms'),
                 data.get('shell_pid')))
    conn.commit()

def main():
    try:
        payload = sys.stdin.buffer.read().decode('utf-8', errors='replace')
        data = json.loads(payload)
        db = get_db_path()
        os.makedirs(os.path.dirname(db), exist_ok=True)
        conn = sqlite3.connect(db)
        conn.execute('PRAGMA journal_mode=WAL')
        ensure_db_schema(conn)
        if data.get('session_id'):
            ensure_session(conn, data['session_id'])
        insert_command(conn, data)
        conn.close()
        return 0
    except Exception:
        return 0

if __name__ == '__main__':
    sys.exit(main())
