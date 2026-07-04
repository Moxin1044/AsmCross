; =============================================================================
;  AsmCross - 屏幕中心十字准星辅助软件 (Crosshair Overlay)
;  SRS 实现源码 (MASM 语法, ml.exe / link.exe 工具链)
;
;  需求映射:
;    FR-1  中心锁定       -> GetSystemMetrics 计算物理中心
;    FR-2  图形规范       -> 30px 跨度 / 2px 线宽 / RGB(255,0,0)
;    FR-3  Alt+F1 切换    -> RegisterHotKey + WM_HOTKEY 状态机
;    FR-4  Alt+F2 退出    -> UnregisterHotKey + DestroyWindow
;    NFR-1 内存 <=2MB     -> 无 CRT / 全局静态数据极小
;    NFR-2 CPU ~0%        -> GetMessage 阻塞, 仅 WM_PAINT 微秒级计算
;    NFR-3 延迟 <5ms      -> 热键直投线程消息队列
;    NFR-4 Win10/11 兼容  -> 32 位子系统原生 API
;    NFR-5 反作弊合规     -> 仅透明 GDI 表面, 不读/注/改第三方内存
; =============================================================================

.586
.model flat, stdcall
option casemap:none

; ---------- 链接库 (Windows SDK 10.0.26100.0 um/x86) ----------
includelib kernel32.lib
includelib user32.lib
includelib gdi32.lib

; ============================================================================
; 常量定义
; ============================================================================

; --- 热键 ID (FR-3 / FR-4) ---
ID_HOTKEY_TOGGLE    equ 101
ID_HOTKEY_EXIT      equ 102

; --- 准星图形规范 (FR-2) ---
CROSS_HALF          equ 15          ; 单边 15 像素, 总跨度 30 像素
CROSS_WIDTH         equ 2           ; 线宽 2 像素
COLOR_CROSS         equ 000000FFh   ; 0x00BBGGRR : 纯红 RGB(255,0,0)
COLOR_KEY           equ 00000000h   ; 黑色作为分层颜色键 (透明)

; --- 扩展窗口风格 ---
WS_EX_LAYERED       equ 00080000h
WS_EX_TRANSPARENT   equ 00000020h   ; 鼠标穿透
WS_EX_TOPMOST       equ 00000008h   ; 置顶
WS_EX_TOOLWINDOW    equ 00000080h   ; 不在任务栏/Alt+Tab 出现

; --- 窗口风格 ---
WS_POPUP            equ 80000000h
WS_VISIBLE          equ 10000000h
WS_CLIPCHILDREN     equ 02000000h

; --- 窗口消息 ---
WM_CREATE           equ 0001h
WM_DESTROY          equ 0002h
WM_PAINT            equ 000Fh
WM_HOTKEY           equ 0312h

; --- 系统度量 ---
SM_CXSCREEN         equ 0
SM_CYSCREEN         equ 1

; --- 热键修饰键 / 虚拟键码 ---
MOD_ALT             equ 0001h
VK_F1               equ 70h
VK_F2               equ 71h

; --- ShowWindow 命令 ---
SW_HIDE             equ 0
SW_SHOW             equ 5

; --- SetWindowPos 标志 ---
SWP_NOSIZE          equ 0001h
SWP_NOMOVE          equ 0002h
SWP_NOACTIVATE      equ 0010h
HWND_TOPMOST        equ -1

; --- 分层窗口属性 ---
LWA_COLORKEY        equ 00000001h

; --- 库存对象 ---
BLACK_BRUSH         equ 4

; --- 画笔样式 ---
PS_SOLID            equ 0

; --- 窗口类风格 ---
CS_HREDRAW          equ 0002h
CS_VREDRAW          equ 0001h

; --- 默认菜单/光标 ---
IDC_ARROW           equ 32512

; --- 通用常量 ---
NULL                equ 0
TRUE                equ 1
FALSE               equ 0

; ============================================================================
; 结构体定义
; ============================================================================

