# Production-Ready Logging with AWS CloudWatch for Python applications

Today we're going to build a production-grade logging system for Python applications using. We're going to use CloudWatch Agent with it's `auto_removal` feature to automatically delete log files after they've been uploaded to CloudWatch Logs.

This architectural constraint requires careful design of your logging pipeline.

The solution uses a dual-formatter approach:
- **Console output**: Human-readable format for `docker compose logs`
- **File output**: Structured JSON for CloudWatch with hourly rotation
- **CloudWatch Agent**: Reads rotated files and automatically deletes them after upload

```mermaid
flowchart TD
    A[Flask App] --> B[Logging System<br/>(dual formatters)]

    B --> C[Console Handler<br/>Human-readable + extras]
    B --> D[File Handler<br/>JSON (hourly rotation)]

    D --> E[Rotated files<br/>app.log.YYYY-MM-DD_HH]
    E --> F[CloudWatch Agent<br/>auto_removal: true]
    F --> G[AWS CloudWatch Logs]
```

The logging system uses two custom formatters to serve different purposes:

```python
from datetime import datetime
from logging.handlers import TimedRotatingFileHandler
from pythonjsonlogger.json import JsonFormatter
import logging

class CloudWatchJsonFormatter(JsonFormatter):
    """JSON formatter for CloudWatch logs with custom metadata fields."""

    def __init__(self, app: str, process: str, *args, **kwargs):
        self.app = app
        self.process = process
        super().__init__(*args, **kwargs)

    def add_fields(self, log_record, record, message_dict):
        """Add CloudWatch-specific fields to log record."""
        log_record['@timestamp'] = datetime.fromtimestamp(record.created).isoformat()
        log_record['level'] = record.levelname
        log_record['app'] = self.app
        log_record['logger'] = record.name
        log_record['process'] = self.process
        super(CloudWatchJsonFormatter, self).add_fields(log_record, record, message_dict)


class ConsoleFormatter(logging.Formatter):
    """Console formatter that includes extra fields."""

    RESERVED_ATTRS = {
        'name', 'msg', 'args', 'created', 'filename', 'funcName', 'levelname',
        'levelno', 'lineno', 'module', 'msecs', 'message', 'pathname', 'process',
        'processName', 'relativeCreated', 'thread', 'threadName', 'exc_info',
        'exc_text', 'stack_info', 'asctime'
    }

    def format(self, record):
        base_message = super().format(record)

        # Extract extra fields
        extras = {
            key: value
            for key, value in record.__dict__.items()
            if key not in self.RESERVED_ATTRS
        }

        if extras:
            extras_str = ' '.join(f'{k}={v}' for k, v in extras.items())
            return f'{base_message} | {extras_str}'

        return base_message
```

The `ConsoleFormatter` automatically appends extra fields to the log message, making debugging easier. The `CloudWatchJsonFormatter` creates structured JSON logs with CloudWatch-specific metadata.

The key to making `auto_removal` work is using `TimedRotatingFileHandler` with hourly rotation:

```python
from typing import Literal, Union
from pathlib import Path

def setup_logging(
    env: Literal['local', 'production'],
    app: str,
    log_path: Union[Path, str],
    process: str = 'main',
    log_level: str = 'INFO'
) -> None:
    """Configure logging with environment-specific settings."""
    if env == 'local':
        logging.basicConfig(
            format='%(asctime)s [%(levelname)s] %(message)s',
            level=log_level,
            datefmt='%d/%m/%Y %X'
        )
    else:
        # Console handler with human-readable format
        console_handler = logging.StreamHandler()
        console_formatter = ConsoleFormatter(
            fmt='%(asctime)s [%(levelname)s] %(name)s - %(message)s',
            datefmt='%Y-%m-%d %H:%M:%S'
        )
        console_handler.setFormatter(console_formatter)

        # JSON formatter for file (CloudWatch)
        json_formatter = CloudWatchJsonFormatter(
            app=app,
            process=process,
            fmt='%(levelname)s %(name)s %(message)s'
        )

        # File handler with hourly rotation
        file_handler = TimedRotatingFileHandler(
            log_path,
            when='H',        # Hourly rotation
            interval=1,      # Every 1 hour
            backupCount=2,   # Keep 2 backups
            encoding='utf-8'
        )
        file_handler.setLevel(logging.INFO)
        file_handler.setFormatter(json_formatter)

        logging.basicConfig(
            level=log_level,
            handlers=[console_handler, file_handler]
        )
```

