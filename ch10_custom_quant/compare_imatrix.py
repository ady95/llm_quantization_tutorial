#!/usr/bin/env python3
"""두 imatrix 파일을 텐서 단위로 비교한다. 각 텐서의 열별 중요도(누적 제곱합 / 카운트)를 정규화해 코사인 유사도와
상위 10% 열의 겹침 비율을 계산하고, 텐서군·층별로 요약한다.
사용: python3 compare_imatrix.py A.gguf B.gguf [--llama <llama.cpp>] [--top 20]
"""
import argparse, collections, pathlib, re, sys
import numpy as np
ap = argparse.ArgumentParser(); ap.add_argument("a"); ap.add_argument("b")
ap.add_argument("--llama", default=str(pathlib.Path.home() / "work/llama.cpp")); ap.add_argument("--top", type=int, default=15)
args = ap.parse_args(); sys.path.insert(0, str(pathlib.Path(args.llama) / "gguf-py"))
from gguf import GGUFReader

def load(path):
    r = GGUFReader(path); sums, counts = {}, {}
    for t in r.tensors:
        name = t.name
        if name.endswith(".in_sum2"): sums[name[:-8]] = np.array(t.data, dtype=np.float64).reshape(-1)
        elif name.endswith(".counts"): counts[name[:-7]] = np.array(t.data, dtype=np.float64).reshape(-1)
    out = {}
    for k, s in sums.items():
        c = counts.get(k); v = s / c.mean() if c is not None and c.mean() > 0 else s
        out[k] = v
    return out

A, B = load(args.a), load(args.b)
common = sorted(set(A) & set(B))
print(f"A: {len(A)} tensors, B: {len(B)} tensors, common: {len(common)}")
rows = []
for k in common:
    a, b = A[k], B[k]
    if a.shape != b.shape: continue
    cos = float(a @ b / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-30))
    n = max(1, len(a) // 10)
    ta, tb = set(np.argsort(a)[-n:]), set(np.argsort(b)[-n:])
    rows.append((k, cos, len(ta & tb) / n))
def group(k):
    m = re.match(r"blk\.(\d+)\.(.+)\.weight", k)
    return (int(m.group(1)), m.group(2)) if m else (-1, k)
by_kind = collections.defaultdict(list)
for k, cos, ov in rows: by_kind[group(k)[1]].append((cos, ov))
print("\n텐서군별 평균 (코사인 유사도 / 상위10% 열 겹침):")
for kind, v in sorted(by_kind.items(), key=lambda kv: np.mean([x[0] for x in kv[1]])):
    print(f"  {kind:22s} n={len(v):3d}  cos={np.mean([x[0] for x in v]):.3f}  top10%={np.mean([x[1] for x in v]):.2f}")
by_layer = collections.defaultdict(list)
for k, cos, ov in rows:
    L = group(k)[0]
    if L >= 0: by_layer[L // 8 * 8].append(cos)
print("\n층 구간별 평균 코사인:")
for L in sorted(by_layer): print(f"  blk.{L:2d}-{L+7:2d}: {np.mean(by_layer[L]):.3f}")
print(f"\n가장 다른 텐서 {args.top}개:")
for k, cos, ov in sorted(rows, key=lambda r: r[1])[:args.top]: print(f"  {k:36s} cos={cos:.3f} top10%={ov:.2f}")
print(f"\n전체 평균 cos={np.mean([r[1] for r in rows]):.3f}, 중앙값={np.median([r[1] for r in rows]):.3f}")
