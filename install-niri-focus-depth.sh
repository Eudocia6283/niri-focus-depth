#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPSTREAM_REPO="https://github.com/YaLTeR/niri.git"
DEFAULT_REF="v26.04"
NIRI_DIR="$SCRIPT_DIR/niri"
BIN_SRC="$NIRI_DIR/target/release/niri"
PATCH_FILE="$SCRIPT_DIR/niri-focus-depth.patch"
KDL_SRC="$SCRIPT_DIR/focus-depth.kdl"
BIN_DST="/usr/bin/niri"
BIN_BAK="/usr/bin/niri.bak"
LEGACY_BAK="/usr/bin/niri.bak-26.04"

usage() {
    cat <<EOF
用法: $(basename "$0") <命令> [参数]

命令:
  --status              查看本地编译版本、系统当前 niri 版本、备份与升级状态
  --rebuild [git-ref]   拉取上游 niri（默认匹配系统版本，或指定如 v26.05 / latest），重新打补丁、跑测试并编译 release
  --install [--force]   安装本地 release 二进制到 /usr/bin/niri（会自动备份原版；若系统已更新则拒绝降级除非 --force）
  --update [git-ref]    一键执行 --rebuild + --install（系统滚动更新 niri 后使用）
  --rollback            从备份（/usr/bin/niri.bak 或 /usr/bin/niri.bak-26.04）恢复原版 niri
EOF
}

extract_ver() {
    "$1" --version 2>/dev/null | awk '{print $2}' | head -n1
}

