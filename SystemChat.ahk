#Requires AutoHotkey v2.0
#SingleInstance Force

#include "lib\ImagePut.ahk"
#Include "lib\Class_LV_Colors.ahk"


ChatBkgrndPath := A_ScriptDir "\resources\CustomSystemChatBkgrnd.png"

if !FileExist(ChatBkgrndPath) {
    MsgBox("Ошибка! Файл фона не найден по пути:`n" ChatBkgrndPath, "Error", 0x10)
	ExitApp
}

DefaultTextColor := "0xB09979"
DefaultBackColor := "0x1D1D1D"

global NoIntegr := true


CoordMode "Mouse", "Client"
;------------------------------------------------------------------------------------------------------

; Загружаем конфиг фильтрации ID -> Color
global MsgColorMap := Map()
LoadMsgFilterConfig()

LoadMsgFilterConfig() {
    global MsgColorMap
    configPath := A_ScriptDir "\ChatConfig.ini"
    if !FileExist(configPath) {
        OutputDebug("AHK: ChatConfig.ini not found: " configPath)
        return
    }

    try {
        ; Без третьего параметра IniRead возвращает строку "ключ=значение`nключ2=значение2"
        sectionContent := IniRead(configPath, "MsgFilter")
    } catch {
        OutputDebug("AHK: Section [MsgFilter] not found or empty")
        return
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
    OutputDebug("AHK: Loaded " MsgColorMap.Count " ID->Color mappings from ChatConfig.ini")
}


try {
	ConfigPath := A_ScriptDir "\ChatConfig.ini"
	ChatHeight := IniRead(ConfigPath, "AdditionalChat", "ChatHeight")
    ChatPosY := IniRead(ConfigPath, "AdditionalChat", "ChatPosY")
}
catch {
    MsgBox("Failed to find ChatConfig", "Error", 0x10)
	ExitApp
}

; 0. Создаем окно-фон
;global СBack := Gui("-SysMenu -Caption -Border -DPIScale")
;Background := []
;Background.hwnd := ImageShow(ChatBkgrndPath,, [0, 0, 345, 498], 0x40000000 | 0x10000000,, SysChat.hwnd, False) ; Флаги: 0x40000000 (WS_CHILD) | 0x10000000 (WS_VISIBLE) | 0x08000000 (WS_DISABLED)

; 1. Создаем основное окно-контейнер
global SysChat := Gui("-SysMenu -Caption -Border -DPIScale") ; +E0x80000 = WS_EX_LAYERED
SysChat.Title := "L2_SystemChat" ; это имя прописано в .dll
SysChat.BackColor := "" DefaultBackColor

BChwnd := ImageShow(A_ScriptDir "\resources\CustomSystemChatBkgrnd.png",, [0, 0, 345, ChatHeight], 0x40000000 | 0x10000000 | 0x08000000,, SysChat.hwnd, False) ; Флаги: 0x40000000 (WS_CHILD) | 0x10000000 (WS_VISIBLE) | 0x08000000 (WS_DISABLED)

; 2. Создаем дочернее окно-маску меньшего размера для сокрытия элементов контроллов (скролл-баров)
global Mask := Gui("-Caption -Border +Parent" SysChat.Hwnd " +E0x20000")
Mask.BackColor := "ABCDEF"
WinSetTransColor("ABCDEF", Mask) ;Делаем прозрачным по цвету "0xABCDEF"

GAMECHAT_WIDTH := 345
VisibleW := GAMECHAT_WIDTH - 20 - 5 ; 20px условный скроллбар слева, 5px для выравнивания
VisibleH := ChatHeight - 5


; 3. Создаем ListView внутри маски.
; Больше маски на 20-25 пикселей, чтобы скроллбар ушел за видимый край
; Второй столбец делаем нулевого размера (скрытым)
global LV := Mask.AddListView("x0 y0 w" (VisibleW + 25) " h" (VisibleH + 20) " -Hdr -Multi -E0x200 +LV0x14000 BackgroundABCDEF c" DefaultTextColor, ["Msg", "Color"])
LV.ModifyCol(1, VisibleW + 25)
LV.ModifyCol(2, 0)
DisableFontAntialiasing(LV.Hwnd)

LV_STR_MAX := 4000 ; по достижении этого количества строк частично очищаем таблицу от старых событий
LV_STR_TO_SAVE := 2500 ; количество сохраняемых строк

global LV_ColorManager := LV_Colors(LV)



; 4. Привязка к Lineage 2
SetTitleMatchMode "RegEx"
;DetectHiddenWindows(True)
global L2Class := "ahk_class (?i)^L2UnrealWWindowsViewportWindow$"
global L2Hwnd := WinExist(L2Class)

if L2Hwnd {
    if !NoIntegr {
        DllCall("SetParent", "ptr", SysChat.Hwnd, "ptr", L2Hwnd) ; TODO: NoIntegr не менять, в текущей реализации окна метод через SetParent не работает
    }
    else {
        SysChat.Opt("+Owner" L2Hwnd)
    }
    SysChat.Show("NA x0 y" ChatPosY " w345 h" ChatHeight)
    ; Отображаем маску внутри главного GUI, смещение y-?? чтобы верхняя строка не влезала. "Огрызок" строки будет служить индикатором того, что отображается не весь чат, что выше есть еще сообщения.
    Mask.Show("x21 y1 w" (VisibleW + 2) " h" (VisibleH + 2))
}
else {
    ExitApp
}


; --- КНОПКИ УПРАВЛЕНИЯ ---

; Кнопка Свернуть/Развернуть чат.
SysChat.SetFont("s14 w700", "Marlett")
btnHide := SysChat.AddText("x2 y2 w16 h14 +Center Background", "0")
btnHide.SetFont("c" DefaultTextColor " s10 w900")
SysChat.SetFont("s10 w400", "Segoe UI")
btnHide.OnEvent("Click", (*) => MinimizeRestore())

global isHidden := false

MinimizeRestore(*) {
    global isHidden

    if (isHidden) {     ; если чат был скрыт - восстанавливаем отображение и цвета
        SysChat.SetFont("s14 w700", "Marlett")
        btnHide.Text := "0"
        SysChat.SetFont("s10 w400", "Segoe UI")
        btnHide.Opt("-Border Background" DefaultBackColor)
        btnLastStr.SetFont("c" DefaultTextColor)
        WinSetTransColor(DefaultBackColor " 255", SysChat)
        WinSetTransColor("Off", SysChat)
        Mask.Show()
        WinShow(BChwnd)
        WinRedraw(SysChat.Hwnd)
        isHidden := false
    }
    else {
        btnHide.Text := "2"
        btnHide.Opt("+Border Background000000")
        btnLastStr.SetFont("c" DefaultBackColor)
        WinSetTransColor(DefaultBackColor, SysChat)
        Mask.Hide()
        WinHide(BChwnd)
        isHidden := true
    }
}

; Кнопка прокрутки сообщений в самый низ
btnLastStr := SysChat.AddText("x3 y" ChatHeight-18 " w16 h14 +Center Background +Hidden", "▼")  ; ↴ ▼ ▲
btnLastStr.SetFont("c" DefaultTextColor " s10 w900")

btnLastStr.OnEvent("Click", (*) => ScrollToLastStr())

ScrollToLastStr() {
    global IsUserScrolling

    IsUserScrolling := false
    LV.Modify(LV.GetCount(), "Vis")
    btnLastStr.Opt("+Hidden")
}

;------------------------------------------------------------------------------------------------------

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
; Автоматическая прокрутка чата с получением нового события только в том случае, если чат в самом низу (проверяем, видна ли нижняя строчка через запрос индекса верхней видимой строки и расчет индекса нижней строки)
A_HotkeyInterval := 2000
A_MaxHotkeysPerInterval := 200 ; чтобы не выводилась ошибка, если быстро вращать колесико; default 70

global IsUserScrolling := false


#HotIf IsMouseOverChat()

    *WheelUp:: {
        global IsUserScrolling

        IsUserScrolling := true
        btnLastStr.Opt("-Hidden")
        ScrollLV(-1)
    }

    *WheelDown:: {
        global IsUserScrolling

        ScrollLV(1)
        ;Sleep(16)

        BottomIndex := LV_GetBottomIndex(LV)
        TotalRows := LV.GetCount()

        ;ToolTip("last vis string: " BottomIndex "`nTotal strings: " TotalRows, 10, 10)
        ;SetTimer(() => ToolTip(), -2000)

        if (BottomIndex >= TotalRows) {
            IsUserScrolling := false
            btnLastStr.Opt("+Hidden")
        } else {
            IsUserScrolling := true
        }
    }

#HotIf


; Функция прокрутки построчно
ScrollLV(Rows) {
    ; WM_VSCROLL = 0x0115
    ; SB_LINEUP = 0
    ; SB_LINEDOWN = 1

    if (Rows > 0) {
        loop Rows
            PostMessage(0x0115, 1, 0, LV.Hwnd)
    } else {
        loop Abs(Rows)
            PostMessage(0x0115, 0, 0, LV.Hwnd)
    }
}

; Функция получения индекса нижней видимой строки
LV_GetBottomIndex(LVControl) {
    ; LVM_GETTOPINDEX := 0x1027 индекс самой верхней видимой строки (WinAPI возвращает 0-based, для работы с таблицей AHKv2 (1-based) надо прибавить 1, но так как потом будем вычитать для расчета нижнего, то опускаем это действие
    ; LVM_GETCOUNTPERPAGE := 0x1028 количество строк, которые физически помещается в видимую область

    TopIndex := SendMessage(0x1027, 0, 0, LVControl) ; + 1
    CountPerPage := SendMessage(0x1028, 0, 0, LVControl)

    ; Нижний видимый индекс — это верхний + количество строк на страницу - 1
    return TopIndex + CountPerPage ; - 1
}


; Функция проверки положения мыши
IsMouseOverChat() {

    ;CoordMode "Mouse", "Screen"
    ;MouseGetPos &MouseX, &MouseY
    ; cross-process метод
    ;ControlHwnd := DllCall("WindowFromPoint", "int64", (MouseY << 32) | (MouseX & 0xFFFFFFFF), "Ptr")

    MouseGetPos(,, &WindowHwnd, )

    return (WindowHwnd == SysChat.Hwnd)
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

    ;OutputDebug("AHK ReceiveData: msgId=" msgId " text=" textString)

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
            LV_ColorManager.UpdateProps() ; вызываем UpdateProps() после добавления, но перед перекраской, чтобы принудительно синхронизировать с реальным состоянием ListView в памяти Windows
            LV_ColorManager.Row(CurrentRow, "", Color)
        }
        else {
            AddLongMsg(Str, Color, MAX_MSG_LENGTH)
            CurrentRow := LV.GetCount()
        }

        LineCounter++
    }

    LV.Opt("+Redraw")
    LV.Redraw()

    if (!IsUserScrolling) {
        LV.Modify(CurrentRow, "Vis")
    }
}


AddLongMsg(text, color, maxChars) {
    global LV, LV_ColorManager

    pos := 1
    linesArray := []

    ; Ищем максимально возможный кусок, такой чтобы заканчивался на границе слова или пробеле (первая группа регулярки (.{1," maxChars "})(?:\s+|$)). Если не получилось - то просто откусим maxChar символов (вторая группа(.{1," maxChars "}))
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


OnExit(ExitFunc)

ExitFunc(ExitReason, ExitCode) {
    ;global FontFile
    ;DllCall("RemoveFontResource", "Str", FontFile)
    ;DllCall("SendMessage", "Ptr", 0xFFFF, "UInt", 0x001D, "Ptr", 0, "Ptr", 0)
}