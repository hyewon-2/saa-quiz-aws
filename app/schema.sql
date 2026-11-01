-- 앱이 시작될 때마다 실행된다. IF NOT EXISTS라서 여러 번 실행해도 안전하다.

CREATE TABLE IF NOT EXISTS questions (
    id          TEXT PRIMARY KEY,          -- 예: cmp-01
    category    TEXT NOT NULL,             -- compute, storage, ...
    domain      TEXT NOT NULL,             -- 시험 영역: secure, resilient, performance, cost
    services    TEXT[] NOT NULL,
    question    TEXT NOT NULL,
    choices     JSONB NOT NULL,
    answer      INT[] NOT NULL,            -- 정답 보기 번호(0부터). 정답이 2개인 문제도 있다.
    explanation TEXT NOT NULL,
    tip         TEXT
);

-- 풀이 기록. 전체 사용자 통계(문제별 정답률, 많이 틀리는 문제)의 원본 데이터.
-- 주의: question_id에 인덱스를 일부러 만들지 않았다. 부하 테스트(장애 시나리오)에서 느린 쿼리를 찾고 개선하기 위해서다.
CREATE TABLE IF NOT EXISTS attempts (
    id          BIGSERIAL PRIMARY KEY,
    question_id TEXT NOT NULL REFERENCES questions (id),
    chosen      INT[] NOT NULL,
    is_correct  BOOLEAN NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
