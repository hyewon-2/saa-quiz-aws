import json
import logging
import os
import socket
from datetime import UTC, datetime

# 로그 레코드에 기본으로 들어 있는 속성. 이것 말고 extra={...}로 넘긴 값만 JSON 필드로 꺼낸다.
_STANDARD_ATTRS = set(vars(logging.makeLogRecord({}))) | {"message", "asctime", "taskName"}


class JsonFormatter(logging.Formatter):
    """한 줄에 JSON 하나. CloudWatch Logs Insights가 필드를 자동으로 인식한다 (예: filter status >= 500)."""

    def __init__(self):
        super().__init__()
        self.static = {"version": os.environ.get("APP_VERSION", "local"), "host": socket.gethostname()}

    def format(self, record):
        entry = {
            "timestamp": datetime.fromtimestamp(record.created, UTC).isoformat(timespec="milliseconds"),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            **self.static,
        }
        entry.update({k: v for k, v in vars(record).items() if k not in _STANDARD_ATTRS})
        if record.exc_info:
            entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(entry, ensure_ascii=False, default=str)


def configure_logging():
    handler = logging.StreamHandler()  # stderr → 컨테이너 로그 → awslogs 드라이버 → CloudWatch Logs
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(logging.INFO)
