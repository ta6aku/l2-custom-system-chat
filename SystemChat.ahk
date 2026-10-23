#Requires AutoHotkey v2.0
#SingleInstance Force

#include "lib\ImagePut.ahk"
#Include "lib\Class_LV_Colors.ahk"


; Проверяем основной конфиг файл
global configPath := A_ScriptDir "\ChatConfig.ini"
    if !FileExist(configPath) {
        MsgBox("ChatConfig.ini not found: " configPath, "Error", 0x10)
        ExitApp
    }


; Настраиваем трассировку
global DEBUG_MODE := false
DEBUG_MODE := (IniRead(configPath, "Options", "DEBUG_MODE", "false") = "true")

if (DEBUG_MODE){
    global LogFile := FileOpen(A_ScriptDir "\debug_log.txt", "a")
    SetTimer(() => LogFile.Read(0), 10000) ; условным чтением 0 байт вызываем сброс накопленных данных из кэша в файл.
    OnError(ErrorFunc)
}

OnExit(ExitFunc)

LogDebug(msg) {
    try {
		static threadID := DllCall("GetCurrentThreadId")
        LogFile.WriteLine(FormatTime(, "HH:mm:ss") . "." . A_MSec . " [tID " . threadID . "] " . msg)
    }
}

(DEBUG_MODE) && LogDebug(Format("`n*****************************************************************`n******************************СТАРТ******************************`n*****************************************************************`nSystemChat Config Path:`n" configPath))



; Проверяем, подготовлен ли файл фона
ChatBkgrndPath := A_ScriptDir "\resources\CustomSystemChatBkgrnd.png"
if !FileExist(ChatBkgrndPath) {
    MsgBox("Ошибка! Файл фона не найден по пути:`n" ChatBkgrndPath "`n`nЗапустите Конфигуратор и настройте программу", "Error", 0x10)
	ExitApp
}


; Рассчитываем положение системного чата
try {
	ChatHeight := IniRead(configPath, "AdditionalChat", "ChatHeight")
    ChatPosY := IniRead(configPath, "AdditionalChat", "ChatPosY")
    ChatPosManual := (IniRead(configPath, "AdditionalChat", "ChatPosManual", "false") = "true")
    if ChatPosManual {
        ChatPosX := IniRead(configPath, "AdditionalChat", "ChatPosX", "0")
    }
    else {
        ChatPosX := 0
    }
    (DEBUG_MODE) && LogDebug(Format("ChatPosX: " ChatPosX "   ChatPosY: " ChatPosY "   ChatHeight: " ChatHeight))
}
catch Error as err {
    ErrorFunc(err, "Thrown")
    MsgBox("Failed to parse ChatConfig.ini", "Error", 0x10)
	ExitApp
}

global NoIntegr := true


;------------------------------------------------------------------------------------------------------

; Загружаем конфиг фильтрации ID -> Color
global MsgColorMap := Map()
LoadMsgFilterConfig()

LoadMsgFilterConfig() {
    global MsgColorMap
    try {
        ; Без третьего параметра IniRead возвращает строку "ключ=значение`nключ2=значение2"
        sectionContent := IniRead(configPath, "MsgFilter")
    } catch Error as err {
        ErrorFunc(err, "Thrown")
        MsgBox("Failed to parse ChatConfig.ini", "Error", 0x10)
        ExitApp
    }

    ; Парсим полученную строку
    Loop Parse, sectionContent, "`n", "`r" {
        if (A_LoopField = "")
            continue
        pos := InStr(A_LoopField, "=")
        if pos {
            id := Trim(SubStr(A_LoopField, 1, pos-1))
            color := Trim(SubStr(A_LoopField, pos+1))
            if (id ~= "^\d+$" && color ~= "^0x[0-9A-Fa-f]{6}$") {
                MsgColorMap[id] := color
            }
        }
    }
    (DEBUG_MODE) && LogDebug(Format("Loaded " MsgColorMap.Count " ID->Color mappings from ChatConfig.ini"))
}


DefaultTextColor := "0xB09979"
DefaultBackColor := "0x1D1D1D"
DefaultTransColor := "0xABCDEF"

