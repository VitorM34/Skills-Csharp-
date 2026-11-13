#!/usr/bin/env bash
# Instala (via symlink) todas as skills desta pasta.
#   ./install.sh                    -> ~/.claude/skills  (todos os projetos)
#   ./install.sh /caminho/projeto   -> /caminho/projeto/.claude/skills
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ $# -ge 1 ]]; then
  DEST="$1/.claude/skills"
else
  DEST="$HOME/.claude/skills"
fi

mkdir -p "$DEST"
count=0
for dir in "$SRC"/*/; do
  name="$(basename "$dir")"
  [[ -f "$dir/SKILL.md" ]] || continue
  target="$DEST/$name"
  if [[ -e "$target" && ! -L "$target" ]]; then
    echo "PULANDO $name: já existe em $target e não é symlink"
    continue
  fi
  ln -sfn "$dir" "$target"
  count=$((count + 1))
  echo "ok  $name -> $target"
done
echo "$count skills instaladas em $DEST. Reinicie a sessão do Claude Code."
