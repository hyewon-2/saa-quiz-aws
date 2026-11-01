from app import db


def submit(client, question_id, chosen):
    return client.post("/attempts", json={"question_id": question_id, "chosen": chosen})


def test_index_returns_version(client):
    res = client.get("/")
    assert res.status_code == 200
    assert "version" in res.get_json()


def test_health_does_not_touch_db(client):
    res = client.get("/health")
    assert res.status_code == 200
    assert res.get_json() == {"status": "ok"}


def test_health_db(client):
    assert client.get("/health/db").get_json()["database"] == "ok"


def test_all_questions_loaded(client):
    with db.connection() as conn:
        assert conn.execute("SELECT count(*) FROM questions").fetchone()[0] == 800


def test_random_question_hides_answer(client):
    q = client.get("/questions/random?category=networking").get_json()
    assert q["category"] == "networking"
    assert "answer" not in q and "explanation" not in q
    assert q["answer_count"] >= 1


def test_random_question_rejects_unknown_category(client):
    assert client.get("/questions/random?category=nope").status_code == 400


def test_attempt_is_graded_by_server(client):
    # cmp-01의 정답은 1번 보기다.
    right = submit(client, "cmp-01", [1])
    assert right.status_code == 201
    assert right.get_json()["correct"] is True

    wrong = submit(client, "cmp-01", [0])
    assert wrong.get_json()["correct"] is False
    assert wrong.get_json()["answer"] == [1]


def test_multi_answer_question_needs_all_answers(client):
    with db.connection() as conn:
        qid, answer = conn.execute(
            "SELECT id, answer FROM questions WHERE cardinality(answer) = 2 LIMIT 1"
        ).fetchone()
    assert submit(client, qid, answer[:1]).get_json()["correct"] is False
    assert submit(client, qid, list(reversed(answer))).get_json()["correct"] is True


def test_attempt_validation(client):
    assert submit(client, "no-such-id", [0]).status_code == 404
    assert client.post("/attempts", json={"question_id": "cmp-01"}).status_code == 400
    assert submit(client, "cmp-01", [True]).status_code == 400


def test_question_stats(client):
    for chosen in ([1], [1], [1], [0]):
        submit(client, "cmp-01", chosen)
    stats = client.get("/stats/questions/cmp-01").get_json()
    assert stats["attempts"] == 4
    assert stats["correct"] == 3
    assert stats["accuracy"] == 75.0


def test_question_stats_without_attempts(client):
    stats = client.get("/stats/questions/cmp-02").get_json()
    assert stats["attempts"] == 0
    assert stats["accuracy"] is None


def test_most_missed_ranks_lowest_accuracy_first(client):
    for _ in range(5):
        submit(client, "cmp-01", [0])  # 0% 정답
        submit(client, "cmp-02", [1])  # 100% 정답
    submit(client, "cmp-03", [9])  # 시도 1번뿐이라 순위에서 빠져야 한다

    ranking = client.get("/stats/most-missed?min_attempts=5").get_json()["questions"]
    assert [q["id"] for q in ranking] == ["cmp-01", "cmp-02"]
    assert ranking[0]["accuracy"] == 0.0
