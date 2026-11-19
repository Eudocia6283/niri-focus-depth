# niri-focus-depth

> For [YaLTeR/niri](https://github.com/YaLTeR/niri) `v26.04` (commit `8ed0da4`): adds GPU visual scaling, spring-animated opacity, Dual-Kawase content blur, backdrop-blur preservation, and tighter 2.5D card-stack depth for unfocused windows — without triggering client resize or text reflow.

为滚动平铺式 Wayland 合成器 **niri** 添加**窗口聚焦景深与紧密堆叠动效（`focus-depth`）**的源码补丁与 Arch 打包方案：
- **未聚焦窗口**：按 spring 曲线平滑做纯 GPU 视觉缩小、降低额外透明度、对窗口内容本身施加景深失焦模糊（`inactive-blur`），并向聚焦列内侧收拢重叠堆叠，营造“退入背景层”的 2.5D 卡片景深感。
- **聚焦窗口**：平滑恢复 `1.0` 尺寸、`1.0` 透明度与清晰内容，全流程**不发送 Wayland `configure` 尺寸变更**，不触发终端/浏览器重排。

---

## 核心特性

1. **零重排纯 GPU 变换**：保持 niri 逻辑列宽与滚动布局不变，仅在合成渲染阶段缩放与位移，切换焦点时文字不抖动、不重新换行。
2. **完整保留并对齐 `window-rule` 背景毛玻璃**：将背景模糊（`background-effect { blur; xray }`）移至主帧队列按缩放后的几何位置渲染，无论是 `xray true` 还是 `xray false` 都与未聚焦窗口严丝合缝。
3. **未聚焦窗口内容景深模糊（`inactive-blur`）**：基于 niri 内置 Dual-Kawase `Blur` 对离屏缓存纹理做景深模糊，并按 `(id, commit, size, options)` 缓存（静止后台窗口零重复 blur 开销），在关闭边线/阴影与开启圆角裁剪时还会先模糊后裁剪，避免暗角渗色。
4. **2.5D 内缩堆叠与就近遮挡**：自动补偿缩放产生的空白后再内缩 `stack-overlap`，同时将聚焦列左侧列按距焦点由近到远排序（`first.iter().rev()`），保证左右两侧层叠遮挡自然正确。
5. **与 niri 原生动画 / Overview / 鼠标命中协同**：
   - 使用与 `animations.horizontal-view-movement` 一致的 spring 动效，自动响应 `slowdown`。
   - 全屏/最大化或进入 Overview 时平滑退回原状，退出时恢复景深。
   - 指针点击与调整边缘自动对缩放与内缩偏移做逆映射，所见即所点。
6. **默认关闭（`off`）**：需在 KDL 配置中显式开启，便于安全升级与按显示器/工作区覆盖。

---

## KDL 配置说明

参考 [`focus-depth.kdl`](focus-depth.kdl)：

```kdl
layout {
    focus-depth {
        on
        // 未聚焦窗口缩放比例 (0.5 ~ 1.0，默认 0.92)
        inactive-scale 0.92
        // 未聚焦窗口额外透明度乘数 (0.05 ~ 1.0，叠加在 window-rule opacity 之上，默认 0.78)
        inactive-opacity 0.82
        // 未聚焦窗口内容景深模糊强度 (0 ~ 10，0 为关闭，默认 2.0)
        inactive-blur 2.0
        // 未聚焦列向聚焦列内侧收拢堆叠的逻辑像素偏移 (0 ~ 4096，默认 48)
        stack-overlap 48
    }
}
```

支持在 `output "..." { layout { focus-depth { off } } }` 或 `workspace "..." { layout { ... } }` 中按显示器/工作区单独开关或微调。

---

## 安装与系统滚动更新指南

> **重要说明（关于滚动更新）**  
> 本项目是对 `niri` 二进制源码打补丁，而不是外挂插件。**当你通过 `pacman -Syu` 滚动更新了官方 `niri` 软件包后**：
> - pacman 会用新版官方二进制覆盖 `/usr/bin/niri`；
> - **不能直接重新运行 `--install`**（那样会把旧版本编译产物覆盖回去，造成降级；脚本也会主动阻止）；
> - 正确做法是用**新版本的 niri 源码重新打补丁并编译**后再安装。

### 方式一：Arch Linux `PKGBUILD`（最推荐，纳入 pacman 包管理）

通过自定义包替换官方 `niri`（`provides=('niri')`、`conflicts=('niri')`），`pacman -Syu` 不会悄悄覆写你的 `/usr/bin/niri`：

```bash
git clone https://github.com/<你的用户名>/niri-focus-depth.git
cd niri-focus-depth
makepkg -si
```

在 `~/.config/niri/config.kdl` 末尾添加：

```kdl
include "/usr/share/doc/niri-focus-depth/focus-depth.kdl"
```

**上游 niri 发布新版时如何升级**：编辑 [`PKGBUILD`](PKGBUILD) 里的 `pkgver=新版本号`，运行 `git pull && makepkg -si` 即可。

### 方式二：使用仓库脚本（`install-niri-focus-depth.sh`）

1. **首次拉取源码、打补丁、跑测试、编译并安装**：
   ```bash
   git clone https://github.com/<你的用户名>/niri-focus-depth.git
   cd niri-focus-depth
   ./install-niri-focus-depth.sh --update
   ```
   并在 `~/.config/niri/config.kdl` 末尾加入：
   ```kdl
   include "/你的仓库路径/focus-depth.kdl"
   ```
2. **当 pacman 滚动更新了系统 `niri` 后**：
   先查看状态，再执行一键跟进新版本（脚本会自动检测 `/usr/bin/niri` 的当前版本，拉取对应上游 tag、重新打 `niri-focus-depth.patch`、跑配置与布局测试并编译安装）：
   ```bash
   ./install-niri-focus-depth.sh --status
   ./install-niri-focus-depth.sh --update          # 自动匹配系统当前 niri 版本 tag
   # 或显式指定版本 / 最新标签：
   # ./install-niri-focus-depth.sh --update v26.05
   # ./install-niri-focus-depth.sh --update latest
   ```
3. **只重编不覆盖 / 仅安装本地产物 / 一键回滚**：
   ```bash
   ./install-niri-focus-depth.sh --rebuild         # 仅重新打补丁、跑测试并编译
   ./install-niri-focus-depth.sh --install         # 将本地已编译的二进制安装到 /usr/bin/niri（带防降级保护）
   ./install-niri-focus-depth.sh --rollback        # 从原版备份恢复 /usr/bin/niri
   ```

> **提示**：如遇上游大版本重构导致 `git apply --3way` 冲突，脚本会暂停并提示你在 `niri/` 中手动解决冲突后通过 `git diff > ../niri-focus-depth.patch` 更新补丁。

---

## 仓库文件说明

| 文件 | 说明 |
| :--- | :--- |
| [`niri-focus-depth.patch`](niri-focus-depth.patch) | 基于 `YaLTeR/niri` `v26.04 (8ed0da4)` 的完整补丁 |
| [`PKGBUILD`](PKGBUILD) | Arch Linux / AUR 风格打包脚本 |
| [`install-niri-focus-depth.sh`](install-niri-focus-depth.sh) | 支持 `--update` / `--rebuild` / `--install` / `--rollback` / `--status` 的维护脚本 |
| [`focus-depth.kdl`](focus-depth.kdl) | 开箱即用的 KDL 配置片段 |
| [`LICENSE`](LICENSE) | GPL-3.0-or-later |

---

## 致谢与协议

基于 [YaLTeR/niri](https://github.com/YaLTeR/niri) 开发，遵循上游 **GPL-3.0-or-later** 开源协议（详见 [`LICENSE`](LICENSE)）。
