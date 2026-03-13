# waybar_niri_plugin_WallSwitcher

项目名称：`waybar_niri_plugin_WallSwitcher`

这是一个给 `niri + waybar` 用的双层壁纸切换插件。

它同时管理两层内容：

- `wallpaper`：正常桌面看到的壁纸层
- `backdrop`：`niri` 进入 overview / 上帝视角时使用的背景层

插件通过 Waybar 左键弹出 `fuzzel` 菜单进行选择，支持以下两种模式：

- `自动高斯模糊模式`
  - 选择一个 `wallpaper`
  - 如果是图片，就直接把图片做细腻高斯模糊后作为 `backdrop`
  - 如果是视频，就先用 `ffmpeg` 导出首帧，再做同样的高斯模糊作为 `backdrop`
- `分选模式`
  - 分别选择 `wallpaper` 和 `backdrop`
  - `wallpaper` 支持图片 / 视频 / 透明
  - `backdrop` 支持图片 / 视频

## 目录约定

插件只读取以下两个目录：

- `~/Pictures/WallPapper`
- `~/Videos/WallVideo`

注意：

- `WallPapper` 的拼写就是这样，安装后请直接使用这个目录名
- 图片请放到 `~/Pictures/WallPapper`
- 视频请放到 `~/Videos/WallVideo`
- 脚本会对这两个资源目录做大小写不敏感匹配
- 例如 `WallPapper`、`wallpapper`、`WALLPAPPER`，以及 `WallVideo`、`wallvideo`、`WALLVIDEO` 都可以被识别

## 依赖

请先确保系统里有这些命令：

- `ffmpeg`
- `magick`（ImageMagick）
- `jq`
- `fuzzel`
- `mpvpaper`
- `swww`
- `swaybg`
- `waybar`
- `niri`

## 包内文件

```text
waybar/modules/wallpaper-switcher.sh
waybar/modules/wallpaper-switcher.json
snippets/waybar-modules.jsonc.snippet
snippets/waybar-config.snippet
snippets/niri-config.kdl.snippet
```

## 安装步骤

### 1. 复制脚本和配置

把下面两个文件复制到你的 Waybar 模块目录：

- `waybar/modules/wallpaper-switcher.sh`
- `waybar/modules/wallpaper-switcher.json`

目标位置通常是：

```bash
~/.config/waybar/modules/
```

并确保脚本有执行权限：

```bash
chmod +x ~/.config/waybar/modules/wallpaper-switcher.sh
```

### 2. 创建资源目录

```bash
mkdir -p ~/Pictures/WallPapper
mkdir -p ~/Videos/WallVideo
```

然后把图片和视频分别放进去。

### 3. 在 Waybar 里注册模块

把 `snippets/waybar-modules.jsonc.snippet` 里的模块块加入你的 `~/.config/waybar/modules.jsonc`。

再把 `snippets/waybar-config.snippet` 里的 `"custom/wallpaper"` 加进你想放的位置，例如 `modules-left`。

### 4. 在 Niri 里加入 layer-rule 和启动项

把 `snippets/niri-config.kdl.snippet` 里的内容并入你的 `~/.config/niri/config.kdl`：

- `swww-daemon` 放进 `backdrop`
- `mpvpaper` 的 `background` layer 放进 `backdrop`
- 开机执行 `wallpaper-switcher.sh restore`
- 绑定 `Mod+Ctrl+B` 打开菜单
- 绑定 `Mod+Ctrl+R` 触发 niri 配置热重载
- 绑定 `Mod+Ctrl+W` 开关 waybar

注意：

- 片段里的路径按当前机器写成了 `/home/lonnet/...`
- 如果安装目标不是这个用户，请把片段里的绝对路径改成你自己的家目录路径

### 5. 重载配置

```bash
touch ~/.config/niri/config.kdl
pkill waybar
waybar &
```

## 使用方法

- Waybar 左键点击壁纸模块：打开壁纸菜单
- 选 `自动高斯模糊模式`：只选一次 wallpaper，插件自动生成 backdrop
- 选 `分选模式`：分别选 wallpaper 和 backdrop

## 工作方式说明

### 图片 wallpaper

- 用 `swaybg` 作为正常桌面壁纸层

### 视频 wallpaper

- 用 `mpvpaper --layer bottom` 作为正常桌面壁纸层

### 图片 backdrop

- 用 `swww-daemon` + `swww img`
- 通过 `niri` 的 `place-within-backdrop true` 放进 backdrop

### 视频 backdrop

- 用 `mpvpaper --layer background`
- 再通过 `niri` 的 `place-within-backdrop true` 放进 backdrop

## 注意事项

- 如果 `~/Pictures/WallPapper` 里没有图片，菜单里就不会出现静态图片项
- 如果 `~/Videos/WallVideo` 里没有视频，菜单里就不会出现视频项
- 自动模式下生成的模糊图会缓存在：

```text
~/.config/waybar/cache/wallpaper-switcher
```

- 当前实现只支持从上述两个固定目录读取资源

## 许可证

本项目使用 `MIT License`。

完整许可证内容见仓库根目录下的 [LICENSE](./LICENSE) 文件。
