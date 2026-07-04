# ServerHost — iPad C++ HTTP Server

在 iPad 6（iPadOS 17.7.9）上运行的 C++ HTTP 服务器 App。

## 功能概述

- **App 启动** → 弹出文件选择器，让用户从「文件」App 中选择一个 `.html` 文件
- **自动定位目录** → 提取该文件所在目录，`chdir()` 切换工作目录
- **启动 HTTP Server** → cpp-httplib 监听 `127.0.0.1:8080`，`set_base_dir` 映射整个目录
- **静音保活** → AVAudioEngine 循环播放 0.1s 静音 buffer，后台不挂起
- **浏览器访问** → iPad 上用 Safari/Chrome 访问 `http://127.0.0.1:8080` 即可打开网页

## 项目结构

```
ServerHost/
├── main.mm                  # Obj-C++ 入口 + UI + 音频保活 + HTTP Server
├── httplib.h                # cpp-httplib 单头文件 (v0.14+, 20000+ 行)
├── Info.plist               # 含 UIBackgroundModes: audio
├── ExportOptions.plist      # method=ad-hoc, signingStyle=automatic
├── project.yml              # XcodeGen 项目配置
├── index.html               # 示例网页
├── style.css                # 示例样式
├── .github/workflows/
│   └── build-ipa.yml        # GitHub Actions 构建流水线
└── README.md
```

## 构建方式

### 方法一：GitHub Actions 自动构建（推荐）

1. **创建 GitHub 仓库**
   ```bash
   cd ServerHost
   git init
   git add .
   git commit -m "Initial commit: ServerHost iOS app"
   git branch -M main
   git remote add origin https://github.com/<你的用户名>/ServerHost.git
   git push -u origin main
   ```

2. **等待 Actions 完成**
   - 推送后 GitHub Actions 自动触发
   - 进入仓库 → Actions 页面查看构建进度
   - 构建约 5-8 分钟

3. **下载 IPA**
   - 构建成功后，在 Actions 运行页面底部找到 **Artifacts** 区域
   - 点击 `ServerHost-ipa` 下载 `ServerHost.ipa`

### 方法二：本地 Xcode 构建

```bash
# 安装 XcodeGen
brew install xcodegen

# 生成 Xcode 项目
cd ServerHost
xcodegen generate

# 用 Xcode 打开
open ServerHost.xcodeproj

# 或命令行构建
xcodebuild archive \
  -project ServerHost.xcodeproj \
  -scheme ServerHost \
  -archivePath build/ServerHost.xcarchive \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS=arm64
```

## 安装到 iPad

### 使用 NBtool 自签安装

1. **下载 NBtool**（或在 iPad 上使用对应的自签工具）
2. 将 `ServerHost.ipa` 导入 NBtool
3. 使用你的 Apple ID 进行自签
4. 安装签名后的 App
5. 在 iPad **设置 → 通用 → VPN与设备管理** 中信任开发者证书

### 使用其他工具

也支持 AltStore、Sideloadly、TrollStore（如设备兼容）等自签工具安装。

## 使用方法

1. **打开 App**
   - App 启动后自动弹出文件选择器

2. **选择 HTML 文件**
   - 在「文件」App 中导航到你的网页文件夹
   - 选择其中的 `index.html`（或任意 `.html` 文件）
   - App 会自动定位到该文件所在目录

3. **服务器启动**
   - 界面显示「已选择：xxx/index.html，Server 运行中」
   - AVAudioEngine 静音保活已启动

4. **浏览器访问**
   - 在 iPad 上打开 Safari 或 Chrome
   - 访问 `http://127.0.0.1:8080`
   - 即可看到你选择的网页
   - 访问 `http://127.0.0.1:8080/ping` 验证 API 连通性（返回 `pong`）

5. **后台运行**
   - 按下 Home 键或将 App 切到后台
   - 服务器继续运行（得益于 audio 后台保活）
   - 回到前台可继续操作

### 如何把网页文件放到 iPad 上

1. 通过 iCloud Drive / Google Drive / 百度网盘等同步到 iPad
2. 用「文件」App 找到文件所在位置
3. 确保文件夹中有 `index.html` 以及所有 CSS/JS/图片资源

## 接入 OpenFrp（内网穿透）

如果需要从 iPad 外部访问服务器，可以使用 OpenFrp 进行内网穿透。

### 方案 A：在 iPad 上运行 OpenFrp 客户端

> 注：需要 iOS 上可执行 frpc 的环境（如 iSH、a-Shell Pro 或越狱环境）

1. 下载 frpc 配置文件
2. 配置 `frpc.ini`：
   ```ini
   [common]
   server_addr = your-openfrp-server.com
   server_port = 7000
   token = your_token

   [ipad-http]
   type = tcp
   local_ip = 127.0.0.1
   local_port = 8080
   remote_port = 你的远程端口
   ```
3. 运行 frpc，通过 `server_addr:remote_port` 从外部访问

### 方案 B：在同局域网的电脑上运行 frpc

1. 在电脑上下载 frpc
2. 配置 `frpc.ini`（同上，`local_ip` 改为 iPad 的局域网 IP）
   ```ini
   [common]
   server_addr = your-openfrp-server.com
   server_port = 7000
   token = your_token

   [ipad-http]
   type = tcp
   local_ip = 192.168.x.x    # iPad 的局域网 IP
   local_port = 8080
   remote_port = 你的远程端口
   ```
3. 运行 frpc
4. 通过 `server_addr:remote_port` 从外网访问

> **注意**：方案 B 需要将 httplib 的监听地址从 `127.0.0.1` 改为 `0.0.0.0`，修改 `main.mm` 中的 `listen("127.0.0.1", 8080)` 为 `listen("0.0.0.0", 8080)`。

## 技术细节

| 项目 | 说明 |
|------|------|
| 语言 | Objective-C++ (.mm) |
| HTTP 库 | [cpp-httplib](https://github.com/yhirose/cpp-httplib) v0.14+ |
| 最低系统 | iOS 15.0 |
| 架构 | arm64 only |
| Bundle ID | com.serverhost.demo |
| 后台保活 | AVAudioEngine + AVAudioPlayerNode 静音循环 |
| 服务器地址 | 127.0.0.1:8080 |
| 静态资源 | set_base_dir 映射选中目录 |

## 注意事项

- App 使用 `UIDocumentPickerViewController` 选择文件，需要用户手动授权
- `chdir()` 是进程级全局操作，单服务器线程场景下安全
- 静音保活通过 `AVAudioSessionCategoryPlayback` + `MixWithOthers` 实现，不会影响其他音频播放
- 签名后 App 的有效期取决于你的 Apple ID 类型（免费 7 天，付费 1 年）
- 服务器仅监听 `127.0.0.1`，外部设备无法直接访问；如需外网访问请配合 OpenFrp
