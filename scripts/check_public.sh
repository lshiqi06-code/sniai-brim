#!/bin/zsh
# 公开前检查：开源版里不能有收费代码、品牌字体、个人信息、密钥和工作室内部的路径。
# 在 open/（以后的公开仓库根目录）里查所有会被提交的文件（编译产物已被 .gitignore 排除），有问题就列出来、返回 1。
# 用法：./scripts/check_public.sh
set -uo pipefail
cd "$(dirname "$0")/.."
files=("${(@f)$(git ls-files --cached --others --exclude-standard . | grep -v '^scripts/check_public.sh$')}")
fail=0

check() { # 说明 正则
  local hits
  hits=$(grep -nIE -- "$2" "${files[@]}" 2>/dev/null)
  if [[ -n "$hits" ]]; then
    echo "✗ $1"
    echo "$hits" | head -12 | sed 's/^/    /'
    fail=1
  else
    echo "✓ $1"
  fi
}

check "没有收费代码（待办、扫进程、查额度）" 'TodoList|TodoMenuView|TodoAccessory|TodoStore|AgentScanner|ProcessTable|AgentStore|QuotaFetcher|QuotaParser'
check "没有别的工具的登录凭据路径" '\.claude/|\.codex/|\.gemini/|oauth_creds|credentials\.json|claudeAiOauth'
check "没有品牌字体（硬规则 1）" '@font-face|Modular Display'
check "没有个人路径、邮箱、证书编号" '/Users/[a-z]|liushiqi|stevenlsq|yyccii|@icloud\.com|@gmail\.com|H8JL73S59C'
check "没有工作室内部的仓库和路径" 'lblus-office|HANDOFF|接力|brand/tokens|yard-design|sniai/yard'
check "没有密钥" 'sk-[A-Za-z0-9]{20}|ghp_[A-Za-z0-9]{20}|BEGIN [A-Z ]*PRIVATE KEY|xox[bp]-'
check "品牌名全小写、没有弃用名（硬规则 3）" '\b(Lblus|LBLUS|Sniai|SNIAI|Eveye|Buyud|Shiqi)\b|cookie view|seeqi|seeview|myeye|buy\.ed|lbl\.us'
check "bundle id 换成自己的域名（sni.ai 不在 shiqi 名下）" 'ai\.sniai\.brim'
check "草稿标记都删了" '草稿，发布前删掉'

fonts=$(printf '%s\n' "${files[@]}" | grep -iE '\.(otf|ttf|ttc|woff2?)$')
if [[ -n "$fonts" ]]; then
  echo "✗ 有字体文件"
  echo "$fonts" | sed 's/^/    /'
  fail=1
else
  echo "✓ 没有字体文件"
fi

for f in README.md LICENSE; do
  if [[ -f "$f" ]]; then echo "✓ 有 $f"; else echo "✗ 缺 $f"; fail=1; fi
done

exit $fail
