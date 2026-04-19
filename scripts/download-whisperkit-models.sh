#!/bin/bash
# 预下载 WhisperKit large-v3 模型文件（约 2.9GB）和 tokenizer 文件
# 使用方法：./scripts/download-whisperkit-models.sh
# 可选环境变量：HF_ENDPOINT=https://hf-mirror.com（国内镜像）

set -e

ENDPOINT="${HF_ENDPOINT:-https://huggingface.co}"
DOCS_DIR="$HOME/Documents/huggingface"
MODEL_DIR="$DOCS_DIR/models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3"
TOKENIZER_DIR="$DOCS_DIR/models/openai/whisper-large-v3"

echo "=== WhisperKit 模型预下载脚本 ==="
echo "HuggingFace 端点: $ENDPOINT"
echo ""

# 下载 tokenizer 文件（小文件，几秒完成）
echo ">>> 1/2 下载 tokenizer 文件..."
mkdir -p "$TOKENIZER_DIR"
TOKENIZER_FILES="tokenizer.json tokenizer_config.json vocab.json merges.txt special_tokens_map.json"
for f in $TOKENIZER_FILES; do
    if [ -f "$TOKENIZER_DIR/$f" ]; then
        echo "  ✓ $f 已存在，跳过"
    else
        echo "  下载 $f..."
        curl -fL --progress-bar "$ENDPOINT/openai/whisper-large-v3/resolve/main/$f" \
             -o "$TOKENIZER_DIR/$f"
        echo "  ✓ $f"
    fi
done

# 下载 WhisperKit CoreML 模型文件（大文件，约 2.9GB）
echo ""
echo ">>> 2/2 下载 WhisperKit CoreML 模型文件（约 2.9GB）..."
mkdir -p "$MODEL_DIR"
WHISPERKIT_REPO="argmaxinc/whisperkit-coreml"
MODEL_VARIANT="openai_whisper-large-v3"
MODEL_FILES="config.json generation_config.json"

for f in $MODEL_FILES; do
    if [ -f "$MODEL_DIR/$f" ]; then
        echo "  ✓ $f 已存在，跳过"
    else
        echo "  下载 $f..."
        curl -fL --progress-bar "$ENDPOINT/$WHISPERKIT_REPO/resolve/main/$MODEL_VARIANT/$f" \
             -o "$MODEL_DIR/$f"
        echo "  ✓ $f"
    fi
done

# 下载 mlmodelc 目录中的大权重文件
MLMODELCS="AudioEncoder.mlmodelc MelSpectrogram.mlmodelc TextDecoder.mlmodelc"
MLMODELC_FILES="weights/weight.bin metadata.json model.mil model.mlmodel coremldata.bin analytics/coremldata.bin"

for mlmodelc in $MLMODELCS; do
    echo ""
    echo "  下载 $mlmodelc..."
    for file in $MLMODELC_FILES; do
        local_path="$MODEL_DIR/$mlmodelc/$file"
        remote_path="$MODEL_VARIANT/$mlmodelc/$file"
        if [ -f "$local_path" ]; then
            echo "    ✓ $file 已存在，跳过"
            continue
        fi
        mkdir -p "$(dirname "$local_path")"
        url="$ENDPOINT/$WHISPERKIT_REPO/resolve/main/$remote_path"
        http_code=$(curl -fL --progress-bar -o "$local_path" -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        if [ -f "$local_path" ] && [ -s "$local_path" ]; then
            echo "    ✓ $file"
        else
            rm -f "$local_path"
            echo "    - $file (不存在或跳过)"
        fi
    done
done

echo ""
echo "=== 下载完成 ==="
echo "模型目录: $MODEL_DIR"
echo "Tokenizer 目录: $TOKENIZER_DIR"
echo ""
echo "现在可以启动 App，切换到 WhisperKit 实验性模式，模型将从本地加载（约 30 秒）"