global BlackBkgrnd := (IniRead(configPath, "AdditionalChat", "BlackBkgrnd", "false") = "true")
(BlackBkgrnd) ? (BkColor := DefaultBackColor) : (BkColor := DefaultTransColor)

GAMECHAT_WIDTH := 345
VisibleW := GAMECHAT_WIDTH - (24 + 2) ; 24px - условный скроллбар слева, 2px - толщина контура (обводки) окна
VisibleH := ChatHeight - 4 ; 2px сверху и 2px снизу на контур окна



; 1. Окно для фоновой картинки и кнопок управления
global wBkgrnd := Gui("-SysMenu -Caption -Border -DPIScale")
wBkgrnd.Title := "L2_SystemChat_Bkgrnd"
wBkgrnd.BackColor := "" BkColor
WinSetTransColor("ABCDEF", wBkgrnd) ; делаем прозрачным по цвету "0xABCDEF"

ChatBkgrnd := ImageShow(A_ScriptDir "\resources\CustomSystemChatBkgrnd.png",, [0, 0, GAMECHAT_WIDTH, ChatHeight], 0x40000000 | 0x10000000 | 0x08000000,, wBkgrnd.hwnd, False) ; Флаги: 0x40000000 (WS_CHILD) | 0x10000000 (WS_VISIBLE) | 0x08000000 (WS_DISABLED)



; 2. Отдельное окно для таблицы (чтобы не пытаться управлять прозрачностью слоев в рамках одного gui. Это окно будем отрисовывать поверх фоновой картинки)
global wSysChat := Gui("-SysMenu -Caption -Border -DPIScale +E0x80000") ; +E0x80000 = WS_EX_LAYERED
wSysChat.Title := "L2_SystemChat" ; это имя прописано в .dll
;wSysChat.SetFont("s10 q3", "Segoe UI")
wSysChat.BackColor := "" BkColor
WinSetTransColor("ABCDEF", wSysChat)



; 3. Отдельное прозрачное окно для перехвата кликов по области
global wCtrls := Gui("-SysMenu -Caption -Border -DPIScale")
wCtrls.Title := "L2_SystemChat_CtrlsZone"




; 4. Привязка к Lineage 2
SetTitleMatchMode "RegEx"
;DetectHiddenWindows(True)
global L2Class := "ahk_class (?i)^L2UnrealWWindowsViewportWindow$"
global L2Hwnd := WinExist(L2Class)

if L2Hwnd {
    if !NoIntegr {
        DllCall("SetParent", "ptr", wSysChat.Hwnd, "ptr", L2Hwnd) ; TODO: NoIntegr не менять, в текущей реализации окна метод через SetParent не работает
    }
    else {
        wBkgrnd.Opt("+Owner" L2Hwnd)
        wSysChat.Opt("+Owner" wBkgrnd.HWnd)
        wCtrls.Opt("+Owner" wBkgrnd.HWnd)
    }
    wBkgrnd.Show("NA x" ChatPosX " y" ChatPosY " w" GAMECHAT_WIDTH " h" ChatHeight)
    wSysChat.Show("NA x" ChatPosX+24 " y" ChatPosY+2 " w" VisibleW " h" VisibleH)
    wCtrls.Show("NA x" ChatPosX+3 " y" ChatPosY+3 " w18 h" VisibleH-3) ; 3px отступ от края , 18px - на 1px слева и справа больше, чем иконки (16px) кнопок
    WinSetTransparent(1, "L2_SystemChat_CtrlsZone") ; wCtrls
}
else {
    ExitApp
}


; Создаем ListView более широкий, чем сумма ширин столбцов, чтобы скроллбар ушел за видимый край
; Второй столбец делаем нулевого размера (скрытым)
global LV := wSysChat.AddListView("x0 y0 w" (VisibleW + 45) " h" (VisibleH) " -Hdr -Multi -E0x200 +LV0x14000 Background" BkColor " c" DefaultTextColor, ["Msg", "Color"]) ; LVS_EX_DOUBLEBUFFER = 0x00010000 ,  LVS_EX_JUSTIFYCOLUMNS = 0x00004000 ,  WS_EX_CLIENTEDGE = E0x200
LV.ModifyCol(1, VisibleW + 25)
LV.ModifyCol(2, 0)

