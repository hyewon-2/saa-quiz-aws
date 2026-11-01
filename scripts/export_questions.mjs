// saa-quiz 저장소(GitHub Pages 버전)의 문제 데이터(data/*.js)를 API용 JSON으로 변환한다.
// 사용법: node scripts/export_questions.mjs  →  app/data/questions.json
//
// 원본은 브라우저용 스크립트라 `window.QB.push({...})` 형태다. 격리된 vm 컨텍스트에서 실행해 배열만 꺼낸다.
import { writeFile, mkdir } from "node:fs/promises";
import vm from "node:vm";

const RAW = "https://raw.githubusercontent.com/hyewon-2/saa-quiz/main";
const OUT = new URL("../app/data/questions.json", import.meta.url);

// index.html이 불러오는 순서 그대로 문제 파일 목록을 가져온다 (concepts.js 등 문제가 아닌 파일은 제외).
const html = await (await fetch(`${RAW}/index.html`)).text();
const files = [...html.matchAll(/<script src="(data\/[^"]+\.js)"/g)]
  .map((m) => m[1])
  .filter((f) => !f.endsWith("concepts.js"));

const sandbox = { window: {} };
vm.createContext(sandbox);
for (const file of files) {
  const res = await fetch(`${RAW}/${file}`);
  if (!res.ok) throw new Error(`${file}: HTTP ${res.status}`);
  // 원본은 `window.QB = window.QB || []; QB.push(...)`라서 QB를 전역으로 노출해 준다.
  vm.runInContext(`var QB = window.QB = window.QB || [];\n${await res.text()}`, sandbox, { timeout: 2000 });
}

const questions = sandbox.window.QB.map((q) => ({
  id: q.id,
  category: q.cat,
  domain: q.domain,
  services: q.svc ?? [],
  question: q.q,
  choices: q.opts,
  answer: q.ans,
  explanation: q.exp,
  tip: q.tip ?? null,
}));

const ids = new Set(questions.map((q) => q.id));
if (ids.size !== questions.length) throw new Error("duplicate question id");

await mkdir(new URL(".", OUT), { recursive: true });
await writeFile(OUT, JSON.stringify(questions, null, 1) + "\n");
console.log(`${files.length} files -> ${questions.length} questions -> app/data/questions.json`);