RECT STRUCT
  left    DWORD ?
  top     DWORD ?
  right   DWORD ?
  bottom  DWORD ?
RECT ENDS

POINT STRUCT
  x DWORD ?
  y DWORD ?
POINT ENDS

WNDCLASSEX STRUCT
  cbSize          DWORD ?
  style           DWORD ?
  lpfnWndProc     DWORD ?
  cbClsExtra      DWORD ?
  cbWndExtra      DWORD ?
  hInstance       DWORD ?
  hIcon           DWORD ?
  hCursor         DWORD ?
  hbrBackground   DWORD ?
  lpszMenuName    DWORD ?
  lpszClassName   DWORD ?
  hIconSm         DWORD ?
WNDCLASSEX ENDS

PAINTSTRUCT STRUCT
  hdc           DWORD ?
  fErase        DWORD ?
  rcPaint       RECT <?>
  fRestore      DWORD ?
  fIncUpdate    DWORD ?
  rgbReserved   BYTE 32 dup(?)
PAINTSTRUCT ENDS

MSG STRUCT
  hwnd     DWORD ?
  message  DWORD ?
  wParam   DWORD ?
  lParam   DWORD ?
  time     DWORD ?
  pt       POINT <?>
MSG ENDS

; ============================================================================
; 函数原型 (Windows API - stdcall)
; ============================================================================

GetModuleHandleA            PROTO :DWORD
GetSystemMetrics            PROTO :DWORD
RegisterClassExA            PROTO :DWORD
CreateWindowExA             PROTO :DWORD,:DWORD,:DWORD,:DWORD,:DWORD,:DWORD,:DWORD,:DWORD,:DWORD,:DWORD,:DWORD,:DWORD
ShowWindow                  PROTO :DWORD,:DWORD
SetLayeredWindowAttributes PROTO :DWORD,:DWORD,:BYTE,:DWORD
SetWindowPos                PROTO :DWORD,:DWORD,:DWORD,:DWORD,:DWORD,:DWORD,:DWORD
GetMessageA                 PROTO :DWORD,:DWORD,:DWORD,:DWORD
TranslateMessage            PROTO :DWORD
DispatchMessageA            PROTO :DWORD
DefWindowProcA              PROTO :DWORD,:DWORD,:DWORD,:DWORD
RegisterHotKey              PROTO :DWORD,:DWORD,:DWORD,:DWORD
UnregisterHotKey            PROTO :DWORD,:DWORD
BeginPaint                  PROTO :DWORD,:DWORD
EndPaint                    PROTO :DWORD,:DWORD
CreateSolidBrush            PROTO :DWORD
DeleteObject                PROTO :DWORD
GetStockObject              PROTO :DWORD
FillRect                    PROTO :DWORD,:DWORD,:DWORD
PostQuitMessage             PROTO :DWORD
DestroyWindow               PROTO :DWORD
ExitProcess                 PROTO :DWORD
LoadCursorA                 PROTO :DWORD,:DWORD
SetProcessDPIAware          PROTO

; ============================================================================
; 数据段
; ============================================================================

.data
  ClassName     db "AsmCrossClass", 0
  IsVisible     dd 1                ; 准星显示状态: 1=显示, 0=隐藏

.data?
  hInstance     dd ?
  hWndMain      dd ?
  hBrushRed     dd ?
  ScreenW       dd ?
  ScreenH       dd ?
  CenterX       dd ?
  CenterY       dd ?
  wc            WNDCLASSEX <?>
  msg           MSG <?>
  ps            PAINTSTRUCT <?>
  rcClient      RECT <?>

; ============================================================================
; 代码段
; ============================================================================

.code

