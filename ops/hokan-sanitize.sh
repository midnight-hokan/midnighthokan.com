#!/usr/bin/env bash
# hokan-sanitize — 发布前扫描内容目录，发现内部标识就退出非 0
# 拦截：Tailscale 地址(100.64/10)、内网地址、家宽/零点公网 IP、邮箱、公众号 AppID、
#       常见 token 前缀、私钥、本机用户名与真名
# 某一行确实需要保留（比如文档示例），在该行末尾加 <!-- sanitize-ok -->
set -uo pipefail
DIR=${1:-.}

PAT='\b100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}\b'
PAT+='|\b192\.168\.[0-9]{1,3}\.[0-9]{1,3}\b'
PAT+='|\b10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b'
PAT+='|\b172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}\b'
PAT+='|\b101\.36\.226\.14\b|\b221\.220\.134\.232\b'
PAT+='|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
PAT+='|\bwx[0-9a-f]{16}\b'
PAT+='|\b(sk|ghp|gho|ghs|github_pat|xox[bp])[-_][A-Za-z0-9_]{16,}'
PAT+='|BEGIN [A-Z ]*PRIVATE KEY'
PAT+='|\byuguang\b|kikalu|于光'

hits=$(grep -rnEI --include='*.md' --include='*.mdx' "$PAT" "$DIR" | grep -v 'sanitize-ok' || true)
if [[ -n "$hits" ]]; then
  echo "FAIL: sanitize check found internal identifiers:"
  echo "$hits"
  exit 1
fi
echo "sanitize: clean"
