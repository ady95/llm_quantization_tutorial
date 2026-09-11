# 실측 기록 — 배포본 출처와 해시

책 5-1, 부록D의 기록표 원본입니다. Ollama에 등록된 뒤의 블롭 digest는 등록 시 GGUF가 재작성되어 파일 SHA-256과 다릅니다(책 5-3). 두 값을 모두 기록합니다.

| 이 책의 별칭 | 저장소 | 파일 | 크기(바이트) | 저장소 revision | 파일 SHA-256 | Ollama 블롭 digest (sha256-) |
|---|---|---|---:|---|---|---|
| qwen3.8:27b (Q4_K_M) | Ollama 라이브러리 | 매니페스트 22130167c4c2 | 16,810,000,000 (약) | - | - | f5f1dd8920d417aac2718b0bda3403da274301efdd6760b4f0f4b864ff2ad57d (가중치), ac3714bfdddeca31351f2752bf1a63f266f4df87c0b68c895e44945ca704448e (비전 프로젝터) |
| qwen27b-ud-iq3xxs | unsloth/Qwen3.8-27B-GGUF | Qwen3.8-27B-UD-IQ3_XXS.gguf | 10,934,860,704 | 4ca720788d1e01f1bff70c033e0d0028fd02e502 | c0b7c3038681ed2e3040456c1dd45f9858b6c2290bed172c70388a94874f3eee | 85cb2e467bb884838bb3a9d6f69abd1399f46b33d97fd77d3efa8a2d568df30a |
| qwen27b-gsq-iq3xxs | ISTA-DASLab/Qwen3.8-27B-GSQ-RCO-GGUF | Qwen3.8-27B-GSQ-RCO-IQ3_XXS.gguf | 10,094,357,632 | d562806dbafae37109975e970aae91b43e73b440 | fdfcb6a29b11188956dfbfd904223588a6c1b77eb250c3e8a36e1bd269df91f7 | 32e99c0670291d1b858cca1d43d641ebe0d2ed7273a8ef4e96c1e695d79e806f |
| qwen27b-ad-iq2xs | AtomicChat/Qwen3.8-27B-GGUF | Qwen3.8-27B-AD-IQ2_XS.gguf | 9,889,846,752 | ca10ebceb1887be9d33b838770a36b39d75a8a4c (2026-09-11 main) | a437190b719a4f1498cb54120d73a97b595fcfa0c263bc0753cc9c19942e82c5 | 515c37b6e59fefb2b7fc1ed116cc08c8bce8a482cfb5fbe63ef0fea62498cce2 |

등록에 쓴 Modelfile (세 HF 배포본 공통):

```
FROM <파일 경로>
PARAMETER num_ctx 8192
PARAMETER num_batch 512
PARAMETER num_thread 8
PARAMETER temperature 1.0
PARAMETER top_k 20
PARAMETER top_p 0.95
PARAMETER min_p 0
```

TEMPLATE은 적지 않아 GGUF 내장 채팅 템플릿이 그대로 쓰였습니다.

## 소프트웨어 버전

| 소프트웨어 | 버전 |
|---|---|
| Ollama | 0.34.0 |
| OpenCode | 1.18.25 (24GB 장비), 1.17.11 (12GB 장비) |
| llama.cpp | 커밋 8ea2902 (2026-09-11) |
| Python | 3.10.12, PyYAML 5.4.1 |
| NVIDIA 드라이버 | 580 (24GB), 535 (12GB, Vulkan 백엔드) |