; ----------------------------------------------------------------------------
; WndProc - 窗口回调
; ----------------------------------------------------------------------------
WndProc PROC hWnd:DWORD, uMsg:DWORD, wParam:DWORD, lParam:DWORD

    .IF uMsg == WM_CREATE
        ; --- FR-2: 创建红色画刷 (一次创建, 复用至退出) ---
        ; 线宽通过 FillRect 矩形尺寸精确控制, 避免 CreatePen 端帽扩展
        invoke CreateSolidBrush, COLOR_CROSS
        mov hBrushRed, eax

        ; --- FR-3 / FR-4: 注册全局热键 ---
        invoke RegisterHotKey, hWnd, ID_HOTKEY_TOGGLE, MOD_ALT, VK_F1
        invoke RegisterHotKey, hWnd, ID_HOTKEY_EXIT,   MOD_ALT, VK_F2
        xor eax, eax
        ret

    .ELSEIF uMsg == WM_PAINT
        ; --- FR-1 / FR-2: 中心绘制十字 (FillRect 像素精确) ---
        invoke BeginPaint, hWnd, ADDR ps

        ; 用黑色 (颜色键) 填充整个客户区 -> 分层合成后变透明
        ; 仅绘制 ps.rcPaint 脏区, 减少开销 (满足 NFR-2/NFR-3)
        mov eax, ps.rcPaint.left
        mov rcClient.left, eax
        mov eax, ps.rcPaint.top
        mov rcClient.top, eax
        mov eax, ps.rcPaint.right
        mov rcClient.right, eax
        mov eax, ps.rcPaint.bottom
        mov rcClient.bottom, eax
        invoke GetStockObject, BLACK_BRUSH
        invoke FillRect, ps.hdc, ADDR rcClient, eax

        ; --- 水平线: 31x2 像素, 中心 (cx, cy) ---
        ; FillRect 区间 [left, right) x [top, bottom), 右下为 exclusive
        mov edx, CenterX
        mov ecx, CenterY
        mov eax, edx
        sub eax, CROSS_HALF           ; left   = cx - 15
        mov rcClient.left, eax
        mov eax, ecx
        sub eax, 1                    ; top    = cy - 1
        mov rcClient.top, eax
        mov eax, edx
        add eax, CROSS_HALF
        inc eax                       ; right  = cx + 16 (画到 cx+15)
        mov rcClient.right, eax
        mov eax, ecx
        add eax, 1                    ; bottom = cy + 1  (画到 cy)
        mov rcClient.bottom, eax
        invoke FillRect, ps.hdc, ADDR rcClient, hBrushRed

        ; --- 垂直线: 2x31 像素, 中心 (cx, cy) ---
        ; 注意: invoke FillRect 会破坏 EDX/ECX (caller-saved), 必须重新加载
        mov edx, CenterX
        mov ecx, CenterY
        mov eax, edx
        sub eax, 1                    ; left   = cx - 1
        mov rcClient.left, eax
        mov eax, ecx
        sub eax, CROSS_HALF           ; top    = cy - 15
        mov rcClient.top, eax
        mov eax, edx
        add eax, 1                    ; right  = cx + 1  (画到 cx)
        mov rcClient.right, eax
        mov eax, ecx
        add eax, CROSS_HALF
        inc eax                       ; bottom = cy + 16 (画到 cy+15)
        mov rcClient.bottom, eax
        invoke FillRect, ps.hdc, ADDR rcClient, hBrushRed

        invoke EndPaint, hWnd, ADDR ps
        xor eax, eax
        ret

    .ELSEIF uMsg == WM_HOTKEY
        mov eax, wParam

        .IF eax == ID_HOTKEY_TOGGLE
            ; --- FR-3: Alt+F1 切换显示/隐藏 ---
            not IsVisible
            and IsVisible, 1                  ; 确保非 0 即 1

            .IF IsVisible == 1
                invoke ShowWindow, hWnd, SW_SHOW
                invoke SetWindowPos, hWnd, HWND_TOPMOST, 0, 0, 0, 0,
                       SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE
            .ELSE
                invoke ShowWindow, hWnd, SW_HIDE
            .ENDIF

        .ELSEIF eax == ID_HOTKEY_EXIT
            ; --- FR-4: Alt+F2 完全关闭 ---
            invoke UnregisterHotKey, hWnd, ID_HOTKEY_TOGGLE
            invoke UnregisterHotKey, hWnd, ID_HOTKEY_EXIT
            invoke DestroyWindow, hWnd
        .ENDIF

        xor eax, eax
        ret

    .ELSEIF uMsg == WM_DESTROY
        ; --- FR-4: 释放 GDI 句柄 + 退出消息循环 ---
        .IF hBrushRed != 0
            invoke DeleteObject, hBrushRed
            mov hBrushRed, 0
        .ENDIF
        invoke PostQuitMessage, 0
        xor eax, eax
        ret

    .ENDIF

    invoke DefWindowProcA, hWnd, uMsg, wParam, lParam
    ret
