# UU 风格定制客户端方案（基于 RustDesk 内核）

> 版本：v1 · 2026-11-19
> 状态：待确认，尚未改动任何代码
> 定位：个人/小范围使用的定制客户端，不是 UU 远程的 1:1 复刻

---

## 1. 结论先行

- **可以做**：UU 风格的界面与交互、手机端自定义悬浮按键、账号登录与设备列表同步、分阶段的 iOS 自打包。
- **不做/做不到**：复制 UU 的 Logo、图标、文案、界面素材；完全追平 UU 的商业级网络与低延迟；一次对话内整体替换。
- **建议顺序**：先做客户端体验（UI + 悬浮按键），账号同步优先用 Server Pro 快速打通，iOS 最后投入。
- **重要前提**：先把 Mac 被控端的「辅助功能」「输入监控」权限调通，确认基础远程操作可用，再在其上改 UI。

---

## 2. 现状盘点：哪些能力已经存在

| 能力 | 现状 | 关键位置 |
|---|---|---|
| 远程连接内核 | 完整（采集/编码/传输/输入） | `src/`、`libs/scrap/`、`libs/enigo/` |
| 地址簿 | 已有模型、UI、在线状态、最近连接 | `flutter/lib/models/ab_model.dart`、`peer_model.dart`、`common/widgets/peers_view.dart`、`peer_card.dart`、`address_book.dart` |
| 账号登录 | 客户端已实现，依赖 Pro/官方服务器 API | `flutter/lib/models/user_model.dart`、`common/widgets/login.dart`、`src/hbbs_http/account.rs` |
| 手机会话操作 | 鼠标/触摸模式、虚拟鼠标、虚拟摇杆、手势 | `mobile/pages/remote_page.dart`、`mobile/widgets/gesture_help.dart`、`floating_mouse*.dart` |
| 按键注入 | 已有 FFI，可直接发送组合键 | `session_input_key`（`src/flutter_ffi.rs:690`）、`session_input_string` |
| 鼠标注入 | 已有 FFI | `session_send_mouse`（`src/flutter_ffi.rs:1991`） |
| 悬浮层 | 已有可拖拽的 mobile actions overlay | `makeMobileActionsOverlayEntry`（`flutter/lib/common.dart:982`） |
| 服务端 | 开源 hbbs/hbbr 只有信令/中继，**没有账号 API** | 已部署在 `120.26.144.120` |
| iOS | 官方 App 可配置自建服务器；改代码后必须自打包 | `flutter/ios/`、`flutter/build_ios.sh` |

结论：**不需要从零写远程桌面**。要做的是在现有内核之上加一层 UU 风格的产品壳，以及账号/设备同步能力。

---

## 3. 目标体验（MVP）

### 3.1 首页

```
┌──────────────────────────────────────────────┐
│  Remote Desk                    [账号] [设置] │
├──────────────────────────────────────────────┤
│  本机 ID: 123 456 789   [复制]  密码 [显示]   │
├──────────────────────────────────────────────┤
│  我的设备                        [+ 添加设备] │
│  ┌────────────────┐  ┌────────────────┐      │
│  │ 🖥 家里台式机   │  │ 💻 公司 Mac     │      │
│  │ ● 在线  [连接]  │  │ ○ 离线          │      │
│  └────────────────┘  └────────────────┘      │
│  最近连接                                     │
│  · 公司 Mac        2 小时前        [连接]     │
└──────────────────────────────────────────────┘
```

- 登录/未登录两种状态；未登录时只显示本机 ID + 最近连接
- 设备卡片：名称、系统图标、在线状态、一键连接
- 最近连接、收藏、地址簿分组
- 本机 ID/密码复制、服务器配置入口

### 3.2 会话页（手机）

