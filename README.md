# AsmCross

> 屏幕中心十字准星辅助软件 (Crosshair Overlay) — 纯汇编实现

常驻屏幕正中央的视觉参考点，采用 MASM (x86) 编写，利用 Windows 原生 API 实现超轻量级、无感延迟的硬件级准星置顶显示。鼠标 100% 穿透，不干扰任何应用程序操作。

## 功能特性

- **中心锁定**：自动获取显示器物理分辨率，高精度对齐绝对中心点
- **鼠标穿透**：透明分层窗口 + `WS_EX_TRANSPARENT`，准星区域所有点击/拖拽穿透至下层
- **全局热键**：系统级快捷键控制，任意时刻响应
- **极低占用**：无 C 运行时依赖，纯 Win32 API 调用
- **反作弊合规**：仅外部透明 GDI 表面绘制，不读取/注入/修改任何第三方进程内存

## 快捷键

| 组合键 | 动作 | 行为 |
|--------|------|------|
| `Alt + F1` | 切换显示/隐藏 | 当前显示则擦除隐形（进程保留）；当前隐藏则刷新绘制并置顶 |
| `Alt + F2` | 完全退出 | 注销热键 → 销毁窗口 → 释放 GDI → 进程退出 |

## 准星图形规范

| 属性 | 值 |
|------|----|
| 形状 | 正十字 (Horizontal + Vertical) |
| 单边长 | 15 像素 |
| 总跨度 | 31 像素 (含中心列/行) |
| 线宽 | 2 像素 |
| 颜色 | 纯红 `RGB(255, 0, 0)` |
| 中心对齐 | 严格关于屏幕中心 `(⌊W/2⌋, ⌊H/2⌋)` 对称 |

> 绘制采用 `FillRect` + `CreateSolidBrush` 而非 `CreatePen` + `LineTo`，避免宽画笔端帽扩展导致的像素不对称问题。

## 构建方法

### 前置要求

- **Visual Studio 2022 Build Tools** (含 C++ 工作负载)
  - 提供 `ml.exe` (MASM 汇编器, x86)
  - 提供 `link.exe` (链接器)
- **Windows 10 SDK** (10.0.26100.0 或更高)
  - 提供 `kernel32.lib` / `user32.lib` / `gdi32.lib`

无需安装 MASM32 包，源码自包含全部常量、结构体与函数原型声明。

### 构建步骤

```cmd
build.bat
```

脚本自动完成：
1. 调用 `vcvars32.bat` 初始化 x86 构建环境
2. `ml /c /coff /Cp` 汇编 `Crosshair.asm`
3. `link /SUBSYSTEM:WINDOWS /ENTRY:start /NODEFAULTLIB` 生成 `Crosshair.exe`

构建产物：`Crosshair.exe` (约 4.5 KB)

## 使用方法

```cmd
Crosshair.exe
```

启动后准星立即显示在屏幕中心，驻留后台等待热键。

## 技术架构

### 窗口属性

```
ExStyle = WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOPMOST | WS_EX_TOOLWINDOW
Style   = WS_POPUP | WS_VISIBLE
```

- `WS_EX_LAYERED` + `SetLayeredWindowAttributes(LWA_COLORKEY)`：黑色为颜色键（透明），红色为不透明
- `WS_EX_TRANSPARENT`：鼠标点击穿透
- `WS_EX_TOPMOST`：始终置顶
- `WS_EX_TOOLWINDOW`：不在任务栏 / Alt+Tab 出现

### 消息循环

采用阻塞式 `GetMessage` 循环，静态显示时 CPU 占用趋近于 0%。仅在以下时刻进行计算：

- `WM_CREATE`：创建画刷 + 注册热键
- `WM_PAINT`：黑色背景填充 + 红色十字绘制（仅脏区）
- `WM_HOTKEY`：状态机切换显示/隐藏或退出
- `WM_DESTROY`：释放资源 + 退出

### DPI 感知

启动时调用 `SetProcessDPIAware`，确保 `GetSystemMetrics` 返回物理像素，在 2K/4K 高 DPI 显示器上中心对齐准确。

## 性能指标

| 指标 | 实测值 | 目标 |
|------|--------|------|
| 可执行文件大小 | 4.5 KB | — |
| 私有内存 (Private Bytes) | 1.77 MB | ≤ 2 MB |
| 静态 CPU 占用 | ~0.0% | 趋近 0 |
| 热键响应延迟 | < 5 ms | < 5 ms |
| 加载模块数 | 7 (WoW64 子系统) | — |

> 工作集 (Working Set) 在 64 位 Windows 上约 27 MB，主要由 WoW64 层共享系统 DLL (`ntdll.dll` / `wow64*.dll`) 贡献，非应用独占内存。在原生 32 位 Windows 上工作集会显著降低。

## 兼容性

| 系统 | 支持 | 说明 |
|------|------|------|
| Windows 10 (32 位) | ✓ | 原生运行 |
| Windows 10 (64 位) | ✓ | 通过 WoW64 子系统运行 |
| Windows 11 (64 位) | ✓ | 通过 WoW64 子系统运行 |

可执行文件为 x86 (i386) 架构，原生兼容 32 位系统，64 位系统通过 WoW64 子系统运行。

## 文件结构

```
AsmCross/
├── Crosshair.asm    # 主源码 (MASM 语法, 自包含)
├── build.bat        # 构建脚本 (VS 2022 x86 工具链)
├── Crosshair.exe    # 构建产物 (运行时生成)
├── Crosshair.obj    # 中间目标 (构建时生成)
└── README.md        # 本文档
```

## 反作弊合规说明

本软件**不**进行以下任何操作：

- ❌ 读取游戏进程内存 (`ReadProcessMemory` 等)
- ❌ 向游戏进程注入 DLL
- ❌ 修改游戏进程代码或数据
- ❌ 挂钩 (hook) 系统 API
- ❌ 与游戏进程进行任何 IPC 通信

软件仅使用 Windows 标准 API 在桌面合成层上绘制透明窗口，行为等同于系统自带的放大镜或屏幕键盘。是否被反作弊系统（Vanguard / EAC / BE 等）判定为违规，最终取决于各游戏厂商的服务条款。使用者需自行承担风险。

## 许可

本项目仅供学习与个人使用。