LV.DefineProp("Shadows", {Value: (IniRead(configPath, "AdditionalChat", "UseShadows", "true") = "true")})
DisableFontAntialiasing(LV.Hwnd)

global LV_ColorManager := LV_Colors(LV)


;------------------------------------------------------------------------------------------------------
if (DEBUG_MODE) {
    ; Заполнение для теста
    LV.Add(, "", "")
    LV.Add(, "Проверка шрифта на читаемость", "")
    LV.Add(, "Шрифт: Segue,  10", "")
    LV.Add(, "......................................", "")
    LV.Add(, "0O08B389 1lI1l1Ii b6b ч4чб6б  З3З", "")
    LV.Add(, "unusual autumn million Illustration", "")
    LV.Add(, "clean viola shrnoen running yarn", "")
    LV.Add(, "люминисцент шиншилла осенний расщелина", "")
    LV.Add(, "KpuBbleMakapoHbl JIoxyLLIka IIbl}|{ LLblIIJIeHoKuLLblraH", "")
    LV.Add(, "......................................", "")
    Loop 9 {
        LV.Add(, "Добро пожаловать в мир Lineage IIl  # " A_Index, "")
    }
    global LineCounter := 20
}
else {
    global LineCounter := 1
}

DisableFontAntialiasing(hwnd) {
    ; Получаем текущий шрифт элемента
    currentFont := DllCall("SendMessage", "ptr", hwnd, "uint", 0x0031, "ptr", 0, "ptr", 0, "ptr") ; WM_GETFONT

    ; Создаем структуру для изменения параметров шрифта
    LOGFONT := Buffer(92, 0)
    DllCall("GetObject", "ptr", currentFont, "int", 92, "ptr", LOGFONT)

    ; Меняем качество шрифта (смещение 26) на NONANTIALIASED_QUALITY (значение 3)
    NumPut("uchar", 3, LOGFONT, 26)

    ; Создаем новый четкий шрифт и применяем его
    newFont := DllCall("CreateFontIndirect", "ptr", LOGFONT, "ptr")
    DllCall("SendMessage", "ptr", hwnd, "uint", 0x0030, "ptr", newFont, "ptr", 1) ; WM_SETFONT
}


;------------------------------------------------------------------------------------------------------
; Кнопка Свернуть/Развернуть чат.

HideIcon := ImageShow(A_ScriptDir "\resources\HideIcon.png",, [4, 3, 16, 16], 0x40000000 | 0x10000000 | 0x08000000,, ChatBkgrnd, False)
RestoreIcon := ImageShow(A_ScriptDir "\resources\RestoreIcon.png",, [4, 3, 16, 16], 0x40000000 | 0x10000000 | 0x08000000,, wBkgrnd.hwnd, False)
WinHide(RestoreIcon)

fbtnHideRestore := wCtrls.AddText("x3 y3 w16 h14 +Center Background", " ") ; fake кнопка для перехвата клика
fbtnHideRestore.OnEvent("Click", MinimizeRestore)

global isHidden := false

MinimizeRestore(*) {
    global isHidden

    if (isHidden) {     ; если чат был скрыт - восстанавливаем
        ;btnLastStr.SetFont("c" DefaultTextColor)
        wSysChat.Show()
        WinShow(ChatBkgrnd)
        WinHide(RestoreIcon)
        WinShow(HideIcon)
        WinRedraw(wBkgrnd.Hwnd)
        wCtrls.Move(ChatPosX+3, ChatPosY+3, 18, VisibleH-3)
        isHidden := false
    }
    else {      ; скрываем чат
        ;btnLastStr.SetFont("c" DefaultTransColor)
        wSysChat.Hide()
        WinHide(ChatBkgrnd)
        WinHide(HideIcon)
        WinShow(RestoreIcon)
        wCtrls.Move(ChatPosX+3, ChatPosY+3, 18, 18)
        isHidden := true
    }
}