```
┌──────────────────────────────────────────────┐
│ [←] [☰]              远程画面            [⚙]  │
│                                              │
│                        ┌───┐                 │
│                        │ESC│                 │
│                        ├───┤   ┌────┐        │
│                        │WIN│   │Ctrl│        │
│                        ├───┤   ├────┤        │
│                        │TAB│   │Alt │        │
│                        └───┘   └────┘        │
└──────────────────────────────────────────────┘
```

- 可收起的顶栏，保留键盘、鼠标/触摸模式、显示设置、更多
- 自定义悬浮按键：位置、大小、透明度、组合键/鼠标/文本
- 虚拟鼠标、虚拟摇杆、手势保持现有能力

### 3.3 平台范围

- 第一阶段：**Windows、macOS、Android**
- 第二阶段：iOS（官方 App 先行，定制版后置）
- Linux 顺带保留，不作为重点测试目标

---

## 4. 架构与改造原则

1. **内核不动**：不改 `src/server/`、`libs/scrap/`、`libs/enigo/`，除非功能确实需要。
2. **新 UI 自包含**：新建 `flutter/lib/custom_ui/`，旧页面保留。
3. **入口只加薄钩子**：`home_page.dart` / `desktop_home_page.dart` 用一行开关决定进入新页面还是旧页面。
4. **Feature flag**：新增本地选项 `custom-ui`，关闭时完全走原逻辑，便于回退和对比。
5. **不复制 UU 素材**：布局和交互可以借鉴，视觉资产、文案、名称必须原创。
6. **新增文案走本地化流程**：尽量复用现有 key；必须新增时按项目规则追加到 `src/lang/*.rs`。

---

## 5. 四条工作流

### A. UI 改版（桌面 + Android）

**范围**
- 新首页：账号区、我的设备、最近连接、本机 ID/密码、添加设备
- 设备卡片：在线状态、系统图标、连接按钮、更多菜单
- 会话页：简化顶栏、可收起工具栏
- 主题：配色、字体、间距、圆角，形成统一的品牌感

**做法**
- 新建 `flutter/lib/custom_ui/`：
  - `home/`：首页、设备卡片、最近连接
  - `session/`：会话工具栏与浮层
  - `theme.dart`：主题
- 复用 `AbModel`、`PeerModel`、`peers_view.dart` 的数据和在线状态逻辑
- 移动端在 `HomePage.initPages()` 里选择新首页；桌面端在 `DesktopHomePage` 的 build 里选择
- 不改连接、文件传输、剪贴板等既有逻辑

**关键文件**
- `flutter/lib/mobile/pages/home_page.dart`（底部导航壳）
- `flutter/lib/mobile/pages/connection_page.dart`（现有连接页）
- `flutter/lib/desktop/pages/desktop_home_page.dart`
- `flutter/lib/common/widgets/peers_view.dart`、`peer_card.dart`、`address_book.dart`
- `flutter/lib/common.dart`（主题、overlay 基础设施）

**验收**
- 新首页能展示本机 ID、最近连接、地址簿设备与在线状态
- 点设备能发起连接并进入现有会话页
- `custom-ui = N` 时行为与现在完全一致
- macOS + Android 手动跑通

**工作量**：中

---

### B. 手机端自定义悬浮按键

**范围**
- 悬浮按键层：可拖动、可缩放、可隐藏
- 按键类型：
  - 组合键（如 Ctrl+C、Alt+Tab、Win+D）
  - 鼠标左/右/中键点击
  - 滚轮
  - 文本片段（如常用命令、密码之外的固定文本）
- 按键配置：标签、图标、大小、透明度
- 配置持久化：按设备或全局保存
- 编辑器：会话内长按或从设置进入，拖拽摆放

**做法**
- 复用现有能力，不新增 FFI：
  - 组合键：`bind.sessionInputKey(...)`（`session_input_key`）
  - 文本：`bind.sessionInputString(...)`
  - 鼠标：`session_send_mouse`
