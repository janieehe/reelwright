#!/usr/bin/env bash
# 把本地视频变成灵小兔能「看」的素材：ffmpeg 抽帧 + whisper 转写字幕。
# 用法：bash scripts/video_to_frames_transcript.sh <视频文件> [--fps 1] [--model small]
# 产出：<视频名>.analysis/ 下 meta.txt、frames/*.jpg、transcript.srt、transcript.txt
set -euo pipefail

VIDEO=""
FPS="1"
MODEL="small"   # 仅 openai-whisper 用：tiny/base/small/medium/large；mlx_whisper 用自带默认模型

while [ $# -gt 0 ]; do
  case "$1" in
    --fps)    FPS="$2";  shift 2 ;;
    --model)  MODEL="$2"; shift 2 ;;
    --check|check)
      echo "检查拆本地视频需要的工具："
      for t in ffmpeg ffprobe mlx_whisper whisper; do
        if command -v "$t" >/dev/null 2>&1; then echo "  ✅ $t → $(command -v "$t")"; else echo "  ❌ $t → 未安装"; fi
      done
      echo
      echo "缺 ffmpeg：brew install ffmpeg"
      echo "缺 whisper：Apple Silicon 推荐 brew install mlx-whisper；通用 pip install -U openai-whisper"
      exit 0 ;;
    -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
    *) VIDEO="$1"; shift ;;
  esac
done

if [ -z "$VIDEO" ]; then
  echo "用法：bash scripts/video_to_frames_transcript.sh <视频文件> [--fps 1] [--model small]"
  exit 1
fi
[ -f "$VIDEO" ] || { echo "找不到文件：$VIDEO"; exit 1; }

command -v ffmpeg  >/dev/null 2>&1 || { echo "❌ 缺少 ffmpeg：brew install ffmpeg"; exit 1; }
command -v ffprobe >/dev/null 2>&1 || { echo "❌ 缺少 ffprobe（随 ffmpeg 一起装）"; exit 1; }

WHISPER=""
command -v mlx_whisper >/dev/null 2>&1 && WHISPER="mlx_whisper"
[ -z "$WHISPER" ] && command -v whisper >/dev/null 2>&1 && WHISPER="whisper"

BASE="$(basename "$VIDEO")"
NAME="${BASE%.*}"
OUT="${NAME}.analysis"
mkdir -p "$OUT/frames"

# 1. 元信息
DURATION="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$VIDEO" | cut -d. -f1)"
RES="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$VIDEO")"
printf '视频：%s\n时长：%s 秒\n分辨率：%s\n抽帧间隔：%s 秒/帧\n' "$BASE" "$DURATION" "$RES" "$FPS" > "$OUT/meta.txt"
echo "✅ 元信息：$OUT/meta.txt"

# 2. 抽帧
echo "抽帧中（$FPS 秒/帧）……"
ffmpeg -y -loglevel error -i "$VIDEO" -vf "fps=$FPS" "$OUT/frames/%04d.jpg"
NFRAMES="$(find "$OUT/frames" -name '*.jpg' | wc -l | tr -d ' ')"
echo "✅ 抽帧：$NFRAMES 张 → $OUT/frames/"

# 3. 语音转写
if [ -z "$WHISPER" ]; then
  echo "⚠️  未检测到 whisper，跳过语音转写。"
  echo "    macOS 推荐：brew install mlx-whisper   或   pip install -U openai-whisper"
  echo "    画面帧已就绪，台词可之后手动贴给灵小兔。"
else
  echo "转写中（$WHISPER / 模型 $MODEL）……"
  if [ "$WHISPER" = "mlx_whisper" ]; then
    mlx_whisper "$VIDEO" --output_format srt --output_dir "$OUT"
  else
    whisper "$VIDEO" --model "$MODEL" --output_format srt --output_dir "$OUT"
  fi
  SRT="$(find "$OUT" -maxdepth 1 -name '*.srt' | head -1)"
  if [ -n "$SRT" ]; then
    [ "$SRT" != "$OUT/transcript.srt" ] && mv "$SRT" "$OUT/transcript.srt"
    python3 - "$OUT/transcript.srt" "$OUT/transcript.txt" <<'PY'
import sys, re
srt, txt = sys.argv[1], sys.argv[2]
out = []
for block in open(srt, encoding="utf-8").read().split("\n\n"):
    lines = block.strip().split("\n")
    if len(lines) >= 3:
        m = re.match(r"(\d+):(\d+):(\d+),(\d+)", lines[1].split(" --> ")[0])
        text = " ".join(lines[2:]).strip()
        if text:
            if m:
                h, mm, s = int(m.group(1)), int(m.group(2)), int(m.group(3))
                out.append(f"[{h:02d}:{mm:02d}:{s:02d}] {text}")
            else:
                out.append(text)
open(txt, "w", encoding="utf-8").write("\n".join(out) + "\n")
print(f"✅ 转写：{srt}")
PY
    echo "✅ 纯文本：$OUT/transcript.txt"
  else
    echo "⚠️  转写未产出字幕文件，请检查 whisper 是否正常。"
  fi
fi

echo
echo "完成。对灵小兔说："
echo "  帮我把这条视频拆了，素材在 $OUT（帧图 + 字幕都在里面）"
