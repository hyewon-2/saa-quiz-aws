import os

import pytest

# 로컬은 docker compose의 db, CI는 GitHub Actions의 postgres 서비스에 연결한다. 값은 둘이 같다.
os.environ.setdefault("DB_HOST", "localhost")
os.environ.setdefault("DB_NAME", "quiz")
os.environ.setdefault("DB_USER", "quiz")
os.environ.setdefault("DB_PASSWORD", "localdev")

from app import db  # noqa: E402  (환경변수를 먼저 정한 뒤 import 해야 한다)
from app.main import app  # noqa: E402


def pytest_sessionfinish(session, exitstatus):
    # 연결 풀을 직접 닫아 준다. 안 닫으면 인터프리터 종료 중에 풀 스레드를 정리하려다 경고가 난다.
    if db._pool is not None:
        db._pool.close()


@pytest.fixture
def client():
    app.config["TESTING"] = True
    return app.test_client()


@pytest.fixture(autouse=True)
def clean_attempts():
    # 테스트끼리 풀이 기록이 섞이지 않게 매번 비운다. 문제 데이터는 그대로 둔다.
    with db.connection() as conn:
        conn.execute("TRUNCATE attempts RESTART IDENTITY")
    yield