Why hourly rotation? CloudWatch Agent's `auto_removal` only deletes complete files. With daily rotation, you'd have up to 24 hours of logs accumulating. Hourly rotation minimizes disk usage to just 1-2 hours of logs at any time.

**Important**: Do not use minute-level rotation (`when='M'`). Fast rotation intervals cause timing issues where CloudWatch Agent cannot properly track file inodes during rotation, leading to log loss or incorrect file deletion. AWS documentation recommends hourly or longer rotation intervals for reliable `auto_removal` behavior.

Using the logger is straightforward. Extra fields are automatically handled:

```python
import logging
from flask import Flask
from lib.logger import setup_logging
from settings import APP, PROCESS, LOG_PATH, ENVIRONMENT

app = Flask(__name__)
logger = logging.getLogger(__name__)

setup_logging(
    env=ENVIRONMENT,
    app=APP,
    process=PROCESS,
    log_path=LOG_PATH
)

@app.get("/")
def health():
    logger.info("GET /", extra=dict(
        user_id=123,
        response_time_ms=45
    ))
    return {'status': 'ok'}
```

**Console output:**
```
2025-12-13 12:30:45 [INFO] app - GET / | user_id=123 response_time_ms=45
```

**JSON output (CloudWatch):**
```json
{
  "@timestamp": "2025-12-13T12:30:45.123456",
  "level": "INFO",
  "logger": "app",
  "app": "cw_demo",
  "process": "cw_demo",
  "message": "GET /",
  "user_id": 123,
  "response_time_ms": 45
}
```

The CloudWatch Agent uses `auto_removal` to delete rotated files automatically:

```json
{
  "agent": {
    "debug": false
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/logs/*.log*",
            "log_group_name": "${LOG_GROUP_NAME}",
            "log_stream_name": "{hostname}",
            "auto_removal": true
          }
        ]
      }
    }
  }
}
```

The wildcard pattern `/logs/*.log*` matches any log file and its rotations (e.g., `app.log`, `cw.log`, `worker.log` and their rotated versions like `app.log.2025-12-13_12`). This allows different applications to use different log file names based on their `app_id`.

The `LOG_GROUP_NAME` environment variable is injected at runtime by the entrypoint script. If not provided, it defaults to `/app/logs`.

The application runs alongside CloudWatch Agent with a shared volume:

```yaml
services:
  api:
    build:
      context: .
    volumes:
      - logs_volume:/src/logs
    environment:
      - ENVIRONMENT=production
      - PROCESS_ID=api
    ports:
      - 5000:5000
    command: gunicorn -w 1 app:app -b 0.0.0.0:5000 --timeout 180

  cloudwatch-agent:
    build:
      context: .docker/cw
    volumes:
      - logs_volume:/logs
    environment:
      - LOG_GROUP_NAME=/mi-proyecto/app  # Optional: defaults to /app/logs if not set

volumes:
  logs_volume:
```

The CloudWatch Agent container's entrypoint script handles the `LOG_GROUP_NAME` variable with a default value:

```bash
#!/bin/sh
set -e

# Set default value for LOG_GROUP_NAME if not provided
LOG_GROUP_NAME=${LOG_GROUP_NAME:-/app/logs}

# Replace LOG_GROUP_NAME environment variable in the config file
sed "s|\${LOG_GROUP_NAME}|${LOG_GROUP_NAME}|g" \
    /opt/aws/amazon-cloudwatch-agent/bin/config.template.json > /opt/aws/amazon-cloudwatch-agent/bin/default_linux_config.json

echo "CloudWatch Agent starting with LOG_GROUP_NAME=${LOG_GROUP_NAME}"

# Start the CloudWatch Agent
exec /opt/aws/amazon-cloudwatch-agent/bin/start-amazon-cloudwatch-agent
```

This ensures the agent always has a valid log group name, even if the environment variable is not explicitly set.

When using CloudWatch Insights, remember to use the actual field names from your JSON structure:

```sql
fields @timestamp, level, logger, message, user_id, response_time_ms
| filter level = "ERROR"
| sort @timestamp desc
| limit 100
```

This logging architecture uses sidecar patterns to decouple application logic from logging concerns, ensuring robust, production-ready logging with minimal disk usage and automatic log management via AWS CloudWatch.

