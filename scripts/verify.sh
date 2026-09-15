#!/usr/bin/env bash
# reelwright 结构自检：校验 skill 文件齐全、引用一致、frontmatter 完整。
# 用法：bash scripts/verify.sh
set -u

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SKILL_DIR" || exit 1

fail=0
ok()  { printf '  ✓ %s\n' "$*"; }
bad() { printf '  ✗ %s\n' "$*"; fail=1; }

echo "reelwright 结构自检"
echo "目录：$SKILL_DIR"
echo

# [1] 核心文件
echo "[1/4] 核心文件与脚本"
[ -s SKILL.md ] && ok "SKILL.md" || bad "SKILL.md 缺失或为空"
[ -s README.md ] && ok "README.md" || bad "README.md 缺失或为空"
[ -s LICENSE ]   && ok "LICENSE"   || bad "LICENSE 缺失或为空"
[ -s scripts/video_to_frames_transcript.sh ] && ok "scripts/video_to_frames_transcript.sh" || bad "scripts/video_to_frames_transcript.sh 缺失或为空"

# [2] 参考文件（00~09）
echo "[2/4] 参考文件"
for i in 00 01 02 03 04 05 06 07 08 09; do
  f="$(ls "references/${i}-"*.md 2>/dev/null | head -1)"
  if [ -n "$f" ] && [ -s "$f" ]; then
    ok "${f#references/}"
  else
    bad "references/${i}-*.md 缺失"
  fi
done

# [3] SKILL.md frontmatter 与引用一致性
echo "[3/4] SKILL.md 元信息"
head -8 SKILL.md | grep -q '^name:'        && ok "有 name 字段"        || bad "缺 name 字段"
head -8 SKILL.md | grep -q '^description:' && ok "有 description 字段" || bad "缺 description 字段"
while read -r ref; do
  [ -n "$ref" ] || continue
  [ -f "$ref" ] && ok "$ref 存在" || bad "$ref 被引用但文件不存在"
done < <(grep -oE 'references/[0-9]{2}-[^ `)]+' SKILL.md | sort -u)

# [4] 方向模板 frontmatter 抽查（01-09 均产出档案，须含 type）
echo "[4/4] 方向模板 frontmatter"
n=0
for f in references/0[1-9]-*.md; do
  if grep -q '^type:' "$f"; then
    n=$((n+1))
  else
    bad "${f#references/} 缺 type 字段"
  fi
done
echo "  产出档案的 9 个方向（01-09）含 type 字段：${n} / 9"

echo
if [ "$fail" -eq 0 ]; then
  echo "✅ 自检通过，skill 结构完整、引用一致。"
else
  echo "❌ 发现问题，请修复后重跑。"
fi
exit "$fail"
