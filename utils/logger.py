import logging
import json
import sys
from datetime import datetime
from config.settings import LOG_LEVEL


class JsonFormatter(logging.Formatter):
    def format(self, record):
        log = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "level": record.levelname,
            "service": "severus-ai",
            "logger": record.name,
            "message": record.getMessage(),
        }

        # Optional extras (safe)
        if record.exc_info:
            log["exception"] = self.formatException(record.exc_info)

        return json.dumps(log)


def setup_logger(name: str):
    logger = logging.getLogger(name)
    logger.setLevel(LOG_LEVEL)

    # IMPORTANT: prevent duplicate handlers
    if not logger.handlers:
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(JsonFormatter())
        logger.addHandler(handler)

    # Prevent double logging via root
    logger.propagate = False

    return logger
