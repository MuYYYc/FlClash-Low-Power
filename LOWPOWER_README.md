# FlClash Low-Power

FlClash 低功耗 Fork，基于 [chen08209/FlClash](https://github.com/chen08209/FlClash) v0.9.3，面向 macOS 长时间后台运行优化。

## 合入的 PR

| 来源 | 内容 |
|------|------|
| #2201 | 托盘标题去重，关闭网速时取消流量订阅 |
| #2186 部分 | 隐藏窗口暂停每秒核心 IPC + 流量日志静默 |
| #1826 | 点击托盘图标切换显示/隐藏 |
| #2237 | TUN `auto-detect-interface` JSON 序列化修复 |
| #2238 | 关闭 IPv6 时清除 TUN IPv6 地址 |
| #2170 | 取消 99 小时运行时间上限 |

### 自研改动

| 内容 |
|------|
| 停止代理后延迟 10 秒再清流量（可确认本次流量后再归零） |
| 低功耗定时器检查：窗口隐藏 + 关闭网速 → 跳过每秒 core IPC |
| `resetTraffic` 全链路 async，防止重启时异步竞态 |
| Provider dispose 时取消定时器 |
| 关于页显示 Low Power · Muyu，并链接到本分支 |
| 副模块 URL HTTPS（无需 SSH key） |
| `.gitignore` 忽略 `**/.gradle/` |

## 分支布局

```
Muyu-Chen/FlClash-Low-Power (fork):
  main     → 低功耗版（即本分支），clone 即可编译
  upstream → 上游 main 镜像，用于 diff/对照

本地:
  macos-low-power → 开发分支，所有改动在此
```

## 合入上游新版本

使用合并保留低功耗分支的提交历史，并按新版架构核对本分支功能：

```bash
git fetch origin --tags
git merge origin/main
git submodule update --init --recursive
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze --no-fatal-infos
dart run tool/test.dart
bash macos/packaging/release_arm64.sh
```

v0.9.1 上游已提供隐藏窗口暂停轮询、托盘标题去重、连接网速稳定排序及表格列排序；本分支沿用这些实现。
停止后保留流量 10 秒、macOS 托盘点击切换及 Apple Silicon 打包由本分支保留。

v0.9.3 使用上游的新 Core 协议、prism_ui 和合并后的连接/请求页面，不维护旧协议或旧页面。
本分支额外保留日志、请求、DNS 和仪表盘的隐藏展示刷新暂停、历史记录环形缓冲、流量调用日志静默、
Windows 热点共享以及菜单栏文字随系统变暗。记录采集不随页面隐藏停止。
更新检查和下载使用本 fork 的 release，避免更新回上游原版；macOS 仍由 release 页面手动下载。
升级后运行完整回归，实际离电功耗另行测量，不由测试通过推断。

## 编译

需要 Xcode + Flutter 3.47.2 以上（本机固定 3.47.7）+ Go 1.27 + Rust 1.99 以上。macOS 插件使用 Swift Package Manager。

```bash
# 初始化
git submodule update --init --recursive  # 已 HTTPS URL，无需 SSH key
flutter pub get
dart run build_runner build

# 编译 macOS Release（Apple Silicon only，无 PRE 标志）
bash macos/packaging/release_arm64.sh

# 产物
dist/macos-arm64/FlClash-0.9.3.app.zip  → FlClash.app
```

详细环境安装和卸载见 `low-power-doc/`。

## 与上游 dist 产物的区别

| 项目 | 上游 | Low-Power Fork |
|------|------|----------------|
| 发布渠道 | 正式版与 pre 分开 | 正式版（`APP_ENV=stable`） |
| 托盘标题去重 | 支持 | 沿用上游实现 |
| 隐藏窗口轮询 | 暂停 | 沿用上游实现 |
| 隐藏页面事件展示刷新 | 持续 | 暂停，返回后读取最新记录 |
| 满容量历史记录追加 | 移动旧元素 | 环形缓冲，O(1) |
| 流量日志每秒写入 | 是 | 静默 |
| 停止代理后流量归零 | 立即 | 延迟 10 秒 |
| 运行时间上限 | 999:59:59 | 无 |
| macOS 框架 | 含 x86_64 | Apple Silicon only |
| TUN 配置和连接排序 | 上游实现 | 沿用上游实现 |
| 更新源 | 作者仓库 | 本 fork |
