#!/usr/bin/env bash
# 6장: 환경 변수 실험용 사용자 권한 Ollama 인스턴스. 시스템 서비스(11434)와 분리해 다른 포트에서 띄운다.
# 사용 예:
#   bash start_ollama_instance.sh                                  # 기본: 포트 11435, f16 KV
#   OLLAMA_KV_CACHE_TYPE=q8_0 bash start_ollama_instance.sh        # KV 캐시 q8_0 (flash attention 자동)
#   CUDA_VISIBLE_DEVICES=1 bash start_ollama_instance.sh           # GPU 두 장 중 두 번째만 (Vulkan 경로도 함께 차단)
# 모델 저장소가 비어 있으므로 별도로 pull 하거나, 서비스 저장소의 manifests/blobs를 복사해 재사용한다(책 2-1).
set -eu
export OLLAMA_HOST=${OLLAMA_HOST:-127.0.0.1:11435}
export OLLAMA_MODELS=${OLLAMA_MODELS:-$HOME/ollama-store}
export OLLAMA_NUM_PARALLEL=${OLLAMA_NUM_PARALLEL:-1}
export OLLAMA_KEEP_ALIVE=${OLLAMA_KEEP_ALIVE:-10m}
export OLLAMA_VULKAN=${OLLAMA_VULKAN:-false}
export OLLAMA_NO_CLOUD=1
mkdir -p "$OLLAMA_MODELS"
echo "Ollama 인스턴스: $OLLAMA_HOST, 저장소 $OLLAMA_MODELS, KV=${OLLAMA_KV_CACHE_TYPE:-f16}, GPU=${CUDA_VISIBLE_DEVICES:-all}"
exec ollama serve