- 新建：
  - `flutter/lib/mobile/widgets/custom_buttons/overlay.dart`
  - `flutter/lib/mobile/widgets/custom_buttons/editor.dart`
  - `flutter/lib/models/custom_buttons_model.dart`（配置模型与持久化）
- 悬浮层参考 `makeMobileActionsOverlayEntry` 的拖拽与定位方式
- 只在按键区域拦截触摸，其余区域保持现有手势

**验收**
- 能向 Windows/macOS/Android 被控端发送组合键与鼠标点击
- 配置重启后保留，切换设备可切换配置
- 不影响原有单指/双指/三指手势
- Android 真机跑通；iOS 留到打包阶段验证

**工作量**：中
**风险**：输入事件的按下/抬起顺序、修饰键状态、软键盘冲突

---

### C. 账号 + 设备同步

#### 方案 C1：RustDesk Server Pro（推荐）

- 自部署 Pro 服务端，客户端填 ID/中继/API 服务器并登录
- 地址簿在各设备间同步，在线状态可见，无需改代码
- 限制：Pro 闭源、需要授权；界面仍是 RustDesk 风格
- 工作量：**小**
- 适用：想尽快拿到“登录后看到设备”的效果

#### 方案 C2：自建兼容账号服务

客户端已经在调用这些接口（节选）：

```
/api/login
/api/login-options
/api/logout
/api/currentUser
/api/ab
/api/ab/personal
/api/ab/peers
/api/ab/settings
/api/ab/shared/profiles
/api/ab/peer/add/
/api/ab/peer/update/
/api/ab/tags/
/api/ab/tag/add/
/api/ab/tag/update/
/api/ab/tag/rename/
/api/heartbeat
/api/sysinfo
/api/peers
/api/device-group/accessible
/api/audit/
```

要做的后端：

- 用户与 token、登录/登出
- 地址簿 CRUD、标签、共享地址簿
- 设备注册：客户端上报设备信息，按账号聚合
- 在线状态：心跳或扩展 hbbs 事件
- 审计日志（可选）

**做法**
- 独立 HTTP 服务监听 `21114`，与 hbbs/hbbr 并存
- 数据库：用户、设备、地址簿、设备条目、标签
- 客户端侧：登录后自动把本机设备加入“我的设备”；首页展示账号设备列表
- 先实现登录 + 个人地址簿 + 设备列表，其他接口返回最小可用响应

**验收**
- 两台客户端登录同一账号，看到同一设备列表
- 一台新增设备，另一台刷新可见
- 在线状态与 hbbs 实际状态一致

**工作量**：大（后端 + 客户端适配 + 联调）
**风险**：接口未公开、字段兼容、安全与维护成本

**建议**：先用 C1 验证需求；如果授权成本或闭源不可接受，再启动 C2。

---

### D. iOS 打包与分发

| 方式 | 成本 | 限制 |
|---|---|---|
| App Store 官方 App | 免费 | 不能改 UI，只能配置服务器/账号 |
| 免费 Apple ID + Xcode | 免费 | 7 天过期，每周重签，最多 3 个 App |
| 付费开发者账号 Ad Hoc | $99/年 | 最多 100 台注册设备，证书 1 年 |
| TestFlight | $99/年 | 每个构建 90 天，外部测试需审核 |
| App Store 上架 | $99/年 | 审核 + AGPL 源码义务 |

**构建链**
- Xcode + Flutter + Rust iOS target + vcpkg
- `flutter/build_ios.sh` 使用 `flutter build ipa --release`
- 只改 Dart UI 不需要重新跑 `flutter_rust_bridge_codegen`
- 新增 FFI 才涉及 codegen，按项目规则手写 Dart wrapper

**建议**
- 第一阶段 iOS 继续用官方 App，保证“随时随地能连”
- UI 和悬浮按键在 Android 上稳定后，再评估 iOS 自打包
- 如果只是个人使用，免费 Apple ID 的 7 天重签不可接受，建议直接上付费开发者账号

