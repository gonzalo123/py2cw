import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
ENVIRONMENT = os.getenv('ENVIRONMENT', 'production')

APP_ID = 'cw'
APP = 'cw_demo'
PROCESS = 'cw_demo'
LOG_PATH = BASE_DIR / 'logs' / 'app.log'