WndProc ENDP

; ----------------------------------------------------------------------------
; WinMain - 主初始化与消息循环
; ----------------------------------------------------------------------------
WinMain PROC

    ; --- NFR-4: DPI 感知, 保证 GetSystemMetrics 返回物理像素 ---
    invoke SetProcessDPIAware

    ; --- FR-1: 获取屏幕物理分辨率, 计算绝对中心 ---
    invoke GetSystemMetrics, SM_CXSCREEN
    mov ScreenW, eax
    shr eax, 1                            ; eax = ScreenW / 2 (向下取整)
    mov CenterX, eax
    invoke GetSystemMetrics, SM_CYSCREEN
    mov ScreenH, eax
    shr eax, 1
    mov CenterY, eax

    ; --- 注册窗口类 ---
    mov wc.cbSize,        SIZEOF WNDCLASSEX
    mov wc.style,         CS_HREDRAW or CS_VREDRAW
    mov wc.lpfnWndProc,   OFFSET WndProc
    mov wc.cbClsExtra,    0
    mov wc.cbWndExtra,    0
    mov eax, hInstance
    mov wc.hInstance,     eax
    mov wc.hIcon,         0
    invoke LoadCursorA, 0, IDC_ARROW
    mov wc.hCursor,       eax
    mov wc.hbrBackground, 0                ; WM_PAINT 自行 FillRect
    mov wc.lpszMenuName,  0
    mov wc.lpszClassName, OFFSET ClassName
    mov wc.hIconSm,       0
    invoke RegisterClassExA, ADDR wc

    ; --- 创建全屏分层穿透置顶窗口 ---
    ;   ExStyle = WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOPMOST | WS_EX_TOOLWINDOW
    ;   Style   = WS_POPUP | WS_VISIBLE
    invoke CreateWindowExA,
           WS_EX_LAYERED or WS_EX_TRANSPARENT or WS_EX_TOPMOST or WS_EX_TOOLWINDOW,
           ADDR ClassName, ADDR ClassName,
           WS_POPUP or WS_VISIBLE,
           0, 0, ScreenW, ScreenH,
           0, 0, hInstance, 0
    mov hWndMain, eax

    ; --- 设置分层颜色键 (黑色=透明, 红色=不透明) ---
    invoke SetLayeredWindowAttributes, hWndMain, COLOR_KEY, 0, LWA_COLORKEY

    ; --- 强制置顶 (双保险) ---
    invoke SetWindowPos, hWndMain, HWND_TOPMOST, 0, 0, 0, 0,
           SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE

    ; --- NFR-2: 阻塞式消息循环, 静态时 CPU ~0% ---
    .WHILE TRUE
        invoke GetMessageA, ADDR msg, 0, 0, 0
        .BREAK .IF !eax                 ; eax=0 -> WM_QUIT, 退出循环
        invoke TranslateMessage, ADDR msg
        invoke DispatchMessageA, ADDR msg
    .ENDW

    mov eax, msg.wParam                 ; 退出码
    ret
WinMain ENDP

; ----------------------------------------------------------------------------
; 入口点
; ----------------------------------------------------------------------------
start:
    invoke GetModuleHandleA, NULL
    mov hInstance, eax
    invoke WinMain
    invoke ExitProcess, eax
end start