**工作量**：大（首次搭建签名与流水线）
**风险**：证书/描述文件、审核、AGPL 分发义务

---

## 6. 里程碑

| 里程碑 | 交付物 | 验收标准 | 规模 |
|---|---|---|---|
| M0 | 本方案 + 设计草图 | 你确认范围与优先级 | 文档 |
| M1 | UU 风格首页静态原型（桌面 + Android） | 可运行、可导航、假数据展示 | 中 |
| M2 | 首页接入真实数据 | 最近连接、地址簿、在线状态、一键连接 | 中 |
| M3 | 悬浮按键 MVP | 组合键/鼠标/文本、布局、持久化 | 中 |
| M4 | 账号与设备同步 | C1：Pro 打通；C2：自建服务 | 小 / 大 |
| M5 | 会话页与主题打磨 | 工具栏、动效、性能、细节 | 中 |
| M6 | iOS 定制构建与分发 | 签名 IPA 可安装；TestFlight 可选 | 大 |

每个里程碑都可以独立使用，不会出现“做到一半不能用”的状态。

---

## 7. 改动面与回归控制

**新增文件为主**
- `flutter/lib/custom_ui/**`（新 UI）
- `flutter/lib/models/custom_buttons_model.dart`
- `flutter/lib/mobile/widgets/custom_buttons/**`
- 账号同步（C2）时新增独立后端目录

**修改的现有文件（薄钩子）**
- `flutter/lib/mobile/pages/home_page.dart`：选择新首页
- `flutter/lib/desktop/pages/desktop_home_page.dart`：选择新首页
- `flutter/lib/models/input_model.dart`：如悬浮按键需要复用发送逻辑，只加公开方法，不改原路径
- `libs/base/src/config/keys.rs`：新增 `custom-ui` 等开关

**不动的部分**
- Rust 连接内核、采集、输入
- 现有会话页、文件传输、剪贴板逻辑
- 已部署的 hbbs/hbbr（C2 时只新增 21114 服务）

**测试**
- Dart widget 测试放在 `flutter/test/*_test.dart`
- 手动矩阵：macOS 控制端、Android 控制端；Windows/macOS 被控端
- 每次里程碑都验证 `custom-ui = N` 时旧路径不回归

---

## 8. 风险与合规

1. **上游分叉**：UI 大改后与 RustDesk 上游同步成本高，需要接受长期 fork。
2. **AGPL-3.0**：自己用没问题；分发给他人（含 TestFlight）需按协议提供源码。
3. **版权/商标**：不复制 UU 的视觉素材、图标、文案、名称；只借鉴交互模式。
4. **账号后端兼容性**：C2 依赖客户端现有接口，Pro 升级可能改变字段；需要锁定版本并做回归。
5. **iOS 分发**：Apple 限制无法绕过；免费签名 7 天过期。
6. **性能**：悬浮按键层要保持轻量，避免影响画面帧率。
7. **本地化成本**：新 UI 文案需要走 `src/lang` 流程，建议尽量复用现有 key。

---

## 9. 需要你确认的决策

1. **账号后端**：Server Pro（快、付费）还是自建兼容服务（慢、可控）？
2. **平台优先级**：是否接受 Windows/macOS/Android 先行、iOS 后置？
3. **UI 还原度**：要“神似 UU”还是“类似但保持自己的风格”？
4. **悬浮按键范围**：只做组合键/鼠标/文本，还是要游戏式的按键映射与宏？
5. **iOS 时间点**：现在就投入自打包，还是先用官方 App？
6. **是否长期维护 fork**：接受与上游分叉，还是尽量保持可合并？

---

## 10. 建议的下一步

1. 先完成 Mac 被控端权限配置，验证基础远程操作可用。
2. 你确认第 9 节的决策后，我从 **M1（桌面 + Android 首页静态原型）** 开始。
3. M1 完成后你先看效果，再决定是否继续 M2/M3。

> 本文档只是方案，没有改动任何代码。
