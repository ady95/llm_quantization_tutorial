#!/usr/bin/env python3
"""GGUF 파일의 텐서별 양자화 타입을 센다. 배포본과 직접 만든 파일의 혼합 정밀도 구성을 비교할 때 쓴다.
사용: python3 tensor_types.py <파일.gguf> [--llama <llama.cpp 경로>] [--list 패턴]
  --list 패턴 : 이름이 패턴(정규식)에 맞는 텐서를 타입과 함께 나열 (예: --list 'blk\.(0|3|63)\.')
"""
import argparse, collections, re, sys, pathlib
ap = argparse.ArgumentParser(); ap.add_argument("gguf"); ap.add_argument("--llama", default=str(pathlib.Path.home() / "work/llama.cpp")); ap.add_argument("--list")
a = ap.parse_args(); sys.path.insert(0, str(pathlib.Path(a.llama) / "gguf-py"))
from gguf import GGUFReader
r = GGUFReader(a.gguf); c = collections.Counter(t.tensor_type.name for t in r.tensors)
total = sum(t.n_bytes for t in r.tensors)
print(f"{len(r.tensors)} tensors, {total/2**20:,.0f} MiB")
for k, v in sorted(c.items(), key=lambda kv: -kv[1]):
    mb = sum(t.n_bytes for t in r.tensors if t.tensor_type.name == k) / 2**20
    print(f"{v:5d}  {k:8s} {mb:10,.1f} MiB")
if a.list:
    pat = re.compile(a.list)
    for t in r.tensors:
        if pat.search(t.name): print(f"  {t.name:40s} {t.tensor_type.name:8s} {t.n_bytes/2**20:8.1f} MiB")
