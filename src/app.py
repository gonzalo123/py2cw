import logging
import random
from datetime import datetime

from flask import Flask, request

from lib.logger import setup_logging
from settings import APP, PROCESS, LOG_PATH, ENVIRONMENT

logger = logging.getLogger(__name__)

app = Flask(__name__)

setup_logging(
    env=ENVIRONMENT,
    app=APP,
    process=PROCESS,
    log_path=LOG_PATH)

for logger_name in ["werkzeug"]:
    logging.getLogger(logger_name).setLevel(logging.CRITICAL)


@app.get("/")
def health():
    logger.info(f"GET /", extra=dict(key1=datetime.now(), key2='xx'))
    return {'status': 'ok'}


@app.get("/generate-logs")
def generate_logs():
    count = request.args.get('count', default=10, type=int)
    count = min(count, 100)

    log_levels = [
        (logger.debug, "DEBUG"),
        (logger.info, "INFO"),
        (logger.warning, "WARNING"),
        (logger.error, "ERROR"),
    ]

    actions = ["login", "logout", "purchase", "search", "upload", "download", "delete", "update"]
    statuses = ["success", "failure", "timeout", "pending"]
    users = [f"user_{i}" for i in range(1, 11)]
    endpoints = ["/api/users", "/api/products", "/api/orders", "/api/payments", "/api/reports"]

    generated = []

    for i in range(count):
        log_func, level_name = random.choice(log_levels)
        action = random.choice(actions)
        status = random.choice(statuses)
        user_id = random.choice(users)
        endpoint = random.choice(endpoints)
        duration_ms = random.randint(10, 5000)
        status_code = random.choice([200, 201, 400, 401, 403, 404, 500, 503])

        message = f"{action.capitalize()} operation {status}"

        extra_fields = {
            "user_id": user_id,
            "action": action,
            "status": status,
            "endpoint": endpoint,
            "duration_ms": duration_ms,
            "status_code": status_code,
            "request_id": f"req_{random.randint(1000, 9999)}",
            "ip_address": f"192.168.{random.randint(1, 255)}.{random.randint(1, 255)}"
        }

        log_func(message, extra=extra_fields)
        generated.append({
            "level": level_name,
            "message": message,
            "fields": extra_fields
        })

    logger.info(
        f"Generated {count} random logs",
        extra={"total_logs": count, "endpoint": "/generate-logs"}
    )

    return {
        'status': 'ok',
        'logs_generated': count,
        'sample': generated[:5]
    }
