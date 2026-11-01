import logging
import os
import socket

import psycopg
from flask import Flask, jsonify, request
from psycopg.rows import dict_row
from psycopg_pool import PoolTimeout

from app import db

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger(__name__)

app = Flask(__name__)
app.json.ensure_ascii = False  # 한글 문제를 \uXXXX 대신 그대로 보여 준다.
# charset을 명시한다. 없으면 Windows PowerShell 5.1의 Invoke-RestMethod가 ISO-8859-1로 읽어서 한글이 깨진다.
app.json.mimetype = "application/json; charset=utf-8"

# CI/CD에서 이미지 빌드 시 커밋 SHA를 넣어 준다. 배포 후 새 버전이 떴는지 확인하는 용도.
APP_VERSION = os.environ.get("APP_VERSION", "local")

CATEGORIES = {"compute", "storage", "database", "networking", "security", "integration", "analytics", "management"}


def error(status, message):
    return jsonify(error=message), status


@app.errorhandler(psycopg.OperationalError)
@app.errorhandler(PoolTimeout)
def db_unavailable(exc):
    # DB 연결 실패는 500이 아니라 503으로 응답해서, 알람과 로그에서 "앱 버그"와 구분되게 한다.
    log.error("database unavailable: %s", exc)
    return error(503, "database unavailable")


@app.get("/")
def index():
    return jsonify(
        message="SAA quiz statistics API",
        version=APP_VERSION,
        # ECS에서 태스크가 여러 개일 때 어느 컨테이너가 응답했는지 보여 준다.
        host=socket.gethostname(),
    )


@app.get("/health")
def health():
    # ALB 대상 그룹 헬스체크 경로. 일부러 DB를 확인하지 않는다.
    # DB까지 확인하면 DB가 잠깐 끊겼을 때 ALB가 모든 태스크를 비정상으로 보고 계속 교체해 버린다.
    return jsonify(status="ok")


@app.get("/health/db")
def health_db():
    with db.connection() as conn:
        conn.execute("SELECT 1")
    return jsonify(status="ok", database="ok")


@app.get("/questions/random")
def random_question():
    category = request.args.get("category")
    if category and category not in CATEGORIES:
        return error(400, f"unknown category: {category}")
    with db.connection() as conn, conn.cursor(row_factory=dict_row) as cur:
        # 정답과 해설은 빼고 보낸다. 답을 제출하면 POST /attempts 응답으로 알려 준다.
        cur.execute(
            """
            SELECT id, category, domain, services, question, choices, cardinality(answer) AS answer_count
            FROM questions
            WHERE %(category)s::text IS NULL OR category = %(category)s
            ORDER BY random()
            LIMIT 1
            """,
            {"category": category},
        )
        return jsonify(cur.fetchone())


@app.post("/attempts")
def create_attempt():
    body = request.get_json(silent=True) or {}
    question_id = body.get("question_id")
    chosen = body.get("chosen")
    if not isinstance(question_id, str) or not isinstance(chosen, list) or not chosen:
        return error(400, "question_id (string) and chosen (non-empty list of choice indexes) are required")
    if not all(isinstance(c, int) and not isinstance(c, bool) for c in chosen):
        return error(400, "chosen must contain integers only")

    with db.connection() as conn, conn.cursor(row_factory=dict_row) as cur:
        cur.execute("SELECT answer, explanation, tip FROM questions WHERE id = %s", (question_id,))
        q = cur.fetchone()
        if q is None:
            return error(404, f"question not found: {question_id}")
        # 채점은 서버가 한다. 클라이언트가 보낸 정답 여부를 믿으면 통계를 조작할 수 있다.
        is_correct = sorted(set(chosen)) == sorted(q["answer"])
        cur.execute(
            "INSERT INTO attempts (question_id, chosen, is_correct) VALUES (%s, %s, %s) RETURNING id",
            (question_id, chosen, is_correct),
        )
        attempt_id = cur.fetchone()["id"]
    return jsonify(
        id=attempt_id, correct=is_correct, answer=q["answer"], explanation=q["explanation"], tip=q["tip"]
    ), 201


@app.get("/stats/questions/<question_id>")
def question_stats(question_id):
    with db.connection() as conn, conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT q.id, q.category, q.domain,
                   count(a.id) AS attempts,
                   count(a.id) FILTER (WHERE a.is_correct) AS correct,
                   round(avg(a.is_correct::int) * 100, 1)::float AS accuracy
            FROM questions q
            LEFT JOIN attempts a ON a.question_id = q.id
            WHERE q.id = %s
            GROUP BY q.id
            """,
            (question_id,),
        )
        row = cur.fetchone()
    if row is None:
        return error(404, f"question not found: {question_id}")
    return jsonify(row)


@app.get("/stats/most-missed")
def most_missed():
    try:
        limit = min(int(request.args.get("limit", 10)), 50)
        min_attempts = max(int(request.args.get("min_attempts", 5)), 1)
    except ValueError:
        return error(400, "limit and min_attempts must be integers")

    with db.connection() as conn, conn.cursor(row_factory=dict_row) as cur:
        # 시도 횟수가 너무 적은 문제는 정답률이 들쭉날쭉하므로 min_attempts 이상만 순위에 넣는다.
        cur.execute(
            """
            SELECT a.question_id AS id, q.category, q.domain, left(q.question, 80) AS question,
                   count(*) AS attempts,
                   round(avg(a.is_correct::int) * 100, 1)::float AS accuracy
            FROM attempts a
            JOIN questions q ON q.id = a.question_id
            GROUP BY a.question_id, q.category, q.domain, q.question
            HAVING count(*) >= %s
            ORDER BY accuracy ASC, attempts DESC
            LIMIT %s
            """,
            (min_attempts, limit),
        )
        rows = cur.fetchall()
    return jsonify(min_attempts=min_attempts, questions=rows)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
