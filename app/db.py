import json
import logging
import os
import threading
from pathlib import Path

from psycopg.types.json import Jsonb
from psycopg_pool import ConnectionPool

log = logging.getLogger(__name__)

APP_DIR = Path(__file__).parent

# 임의의 고정 숫자. 태스크 여러 개가 동시에 떠도 스키마 생성/문제 적재는 한 번에 하나만 실행되게 한다.
SCHEMA_LOCK_ID = 7_000_001

_pool = None
_pool_lock = threading.Lock()
_schema_ready = False


def _conninfo():
    # ECS에서는 DB_PASSWORD를 Secrets Manager에서 주입받는다 (infra/ecs.tf의 secrets).
    return (
        f"host={os.environ['DB_HOST']} port={os.environ.get('DB_PORT', '5432')} "
        f"dbname={os.environ['DB_NAME']} user={os.environ['DB_USER']} "
        f"password={os.environ['DB_PASSWORD']} "
        # DB에 연결되지 않을 때 요청이 오래 매달리지 않고 빨리 실패하게 한다.
        "connect_timeout=3"
    )


def get_pool():
    """gunicorn worker(프로세스)마다 하나씩, 첫 요청 때 만든다."""
    global _pool
    if _pool is None:
        with _pool_lock:
            if _pool is None:
                # open=False: 앱이 뜰 때 DB에 바로 연결하지 않는다. DB가 죽어 있어도 앱은 떠야 한다.
                _pool = ConnectionPool(_conninfo(), min_size=1, max_size=5, open=False, timeout=5)
                _pool.open(wait=False)
    return _pool


def connection():
    ensure_schema()
    return get_pool().connection()


def ensure_schema():
    """테이블을 만들고 문제 데이터를 넣는다. 프로세스마다 처음 한 번만 실행된다."""
    global _schema_ready
    if _schema_ready:
        return
    questions = json.loads((APP_DIR / "data" / "questions.json").read_text(encoding="utf-8"))
    with get_pool().connection() as conn:
        conn.execute("SELECT pg_advisory_xact_lock(%s)", (SCHEMA_LOCK_ID,))
        conn.execute((APP_DIR / "schema.sql").read_text(encoding="utf-8"))
        with conn.cursor() as cur:
            # 문제 내용이 바뀌었으면 덮어쓴다 (saa-quiz에서 문제를 고친 뒤 다시 배포하는 경우).
            cur.executemany(
                """
                INSERT INTO questions (id, category, domain, services, question, choices, answer, explanation, tip)
                VALUES (%(id)s, %(category)s, %(domain)s, %(services)s, %(question)s, %(choices)s,
                        %(answer)s, %(explanation)s, %(tip)s)
                ON CONFLICT (id) DO UPDATE SET
                    category = EXCLUDED.category, domain = EXCLUDED.domain, services = EXCLUDED.services,
                    question = EXCLUDED.question, choices = EXCLUDED.choices, answer = EXCLUDED.answer,
                    explanation = EXCLUDED.explanation, tip = EXCLUDED.tip
                """,
                [{**q, "choices": Jsonb(q["choices"])} for q in questions],
            )
    _schema_ready = True
    log.info("schema ready, %d questions loaded", len(questions))