; Кнопка прокрутки сообщений в самый низ
ScrollDownIcon := ImageShow(A_ScriptDir "\resources\ScrollDownIcon.png",, [3, ChatHeight - 20, 16, 16], 0x40000000 | 0x10000000 | 0x08000000,, ChatBkgrnd, False)
WinHide(ScrollDownIcon)
fbtnScrollBottom := wCtrls.AddText("x3 y" ChatHeight-18 " w16 h14 +Center Background", " ") ; fake кнопка для перехвата клика
fbtnScrollBottom.OnEvent("Click", ScrollToLastStr)


global IsUserScrolling := false ; флаг, что чат прокручен вверх и что надо показать кнопку "прокрутить вниз"

ScrollToLastStr(*) {
    global IsUserScrolling

    IsUserScrolling := false
    LV.Modify(LV.GetCount(), "Vis")
    WinHide(ScrollDownIcon)
}


A_HotkeyInterval := 2000
A_MaxHotkeysPerInterval := 200 ; чтобы не выводилась ошибка, если быстро вращать колесико; default 70

CoordMode "Mouse", "Client"


#HotIf WinActive("L2_SystemChat_CtrlsZone") || WinActive("L2_SystemChat_Bkgrnd")

    ~WheelUp:: {
        global IsUserScrolling

        IsUserScrolling := true
        ;btnLastStr.Opt("-Hidden")
        WinShow(ScrollDownIcon)
        ScrollLV(-2)
    }

    ~WheelDown:: {
        global IsUserScrolling

        ScrollLV(1)
        ;Sleep(16)

        BottomIndex := LV_GetBottomIndex(LV)
        TotalRows := LV.GetCount()

        if (BottomIndex >= TotalRows) {
            IsUserScrolling := false
            ;btnLastStr.Opt("+Hidden")
            WinHide(ScrollDownIcon)
        } else {
            IsUserScrolling := true
        }
    }

#HotIf


