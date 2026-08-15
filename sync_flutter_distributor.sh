#!/usr/bin/env bash
# 从上游 (chen08209/flutter_distributor) 拉取最新代码，
# 同步到自己的 fork (Filterrr/flutter_distributor) 并更新父仓库的子模块指针。
#
# 用法:
#   ./sync_flutter_distributor.sh              # 同步并推送 fork、更新父仓库指针并提交
#   ./sync_flutter_distributor.sh --no-push    # 只本地同步，不推送 fork
#   ./sync_flutter_distributor.sh --no-commit  # 更新指针但不自动 commit 父仓库
#   ./sync_flutter_distributor.sh --force      # fork 与上游分叉时，强制重置为上游
set -euo pipefail

SUBMODULE_PATH="plugins/flutter_distributor"
BRANCH="FlClash"
FORK_URL="https://github.com/Filterrr/flutter_distributor.git"
UPSTREAM_URL="https://github.com/chen08209/flutter_distributor.git"

PUSH=1
COMMIT=1
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --no-push)   PUSH=0 ;;
    --no-commit) COMMIT=0 ;;
    --force)     FORCE=1 ;;
    *) echo "未知参数: $arg"; exit 1 ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# 子模块未初始化时先初始化
if [ ! -e "$SUBMODULE_PATH/.git" ]; then
  git submodule update --init "$SUBMODULE_PATH"
fi

cd "$SUBMODULE_PATH"

# 确保 remote 配置正确
if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$FORK_URL"
else
  git remote add origin "$FORK_URL"
fi
if git remote get-url upstream >/dev/null 2>&1; then
  git remote set-url upstream "$UPSTREAM_URL"
else
  git remote add upstream "$UPSTREAM_URL"
fi

echo "==> 从上游拉取 $UPSTREAM_URL ($BRANCH)"
git fetch upstream "$BRANCH"
git checkout "$BRANCH"

UPSTREAM_COMMIT="$(git rev-parse upstream/$BRANCH)"
LOCAL_COMMIT="$(git rev-parse HEAD)"
echo "    本地:   $LOCAL_COMMIT"
echo "    上游:   $UPSTREAM_COMMIT"

if [ "$LOCAL_COMMIT" = "$UPSTREAM_COMMIT" ]; then
  echo "==> 已是最新，无需同步"
  exit 0
fi

if git merge-base --is-ancestor "$LOCAL_COMMIT" "upstream/$BRANCH"; then
  # 本地落后于上游，直接快进
  git merge --ff-only "upstream/$BRANCH"
else
  # 分叉：默认中止，--force 时强制对齐上游（会丢弃 fork 上的独有提交）
  if [ "$FORCE" -ne 1 ]; then
    echo "错误: fork 与上游已分叉，使用 --force 强制重置为上游（丢弃本地独有提交）" >&2
    exit 1
  fi
  echo "==> --force: 重置 $BRANCH 到上游"
  git reset --hard "upstream/$BRANCH"
fi

NEW_COMMIT="$(git rev-parse HEAD)"
echo "==> 同步完成: $NEW_COMMIT"

if [ "$PUSH" -eq 1 ]; then
  echo "==> 推送到 fork $FORK_URL"
  git push origin "$BRANCH"
fi

# 回到父仓库，更新子模块指针
cd "$REPO_ROOT"
git add "$SUBMODULE_PATH"

if [ "$COMMIT" -eq 1 ] && ! git diff --cached --quiet; then
  SHORT="${NEW_COMMIT:0:7}"
  git commit -m "chore: update flutter_distributor to $SHORT"
  echo "==> 父仓库已提交，可手动 git push"
else
  echo "==> 父仓库子模块指针已暂存（未提交）"
fi
