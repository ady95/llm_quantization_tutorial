#!/usr/bin/env python3
"""10장 캘리브레이션 텍스트 구성.

업무 텍스트(8장 평가 사례의 입력·근거·프롬프트)와 일반 텍스트(wikitext-2 train 일부)를 섞는다.
업무 텍스트만 쓰면 imatrix가 그 분포에 과적합되어 일반 능력이 떨어질 수 있고,
일반 텍스트만 쓰면 공개 배포본과 다를 것이 없다. 비율은 --work-repeat 와 --general-tokens 로 조절한다.

사용: python3 build_calib.py --bmt ../ch08_bmt --general wiki.train.raw --out calib-work.txt
"""
import argparse, json, random, pathlib

def work_texts(bmt: pathlib.Path):
    out = []
    for f in ["cases.json", "holdout.json"]:
        for c in json.loads((bmt / f).read_text(encoding="utf-8")):
            i = c["input"]
            parts = [i.get("task", "")] + [e.get("text", "") for e in i.get("evidence", [])]
            out.append("\n".join(p for p in parts if p))
    for f in ["prompt_v2.txt"]:
        p = bmt / f
        if p.exists(): out.append(p.read_text(encoding="utf-8"))
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bmt", required=True); ap.add_argument("--general", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--work-repeat", type=int, default=3, help="업무 텍스트 반복 횟수(순서를 섞어 반복)")
    ap.add_argument("--general-chars", type=int, default=400_000, help="일반 텍스트에서 가져올 문자 수")
    ap.add_argument("--seed", type=int, default=0)
    a = ap.parse_args(); rnd = random.Random(a.seed)
    work = work_texts(pathlib.Path(a.bmt))
    gen = pathlib.Path(a.general).read_text(encoding="utf-8", errors="ignore")
    paras = [p.strip() for p in gen.split("\n \n") if len(p.strip()) > 200]
    rnd.shuffle(paras)
    gen_sel, n = [], 0
    for p in paras:
        if n >= a.general_chars: break
        gen_sel.append(p); n += len(p)
    blocks = []
    for _ in range(a.work_repeat):
        w = work[:]; rnd.shuffle(w); blocks += w
    blocks += gen_sel; rnd.shuffle(blocks)
    text = "\n\n".join(blocks) + "\n"
    pathlib.Path(a.out).write_text(text, encoding="utf-8")
    wc = sum(len(b) for b in work) * a.work_repeat
    print(f"work: {len(work)} texts x{a.work_repeat} = {wc:,} chars; general: {len(gen_sel)} paragraphs = {n:,} chars; total {len(text):,} chars -> {a.out}")

if __name__ == "__main__":
    main()