version_gt() {
    local a="$1" b="$2"
    [[ -n "$a" && -n "$b" && "$a" != "$b" ]] && [[ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -n1)" == "$a" ]]
}

active_backup() {
    if [[ -e "$BIN_BAK" ]]; then
        echo "$BIN_BAK"
    elif [[ -e "$LEGACY_BAK" ]]; then
        echo "$LEGACY_BAK"
    fi
}

resolve_target_ref() {
    local requested="${1:-}"
    if [[ "$requested" == "latest" ]]; then
        git -C "$NIRI_DIR" tag -l 'v*' --sort=-v:refname | head -n1
        return
    fi

    if [[ -n "$requested" ]]; then
        if git -C "$NIRI_DIR" rev-parse --verify "${requested}^{commit}" >/dev/null 2>&1; then
            echo "$requested"
            return
        elif git -C "$NIRI_DIR" rev-parse --verify "v${requested}^{commit}" >/dev/null 2>&1; then
            echo "v${requested}"
            return
        fi
        echo "错误: 上游仓库中找不到 Git 引用: $requested" >&2
        exit 1
    fi

    if [[ -x "$BIN_DST" ]]; then
        local sys_ver
        sys_ver="$(extract_ver "$BIN_DST")"
        if [[ -n "$sys_ver" ]] && git -C "$NIRI_DIR" rev-parse --verify "v${sys_ver}^{commit}" >/dev/null 2>&1; then
            echo "v${sys_ver}"
            return
        fi
    fi

    if git -C "$NIRI_DIR" rev-parse --verify "${DEFAULT_REF}^{commit}" >/dev/null 2>&1; then
        echo "$DEFAULT_REF"
    else
        git -C "$NIRI_DIR" tag -l 'v*' --sort=-v:refname | head -n1
    fi
}

show_status() {
    local local_ver="" sys_ver="" bak_path
    bak_path="$(active_backup)"

    echo "=== niri-focus-depth 状态 ==="
    if [[ -x "$BIN_SRC" ]]; then
        local_ver="$(extract_ver "$BIN_SRC")"
        echo "[本地编译] $("$BIN_SRC" --version)"
    else
        echo "[本地编译] 尚未编译 ($BIN_SRC)"
    fi

    if [[ -x "$BIN_DST" ]]; then
        sys_ver="$(extract_ver "$BIN_DST")"
        echo "[系统当前] $("$BIN_DST" --version)"
    else
        echo "[系统当前] 未找到 $BIN_DST"
    fi

    if [[ -n "$bak_path" ]]; then
        echo "[原版备份] $bak_path ($("$bak_path" --version 2>/dev/null || echo '未知版本'))"
    else
        echo "[原版备份] 尚未创建 (/usr/bin/niri.bak)"
    fi

    echo "[补丁文件] $PATCH_FILE"
    echo "[配置片段] $KDL_SRC"

    if [[ -n "$local_ver" && -n "$sys_ver" ]] && version_gt "$sys_ver" "$local_ver"; then
        echo
        echo "提示: 系统 niri ($sys_ver) 高于本地编译版本 ($local_ver)——可能刚刚通过 pacman 滚动更新。"
        echo "请运行: $(basename "$0") --update"
    fi
}

do_rebuild() {
    local requested_ref="${1:-}"
    if [[ ! -f "$PATCH_FILE" ]]; then
        echo "错误: 找不到补丁文件: $PATCH_FILE" >&2
        exit 1
    fi

    if [[ ! -d "$NIRI_DIR/.git" ]]; then
        echo "正在克隆上游 niri 仓库到 $NIRI_DIR ..."
        git clone "$UPSTREAM_REPO" "$NIRI_DIR"
    else
        echo "正在同步上游标签与提交 ..."
        git -C "$NIRI_DIR" fetch --tags origin
    fi

    local target_ref
    target_ref="$(resolve_target_ref "$requested_ref")"
    echo "目标上游版本: $target_ref"

    # Preserve target/ cache while resetting tracked sources cleanly.
    git -C "$NIRI_DIR" checkout --force "$target_ref"
    git -C "$NIRI_DIR" reset --hard HEAD
    git -C "$NIRI_DIR" clean -fd -e target

    echo "正在应用补丁 $(basename "$PATCH_FILE") ..."
    if ! git -C "$NIRI_DIR" apply --3way "$PATCH_FILE"; then
        cat >&2 <<EOF

错误: 补丁未能无冲突自动应用到 $target_ref。
请排查冲突：
  cd "$NIRI_DIR" && git status
解决冲突后，可运行以下命令更新补丁并继续编译：
  git diff > "$PATCH_FILE"
  cargo test --locked -p niri-config && cargo test --locked --lib layout::tests && cargo build --release --locked --bin niri
EOF
        exit 1
    fi

    echo "正在运行单元测试 ..."
    cargo test --locked --manifest-path "$NIRI_DIR/Cargo.toml" -p niri-config
    cargo test --locked --manifest-path "$NIRI_DIR/Cargo.toml" --lib layout::tests

    echo "正在编译 release 版本 ..."
    cargo build --release --locked --manifest-path "$NIRI_DIR/Cargo.toml" --bin niri
    echo "编译完成: $("$BIN_SRC" --version)"
}

do_install() {
    local force="${1:-false}"
    if [[ ! -x "$BIN_SRC" ]]; then
        echo "错误: 找不到本地编译的可执行文件: $BIN_SRC" >&2
        echo "请先运行: $(basename "$0") --rebuild" >&2
        exit 1
    fi

    if [[ -x "$BIN_DST" ]]; then
        local local_ver sys_ver
        local_ver="$(extract_ver "$BIN_SRC")"
        sys_ver="$(extract_ver "$BIN_DST")"
        if [[ "$force" != "true" ]] && version_gt "$sys_ver" "$local_ver"; then
            cat >&2 <<EOF
拒绝安装: 系统当前 niri ($sys_ver) 新于本地编译产物 ($local_ver)。
pacman 滚动更新已将系统升级到新版，直接 --install 会把系统降级。
请先重新基于新版源码打补丁编译并安装：
  $(basename "$0") --update
如确定要强制覆盖旧版，请加 --force 参数。
EOF
            exit 1
        fi
    fi

    local bak_path
    bak_path="$(active_backup)"
    if [[ -z "$bak_path" && -e "$BIN_DST" ]]; then
        echo "正在备份原版 $BIN_DST -> $BIN_BAK ..."
        sudo cp -a "$BIN_DST" "$BIN_BAK"
    elif [[ -n "$bak_path" ]]; then
        echo "已存在原版备份 $bak_path，跳过备份。"
    fi

    echo "正在安装 $BIN_SRC -> $BIN_DST ..."
    sudo install -m 755 "$BIN_SRC" "$BIN_DST"
    echo "安装完成: $("$BIN_DST" --version)"
    echo
    echo "提示: 确保 ~/.config/niri/config.kdl 末尾包含："
    echo "    include \"$KDL_SRC\""
    echo "然后重新登录 Wayland 会话使新二进制生效。"
}

do_rollback() {
    local bak_path
    bak_path="$(active_backup)"
    if [[ -z "$bak_path" ]]; then
        echo "错误: 找不到原版备份 (/usr/bin/niri.bak 或 /usr/bin/niri.bak-26.04)，可用 pacman 恢复: sudo pacman -S niri" >&2
        exit 1
    fi

    echo "正在从 $bak_path 恢复 $BIN_DST ..."
    sudo install -m 755 "$bak_path" "$BIN_DST"
    echo "已恢复: $("$BIN_DST" --version)"
}

case "${1:-}" in
    --status)
        show_status
        ;;
    --rebuild)
        do_rebuild "${2:-}"
        ;;
    --install)
        force="false"
        if [[ "${2:-}" == "--force" ]]; then
            force="true"
        elif [[ -n "${2:-}" ]]; then
            echo "未知参数: $2" >&2
            usage
            exit 1
        fi
        do_install "$force"
        ;;
    --update)
        do_rebuild "${2:-}"
        do_install "false"
        ;;
    --rollback)
        do_rollback
        ;;
    *)
        usage
        exit 1
        ;;
esac
