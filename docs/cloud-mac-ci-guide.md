# 没有 Mac 时用云 Mac / CI 测试 iOS App

本文面向当前仓库 `InCaseI4Get.xcodeproj`（原生 SwiftUI 工程），介绍不使用本地 Mac 时如何：

1. 用 GitHub Actions 自带的 macOS 机器编译、跑模拟器并截图，验证 App 能跑起来。
2. 之后把正式安装包上传 TestFlight，用自己的 iPhone 做真机测试。

> 前提先说清楚：iOS 的最终编译、签名、上传必须由 Apple 的工具链完成，所以“云 Mac”不是绕过 Apple，而是把 Mac 换成按次/按分钟租用。模拟器验证这一阶段可以基本免费完成；上 TestFlight 需要 Apple Developer Program（每年 $99），这是无法省掉的上架硬成本。

## 阶段一：把代码推到 GitHub

### 1. 安装 Git

Windows 到 <https://git-scm.com/download/win> 下载安装 Git for Windows。

### 2. 创建 GitHub 仓库

1. 打开 <https://github.com/new>。
2. Repository name 填 `InCaseI4Get`。
3. 选择 Private 或 Public 都可以。Private 时 Actions 分钟数有限额但通常足够个人开发用。
4. 不要勾选 “Add a README / .gitignore / license”，否则推送前会出现冲突。
5. 点 Create repository。

### 3. 在当前目录初始化并推送

打开 PowerShell，进入当前目录后执行：

```powershell
cd D:\E\独立开发\InCaseI4Get
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/你的用户名/InCaseI4Get.git
git push -u origin main
```

如果第一次推送要求登录，GitHub 会弹出浏览器授权窗口，按提示完成即可。

## 阶段二：运行 GitHub Actions 云 Mac 构建

仓库里已经放好两个文件：

- `.github/workflows/ios-simulator-smoke.yml`
- `InCaseI4Get.xcodeproj/xcshareddata/xcschemes/InCaseI4Get.xcscheme`

其中 workflow 做这几件事：

1. 在 `macos-15` runner 上 checkout 代码。
2. 用 `xcodebuild` 编译 iOS Simulator 版本（不签名，因此不需要 Apple 开发者账号）。
3. 找一个可用的 iPhone 模拟器，启动 App，等待 12 秒后截图。
4. 把截图和模拟器日志作为 Artifact 上传，供你下载查看。

### 操作步骤

1. 推送完成后打开 GitHub 仓库页面。
2. 点顶部 **Actions**。
3. 左侧会看到 **iOS Simulator Smoke Test**。
4. 点右侧 **Run workflow** 再点绿色按钮，手动触发一次。
5. 等 3-10 分钟，任务结束后点进去。
6. 展开 **Boot simulator and launch app** 看日志；如果失败，日志中会有编译错误或崩溃信息。
7. 成功时页面底部会出现 **Artifacts** 区，下载 `ios-simulator-results`，里面是 `home.png` 截图和 `simulator.log`。

之后每次推送 `main` 分支都会自动触发这个检查。想要重新测试而不改代码，就再次 Run workflow。

## 阶段三：真机测试和 TestFlight

模拟器只能验证“界面、基本交互、能启动”；语音识别、系统通知、锁屏提醒、后台行为必须真机验证。没有本地 Mac 时，最省事的顺序是：

1. 加入 Apple Developer Program（每年 $99）：<https://developer.apple.com/programs/enroll/>。
2. 准备一台你自己的 iPhone，加入 TestFlight。
3. 让云端 Mac/CI 产出签名后的 `.ipa` 并上传 App Store Connect。
4. 在 TestFlight 中把 iPhone 添加为内部测试者并安装。

签名配置第一次做会涉及证书、Provisioning Profile、Bundle ID，本指南不做一键化保证，只说明两条可行路线。

### 路线 A：按小时租一台带图形界面的 Mac（首次配置最省心）

服务商包括 MacinCloud、MacStadium 等，也有国内代理服务。租用后：

1. 在浏览器或远程桌面里打开 Xcode。
2. 用你的 Apple 开发者账号登录。
3. 打开 `InCaseI4Get.xcodeproj`，把 Signing 里的 Team 选成你的开发者团队。
4. 连接或借用一台 iPhone 真机运行一次，确认签名正确。
5. 之后把 Xcode 自动生成的证书/Profile 处理好，再回 GitHub Actions 持续集成。

这种方案适合只用一两次、愿意为“省掉配置学习成本”付少量钱的情况。

### 路线 B：全部走 CI 自动签名

使用 GitHub Actions + fastlane，或 Codemagic 这类带 Apple 签名的移动 CI。通用流程是：

1. 在 Apple Developer 网站创建 App ID：`com.incasei4get.InCaseI4Get`。
2. 在 App Store Connect 的 “Users and Access → Integrations” 创建 App Store Connect API Key，下载 `.p8` 文件。
3. 把 API Key 的 Key ID、Issuer ID 和 `.p8` 内容保存为 GitHub Actions Secrets 或 CI 平台的变量。
4. 让 CI 自动生成并保存 Distribution Certificate 与 App Store Provisioning Profile。
5. CI 执行 `xcodebuild archive` → 导出 `.ipa` → 上传 App Store Connect。
6. 在 TestFlight 页面添加你的 Apple ID 作为内部测试者。

这条路免费额度较少、第一次配置步骤多，但长期无需 Mac。等到你决定走这一步时，可以再把本指南扩展为完整的 fastlane 配置。

## 常见问题

### 为什么 Flutter 也解决不了？

Flutter 只是开发框架。iOS 安装包仍然必须由 macOS 上的 Xcode 编译并签名；Windows 上只能跑 Android、Windows、Web 预览。

### GitHub Actions 的模拟器截图算“真实测试”吗？

不算。它只能尽早发现编译错误、启动崩溃和明显 UI 问题，不能替代真机。真机测试仍需 Apple Developer Program + TestFlight（或本地/租用 Mac 直连 iPhone）。

### 有没有完全免费的 iOS 真机测试？

Apple 没有提供。真机安装测试至少需要一个 Apple ID 签名环境；要长期稳定分发到自己的 iPhone，TestFlight 是最低门槛方案。