;------------------------------------------------------------------------------------------------------
; Автоматическая прокрутка чата с получением нового события только в том случае, если чат в самом низу (проверяем, видна ли нижняя строчка через запрос индекса верхней видимой строки и расчет индекса нижней строки)
; LVM_GETTOPINDEX := 0x1027 индекс самой верхней видимой строки (WinAPI возвращает 0-based, для работы с таблицей AHKv2 (1-based) надо прибавить 1, но так как потом будем вычитать для расчета нижнего, то опускаем это действие
; LVM_GETCOUNTPERPAGE := 0x1028 количество строк, которые физически помещается в видимую область
; Нижний видимый индекс — это верхний + количество строк на страницу - 1

LV.GetPos(,,, &LV_ClientHeight)
global RowsPerPage := SendMessage(0x1028, 0, 0, LV)
global LV_ItemHeight := LV_ClientHeight / RowsPerPage


LV_GetBottomIndex(LVControl) {
    TopIndex := SendMessage(0x1027, 0, 0, LVControl) ; + 1
    return TopIndex + RowsPerPage ; - 1
}


ScrollLV(Rows) {
    ; LVM_SCROLL = 0x1014
    DllCall("SendMessage", "Ptr", LV.Hwnd, "UInt", 0x1014, "Ptr", 0, "Ptr", Rows * LV_ItemHeight)
}


; Функция проверки положения мыши
IsMouseOverChat() {
    MouseGetPos(,, &WindowHwnd, )
    return (WindowHwnd == wSysChat.Hwnd)
}

; Блокировка выделения строк
OnMessage(0x0201, PreventAllClicks) ; WM_LBUTTONDOWN
OnMessage(0x0203, PreventAllClicks) ; WM_LBUTTONDBLCLK
OnMessage(0x0204, PreventAllClicks) ; WM_RBUTTONDOWN

PreventAllClicks(wParam, lParam, msg, hwnd) {
    global LV
    if (hwnd == LV.Hwnd) {
        return 0
    }
}


;------------------------------------------------------------------------------------------------------
; Регистрируем обработчик для сообщения WM_COPYDATA (0x004A)

MAX_MSG_LENGTH := 62

global EventQueue := []
OnMessage(0x004A, ReceiveData)


ReceiveData(wParam, lParam, msg, hwnd) {
    global EventQueue, MsgColorMap

    msgId := NumGet(lParam, 0, "UPtr") ; dwData (ID сообщения)
    textPtr := NumGet(lParam, A_PtrSize * 2, "UPtr") ; lpData (указатель на строку)
    textString := StrGet(textPtr, "UTF-16")

    ;(DEBUG_MODE) && LogDebug(Format("`nReceiveData: msgId=" msgId " text=" textString)

    idStr := "" msgId                                       ; ключи в MsgColorMap — строки, поэтому приводим msgId тоже к строковому типу данных
    if (!MsgColorMap.Has(idStr) || (textString = "")) {     ; отфильтровываем и для случая не заданного цвета в конфиге, и для пустой строки в sysmsg-e.txt
        return true
    }

    EventQueue.Push({num: msgId, text: textString, color: MsgColorMap[idStr]})
    SetTimer(ProcessQueue, -1)

    return true
}

; Функция обработки очереди событий, разбираем по одному событию за раз по принципу FIFO
ProcessQueue() {
    global EventQueue, LV_ColorManager, LV, LineCounter
    static isCleaning := false

    if (isCleaning) {
        return
    }

    ; Замораживаем отрисовку ListView на время добавления, чтобы не было мерцания ; TODO попросить ВЛ-а пофармить парики с сосками и понаблюдать, как себя ведет при отрисовке большого числа ивентов за раз.
    LV.Opt("-Redraw")

    while (EventQueue.Length > 0) {

            if (LV.GetCount() >= LV_STR_MAX) {
                isCleaning := true
                OptimizeListView(LV, LV_ColorManager)
                isCleaning := false
            }

        currentEvent := EventQueue.RemoveAt(1)
        Num := currentEvent.num
        Str := currentEvent.text
        Color := currentEvent.color

        if (StrLen(Str) <= MAX_MSG_LENGTH) {
            LV.Add(, Str, Color)
            CurrentRow := LV.GetCount()
            LV_ColorManager.UpdateProps()   ; вызываем UpdateProps() после добавления, но перед перекраской, чтобы принудительно синхронизировать с реальным состоянием ListView в памяти Windows
            LV_ColorManager.Row(CurrentRow, "", Color)
        }
        else {
            AddLongMsg(Str, Color, MAX_MSG_LENGTH)
            CurrentRow := LV.GetCount()
        }

        LineCounter++
    }

    LV.Opt("+Redraw")
    ;LV.Redraw()

    if (!IsUserScrolling) {     ; автоматическая прокрутка чата с получением нового события только в том случае, если чат в самом низу
        LV.Modify(CurrentRow, "Vis")
    }
}

; Функция обработки (разбиения) длинной строки
AddLongMsg(text, color, maxChars) {
    global LV, LV_ColorManager

    pos := 1
    linesArray := []

    ; Ищем максимально длинный кусок, такой чтобы заканчивался на границе слова или пробеле (первая группа регулярки (.{1," maxChars "})(?:\s+|$)). Если не получилось - то просто откусим maxChar символов (вторая группа(.{1," maxChars "}))
    while (pos := RegExMatch(text, "s)(.{1," maxChars "})(?:\s+|$)|(.{1," maxChars "})", &match, pos)) {

        chunk := match[1] !== "" ? match[1] : match[2]
        linesArray.Push(chunk)
        pos += match.Len(0) ; сдвигаем позицию поиска на длину всего совпадения (включая съеденные пробелы-разделители)

        ; Предотвращение бесконечного цикла, если позиция не сдвинулась
        if (match.Len(0) == 0)
            break
    }

    for index, line in linesArray {
        ; Если кусок текста после разбивки оказался пустым (например, избыточные пробелы на стыке),
        ; но это не одиночная "пустая строка отступа", мы его пропускаем, чтобы чат не расплывался.
        if (Trim(line) == "" && linesArray.Length > 1)
            continue

        LV.Add(, line, color)
        LV_ColorManager.UpdateProps()
        LV_ColorManager.Row(LV.GetCount(), "", color)
    }
}


LV_STR_MAX := 2500 ; по достижении этого количества строк частично очищаем таблицу от старых событий
LV_STR_TO_SAVE := 1500 ; количество сохраняемых строк

; Производительности для отображаем только часть сообщений, остальные удаляем. Используем временный массив для сохранения данных и заполнение таблицы с нуля, так как удаление из стандартного ListView возможно только построчно, а каждое удаление из начала таблицы вызывало бы перестроение всей таблицы и необходимость синхронизации цветов, так как Classic_LV_Colors автоматически этого не делает.
OptimizeListView(LV, CLV) {
    ; 1. Замораживаем прерывания потоков на момент чтения из ListView
    ; AHKv2 сам вернет критичность к обычному уровню при завершении функции
    Critical(true)

    SavedRows := []
    TotalRows := LV.GetCount()

    StartRow := TotalRows - LV_STR_TO_SAVE ; сохраняем последние строки
    if (StartRow < 1)
        StartRow := 1

    currentIdx := StartRow
    while (currentIdx <= TotalRows) {
        try {
            TextVal  := LV.GetText(currentIdx, 1)
            ColorVal := LV.GetText(currentIdx, 2)
            SavedRows.Push({text: TextVal, color: ColorVal})
        } catch {
            ; Если строка заблокирована или пропала, просто пропускаем её
            OutputDebug("AHK Warning: Failed to get text for row " currentIdx)
        }
        currentIdx++
    }

    ; 2. Пересобираем таблицу
    LV.Opt("-Redraw")
    LV.Delete()
    CLV.Clear()

    ; 3. Вставляем строку-таймштамп для информативности
    TimestampText := "[ " FormatTime(, "HH:mm:ss") "]: Archived"
    LV.Add(, TimestampText, "0x888888")
    CLV.UpdateProps()
    CLV.Row(LV.GetCount(), "", 0x888888)

    ; 4. Возвращаем сохраненные строки обратно
    for RowData in SavedRows {
        LV.Add(, RowData.text, RowData.color)
        CurrentRow := LV.GetCount()
        CLV.UpdateProps()
        CLV.Row(CurrentRow, "", RowData.color)
    }

    LV.Opt("+Redraw")
}


;------------------------------------------------------------------------------------------------------
; Если не используется SetParent (пока что сейчас всегда так), выгружаемся сами при получении сообщения о завершении процесса

Hook := DllCall("SetWinEventHook"
    , "UInt", 0x8001 ; EVENT_OBJECT_DESTROY
    , "UInt", 0x8001
    , "Ptr", 0
    , "Ptr", CallbackCreate(OnWindowDestroy, "F")
    , "UInt", 0
    , "UInt", 0
    , "UInt", 0)

OnWindowDestroy(hWinEventHook, event, hwnd, idObject, idChild, dwEventThread, dwmsEventTime) {
    if (idObject = 0 && !WinExist(L2Class)) {
        DllCall("UnhookWinEvent", "Ptr", Hook)
        ExitApp
    }
}



ErrorFunc(Exception, Mode) {
    global LogFile

    if (DEBUG_MODE && LogFile) {
        errMsg := "`n[КРИТИЧЕСКАЯ ОШИБКА] " FormatTime(, "yyyy-MM-dd HH:mm:ss") "`n"
        errMsg .= "Сообщение: " Exception.Message "`n"
        errMsg .= "Файл: " Exception.File "`n"
        errMsg .= "Строка: " Exception.Line "`n"
        errMsg .= "Причина: " Exception.What "`n"
        errMsg .= "*****************************************************************`n"

        LogFile.Write(errMsg)
        LogFile.Read(0)
    }

    ; Возвращаем 0, чтобы AHK показал стандартное диалоговое окно ошибки и завершил работу.
    ; Если вернуть 1, скрипт попытается продолжить работу, проигнорировав ошибку.
    return 0
}

ExitFunc(ExitReason, ExitCode) {
    global LogFile

    if (DEBUG_MODE && LogFile) {
		LogDebug("--- Скрипт завершен (Причина: " ExitReason ")`n*****************************************************************")
		LogFile.Close()
	}
    ;global FontFile
    ;DllCall("RemoveFontResource", "Str", FontFile)
    ;DllCall("SendMessage", "Ptr", 0xFFFF, "UInt", 0x001D, "Ptr", 0, "Ptr", 0)
}
