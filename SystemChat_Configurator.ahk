#Requires AutoHotkey v2.0
#Include "lib\Class_LV_Colors.ahk"
#Include "lib\ImagePut.ahk"
#Include "lib\Gdip_All.ahk"


if !DirExist("resources") {
    MsgBox("Папка resources не найдена.", "Ошибка", "IconX")
    ExitApp
}

if !DirExist("l2encdec") {
    MsgBox("Папка l2encdec не найдена.", "Ошибка", "IconX")
    ExitApp
}
/*
if !DirExist("umodel") {
    MsgBox("umodel не найдена.", "Ошибка", "IconX")
    ExitApp
}
*/

fontsMap := Map(
    "Segoe UI", "NULL",
    ;"SF Pro", "\resources\SF-Pro.ttf",
    "Nunito", "\resources\Nunito-Regular.ttf"
)

for fontName, relPath in fontsMap {
    if !(fontName = "Segoe UI") {
        fullPath := A_ScriptDir . relPath
        if !DllCall("Gdi32.dll\AddFontResourceEx", "Str", fullPath, "UInt", 0x10, "UInt", 0) {
            MsgBox("Не удалось загрузить файл шрифта: " fullPath, "Error", "IconX")
        }
    }
}

HelpText := {
        Tutorial: "
        ( LTrim
        Для работы всего функционала скрипт должен лежать в папке \Игра\Patches\

        Нажмите кнопку Load, чтобы загрузить данные системных сообщений игры.

        Выберите нужные строки (чтобы выбрать сразу несколько, удерживайте Ctrl или Shift) и выберите желаемый цвет раскраски сообщения.

        Если нужно исключить сообщение из отображаемых - выберите нужную строку, нажмите ячейку del (когда напротив сообщения не указан цвет, такое сообщение не будет отображаться вообще).

        Вы можете настроить свою собственную палитру цветов, используя ячейки из второго ряда.

        Задайте размер окна дополнительного чата в  %  от основного игрового.

        Чтобы сохранить конфиг, нажмите Save (настроенные цвета также сохраняются).

        )",
        EN: "
        ( LTrim
        For full functionality the script must be placed into folder \Lineage2\Patches\

        Click the "Load" button to load text of game’s system messages.

        To select several lines at once hold Ctrl or Shift. Choose the lines and select reuired color.

        If you need to exclude a message from being displayed, select the required line and press "del".
        If no color is specified for a message, that message will not be displayed at all.

        You can customize your own color palette using the cells from the second row.

        Set window size in  %  from main-game chat.

        To save the config, click "Save". The customized colors are also saved.

        )"
}

global DebugMode := false
global NoIntegr := true

global isListLoaded := false
global isChanged := false
global OnceChanged := false


configPath := A_ScriptDir "\ChatConfig.ini"

DefaultTextColor := "0xB09979"
DefaultBackColor := "0x1D1D1D"

CustomSystemChatBkgrnd := A_ScriptDir "\resources\CustomSystemChatBkgrnd.png"

mColors := [
    {ID: 1, Name: "Red",      Hex: "0xF84210"},
    {ID: 2, Name: "Green",    Hex: "0x3AC27F"},
    {ID: 3, Name: "SkyBlue",  Hex: "0x19FFFF"},
    {ID: 4, Name: "Gold",     Hex: "0xF4CB21"},
    {ID: 5, Name: "Purple",   Hex: "0xCC00FF"},
    {ID: 6, Name: "Indigo",   Hex: "0x4A4AEE"},
    {ID: 7, Name: "White",    Hex: "0xEAEAEA"},
    {ID: 8, Name: "Tan",      Hex: DefaultTextColor}
]

MyGui2 := Gui()
MyGui2.Title := "System Chat Configurator"
MyGui2.SetFont("s10", "Segoe UI")

hIcon := LoadPicture("shell32.dll", "Icon329", &imgType)
SendMessage(0x0080, 0, hIcon, MyGui2.Hwnd) ; WM_SETICON (0=маленькая для заголовка)
SendMessage(0x0080, 1, hIcon, MyGui2.Hwnd) ; WM_SETICON (1=большая для Alt+Tab)
TraySetIcon("shell32.dll","329")


;MyGui2.OnEvent("Close", (*) => ExitApp())
MyGui2.OnEvent("Close", ConfirmAndExit)

; Кнопка Загрузить
btnLoad := MyGui2.Add("Button", "x10 y15 w80 h29", "Load")
btnLoad.OnEvent("Click", (*) => ReloadSystemMsgE())



;MyGui2.Add("GroupBox", "x+15 yp-12 w175 h65", "")

; Блок Шрифты
ddlFontOpts := []
for fontName in fontsMap {
    ddlFontOpts.Push(fontName)
}

btnLoad.GetPos(&bX, &bY)
ddlFont := MyGui2.Add("DropDownList", "x" bX+100 " yp+2 w100", ddlFontOpts)
ddlFont.Text := "Segoe UI"

ddlFontSize := MyGui2.Add("DropDownList", "x+3 yp w50", ["10", "11", "12", "13", "14"])
ddlFontSize.Text := 10


; Блок Окно
MyGui2.Add("Text", "x+15 yp+4", "Chat Size:")
ddlWSize := MyGui2.Add("DropDownList", "x+3 yp-4 w60", ["30%"])
ddlWSize.Text := "30%"


ddlWSize.Opt("+Disabled")
ddlFont.Opt("+Disabled")
ddlFontSize.Opt("+Disabled")


; Инструкция и Опции
btnLoad.GetPos(&bX, &bY)
MyGui2.SetFont("s10 underline", "Segoe UI")
Tut2 := MyGui2.Add("Text", "cBlue x750 y" bY+5 " w50", "Tutorial")
Tut2.OnEvent("Click", (*) => MsgBox(HelpText.Tutorial, "Help"))
MyGui2.Add("Text", "cBlue x+1", "(EN)").OnEvent("Click", (*) => MsgBox(HelpText.EN, "Help"))
Opts := MyGui2.Add("Text", "x+20 yp cBlue", "Options")
Opts.OnEvent("Click", (*) => ShowOptions(MyGui2))
MyGui2.SetFont("norm s10", "Segoe UI")


; Кнопка Сохранить
btnLoad.GetPos(&bX, &bY)
btnSave := MyGui2.Add("Button", "x+30 y" bY " h29", "Save config")
btnSave.Opt("+Disabled")
btnSave.OnEvent("Click", (*) => SaveConfig())


; "Клавиши" с предопределенными цветами
btnLoad.GetPos(&bX, &bY)
MainBtn := [] ; будем использовать контрол типа "Text", вместо "Button", удобнее для работы с цветом фона, но именовать будем все равно Btn
    MainBtn.Push(MyGui2.Add("Text", "x" bX+410 " y20 w30 h20 Border Background" mColors[1].Hex))
    for obj in mColors {
        if (obj.ID > 1) {
            MainBtn.Push(MyGui2.Add("Text", "x+5 w30 h20 Border Background" obj.Hex))
        }
        MainBtn[obj.ID].fCol := obj.Hex     ;будем именовать "Fixed Color (fCol)", так как цвет зашит в код
    }


; Дополнительные настраиваемые пользователем "клавиши"
CustomBtn := []
    for obj in mColors {
        if (obj.ID = 1) {
            MainBtn[1].GetPos(&bX, &bY)
            CustomBtn.Push(MyGui2.Add("Text", "x" bX " yp+25 w30 h20 Border BackgroundFFFFFF"))
        }
        else {
            CustomBtn.Push(MyGui2.Add("Text", "x+5 w30 h20 Border BackgroundFFFFFF"))
        }
        CustomBtn[obj.ID].cCol := 0     ;будем именовать "Custom Color (cCol)", так как цвет пользователь может настраивать;
        CustomBtn[obj.ID].id := obj.ID
    }

; Крестики для сброса цвета кастомных клавиш
MyGui2.SetFont("s7 w700", "Marlett") ; спец. системный шрифт Windows; r - закрыть окно, 0 - свернуть, 1 - развернуть, 2- восстановить окно, 3 - вверх, 6 - вниз
CustomBtnX := []
    for obj in mColors {
        if (obj.ID = 1) {
            CustomBtn[1].GetPos(&bX, &bY)
            CustomBtnX.Push(MyGui2.Add("Text", "x" (bX+20) " y" bY " w10 h10 Center 0x200 BackgroundFFFFFF", "r")) ; 0x200 SS_CENTERIMAGE
        }
        else {
            CustomBtnX.Push(MyGui2.Add("Text", "x+25 w10 h10 0x200 BackgroundFFFFFF", "r"))
        }
        CustomBtnX[obj.ID].id := obj.ID
        CustomBtnX[obj.ID].Opt("+Hidden")
    }
MyGui2.SetFont("s10 w400", "Segoe UI")


; Кнопка Очистить Цвет
MainBtn[1].GetPos(&bX, &bY)
XBtn    := MyGui2.Add("Text", "x+5 w35 h20 Center Border Background", "del")
;XBtn.SetFont("cB09979 s12 Bold")


; Вызов функций "клавиш" и сброса цветов
for obj in mColors {
    MainBtn[obj.ID].OnEvent("Click", SetColor.Bind(MainBtn[obj.ID].fCol)) ; метод .Bind() "замораживает" значение для каждой кнопки, при этом он будет передан самым первым параметром
    CustomBtn[obj.ID].OnEvent("Click", SetColor.Bind(CustomBtn[obj.ID].cCol))
}

XBtn.OnEvent("Click",  (*) => ClearColor())


; Создание таблицы сообщений
lv := MyGui2.AddListView("x10 yp+30 w1000 h675 NoSortHdr -E0x200 +LV0x14000 Background" DefaultBackColor " c" DefaultTextColor, ["RGB", "ID", "Msg"])
lv.ModifyCol(1, "105 Integer")
lv.ModifyCol(2, "50 Integer")

CLV := LV_Colors(lv)
;DisableFontAntialiasing(lv.Hwnd)



MyGui2.Show()

global ColorsConfMap := Map()


;------------------------------------------------------------------------------------------------------------------------------------------------------------
; Управление шрифтами
ddlFont.OnEvent("Change", SetFonts)
ddlFontSize.OnEvent("Change", SetFonts)

SetFonts(*) {
    font := ddlFont.Text
    fontSize := ddlFontSize.Text
    fontWidth := 400

    ; Пересчитываем размер из пунктов (pt) в пиксели устройства для корректного отображения
    hDC := DllCall("GetDC", "Ptr", lv.Hwnd, "Ptr")
    logPixelsY := DllCall("GetDeviceCaps", "Ptr", hDC, "Int", 90, "Int") ; 90 = LOGPIXELSY
    DllCall("ReleaseDC", "Ptr", lv.Hwnd, "Ptr", hDC)
    fontHeight := -DllCall("MulDiv", "Int", fontSize, "Int", logPixelsY, "Int", 72, "Int")

    ; Создаем структуру шрифта Windows (GDI Object)
    hFont := DllCall("CreateFont",
        "Int", fontHeight, "Int", 0, "Int", 0, "Int", 0,
        "Int", fontWidth ,
        "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 0,
        "Str", font, "Ptr")

    if (!hFont)
        return

    SendMessage(0x0030, hFont, 1, lv.Hwnd) ; WM_SETFONT
    SendMessage(0x001D, 0, 0, lv.Hwnd) ; WM_SETREDRAW = false
    SendMessage(0x1093, 0, 0, lv.Hwnd) ; LVM_SETSELECTEDCOLUMN (пустое сообщение, чтобы сообщить об изменении шрифта и тригернуть пересчет высоты и отступов строк)
    SendMessage(0x001D, 1, 0, lv.Hwnd) ; WM_SETREDRAW = true
    DllCall("RedrawWindow", "Ptr", lv.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 1) ; RDW_INVALIDATE
}

;------------------------------------------------------------------------------------------------------------------------------------------------------------


ShowOptions(ParentGui) {

    optGui := Gui("+Owner" ParentGui.Hwnd " +ToolWindow -SysMenu", "Adv. Settings:")
    ParentGui.Opt("+Disabled")


    optDM := optGui.Add("Checkbox", "x20 y20 h20", "Debug Mode")
    optDM.Value := DebugMode

    ;optGIF := optGui.Add("Checkbox", "x20 yp+24 h20", "Low Quality GIF")
    ;optGIF.Value := GIF

    optNoIntegr := optGui.Add("Checkbox", "x20 yp+24 h20 +Disabled", "Disable integration to L2")
    optNoIntegr.Value := NoIntegr

    btnOk := optGui.Add("Button", "Default w60", "OK")

    ParentGui.GetPos(&px, &py, &pw, &ph)

    CloseModal(*) {
        global DebugMode := optDM.Value
        ;global GIF := optGIF.Value
        global NoIntegr := optNoIntegr.Value
        (DebugMode) ? Opts.Opt("cMaroon") : Opts.Opt("cBlue")
        ParentGui.Opt("-Disabled")
        optGui.Destroy()
    }

    btnOk.OnEvent("Click", CloseModal)
    optGui.OnEvent("Close", CloseModal)

    optGui.Show("Hide")
    ParentGui.GetPos(&px, &py, &pw, &ph)
    cx := px + 850
    cy := py + 75
    optGui.Show("x" cx " y" cy)
}

;------------------------------------------------------------------------------------------------------------------------------------------------------------
; Считывание параметров игрового чата и размеров окна
try {
	RelativePath := A_ScriptDir "\..\..\System\Option.ini"
	L2VideoConfigPath := ""
	Loop Files, RelativePath
	L2VideoConfigPath := A_LoopFileFullPath

	VResolX := IniRead(L2VideoConfigPath, "Video", "GamePlayViewportX")
	VResolY := IniRead(L2VideoConfigPath, "Video", "GamePlayViewportY")


	RelativePath := A_ScriptDir "\..\..\System\WindowsInfo.ini"
	L2ConfigPath := ""
	Loop Files, RelativePath
    L2ConfigPath := A_LoopFileFullPath

    GameChatHeight := IniRead(L2ConfigPath, "22", "Height")

}
catch {
    MsgBox("Failed to find or read Lineage 2 WindowsInfo.ini config file.`n`nCheck that scrip is placed into folder:`nGame_Folder/Patches/SystemChat/", "Error", "IconX Owner" MyGui2.Hwnd)
	ExitApp
}

; Проверяем сколько пространства остается для системного чата. Заполняем выпадающий список допустимыми значениями
if (VResolY > 2 * GameChatHeight + 5) {
    maxPercent := 100
}
else {
    maxPercent := ((VResolY - (GameChatHeight + 5)) / GameChatHeight) * 100
    if (maxPercent < 30) {
        MsgBox("Слишком мало места для системного чата.`nЗапустите игру и уменьшите размер основного чата.`nРазмер системного чата временно ограничен 30% основного", "Недостаточно места", "IconX Owner" MyGui2.Hwnd)
        maxPercent := 30
    }
}

allPercents := [30, 40, 50, 60, 70, 80, 90, 100]
allowedPercents := []

; Фильтруем массив: оставляем только то, что проходит по лимиту
for percent in allPercents {
    if (percent <= maxPercent)
        allowedPercents.Push(percent "%")
}

; Заполняем список
ddlWSize.Delete()
ddlWSize.Add(allowedPercents)
if (allowedPercents.Length > 4) {
    ddlWSize.Choose(5) ; если возможно выбираем 70% (5ый по счету элемент), иначе - максимальный.
}
else {
    ddlWSize.Choose(allowedPercents.Length)
}
ddlWSize.oldText := ddlWSize.Text

ddlWSize.OnEvent("Change",(ctrl, *) => (ctrl.Text != ctrl.oldText) ? (ctrl.oldText := ctrl.Text, EnableSaveConfig()) : "") ; если значение размера реально поменяли



;------------------------------------------------------------------------------------------------------------------------------------------------------------
; Подгрузка данных из systemmsg-e.txt по кнопке LOAD

ReloadSystemMsgE() {
    global configPath, isChanged, OnceChanged

    if (btnLoad.Text = "Reload") && (isChanged = true) {
        result := MsgBox("Are you sure to reload?", "ChatConfig.ini", "0x24 Owner" MyGui2.Hwnd) ; 0x20 Icon?, 0x4 Y/N
        if (result = "No") {
            return
        }
    }

    if (!DecodeMsgFile() || !ReadDecodedFile()) {
        return
    }

    if !FileExist(configPath) {
        return
    }

    if (btnLoad.Text = "Load") {
        btnLoad.Text := "Reload"
        ddlWSize.Opt("-Disabled")
        ddlFont.Opt("-Disabled")
        ddlFontSize.Opt("-Disabled")
    }

    for obj in mColors {
        CustomBtn[obj.ID].cCol := 0
        CustomBtn[obj.ID].Opt("Background0xFFFFFF")
        CustomBtnX[obj.ID].Opt("+Hidden")
        CustomBtn[obj.ID].Redraw()
    }

    result := MsgBox("Previously saved Config file found.`nDo you want to apply color-schema?", "ChatConfig.ini", "0x24 Owner" MyGui2.Hwnd) ; 0x20 Icon?, 0x4 Y/N
    if (result = "Yes") {
        LoadColorConfig(configPath)
        ApplyColorConfig()
    }

    isChanged := false
    OnceChanged := false
    btnSave.Opt("+Disabled")

}


; Функция раскодирования с использованием l2encdec утилиты
DecodeMsgFile() {
    relSystemMsgEFilePath := A_ScriptDir "\..\..\System\SystemMsg-e.txt"
    SystemMsgEFilePath := ""
    Loop Files, relSystemMsgEFilePath
    SystemMsgEFilePath := A_LoopFileFullPath

    ; Поиск в \L2\system
    if !FileExist(SystemMsgEFilePath) {
        MsgBox("SystemMsg-e.txt не найден.", "Ошибка", "IconX Owner" MyGui2.Hwnd)
        return false
    }

    ; Копирование в \l2encdec
    try {
        FileCopy(SystemMsgEFilePath, ".\l2encdec\", 1)
    } catch {
        MsgBox("Ошибка копирования SystemMsgE в \l2encdec\ папку", "Ошибка", "IconX Owner" MyGui2.Hwnd)
        return false
    }

    ; Декодирование
    oldWorkingDir := A_WorkingDir
    SetWorkingDir(A_ScriptDir "\l2encdec")
    decFilePath := A_ScriptDir "\l2encdec\dec_SystemMsg-e.txt"

    try {
        if FileExist(decFilePath) {
            FileDelete(decFilePath)
        }
    }
    catch OSError as err {
            MsgBox("Файл " decFilePath " открыт или заблокирован.`n`nДетали: " err.Message, "Ошибка", "IconX Owner" MyGui2.Hwnd)
            return false
    }

    exePath := "l2encdec.exe"
    args := " -d SystemMsg-e.txt dec_SystemMsg-e.txt"
    RunWait(exePath args, , "Hide")

    SetWorkingDir(oldWorkingDir)

    if !FileExist(decFilePath) {
        MsgBox("Ошибка декодирования", "Ошибка", "IconX Owner" MyGui2.Hwnd)
        return false
    }

    return true
}

; Функция чтения раскодированных сообщений и заполнения таблицы
ReadDecodedFile() {
    global lv, CLV, isListLoaded

    CLV.Clear()
    lv.Delete()

    filePath := A_ScriptDir "\l2encdec\dec_SystemMsg-e.txt"

    Loop read, filePath, "UTF-8" {
        if RegExMatch(A_LoopReadLine, "id=(\d+).*?msg=\[(.*?)\]", &m) {
            lv.Add("", "", m[1], m[2])
        }
    }

    if (lv.GetCount() = 0) {
        MsgBox("Не удалось разобрать содержимое раскодированного файла l2encdec\dec_SystemMsg-e.txt", "Ошибка", "IconX Owner" MyGui2.Hwnd)
        return false
    }

    isListLoaded := true
    return true
}


; Функция загрузки сохраненных параметров из конфиг файла
LoadColorConfig(filepath) {
    global ColorsConfMap

    ; Размер окна
    try {
        chSize := IniRead(filepath, "AdditionalChat", "ChatSize")

        if (Number(StrReplace(chSize, "%")) <= Number(StrReplace(allowedPercents[allowedPercents.Length], "%"))) {
            ddlWSize.Text := chSize
            ddlWSize.oldText := ddlWSize.Text
        }
    } catch Error {
        OutputDebug("Failed to load chatconfig.ini or section [AdditionalChat] is missing`n")
    }

    ; Цвета кастомным "клавиш"
    try {
        sectionContent := IniRead(filepath, "CustomColors") ; без третьего параметра IniRead возвращает строку "ключ=значение`nключ2=значение2"

        Loop Parse, sectionContent, "`n", "`r" {
            if RegExMatch(A_LoopField, "^\s*(\d+)\s*=\s*(0x[0-9A-Fa-f]{6})", &Match) {
                colorHex := Format("0x{:06X}", Integer(Match[2])) ; 0x - дописываем префикс, : - разделитель индекса аргумента (здесь он опущен, так как аргумент один) и формализатора, X - шестнадцатеричная с заглавными, 6 - минимальная ширина строки, 0 - если меньше, заполняем нулями слева
                CustomBtn[Number(Match[1])].cCol := colorHex
                CustomBtn[Number(Match[1])].Opt("Background" colorHex)
                CustomBtnX[Number(Match[1])].Opt("Background" colorHex " -Hidden")
                CustomBtn[Number(Match[1])].Redraw()
            }
        }
    } catch Error {
        OutputDebug("Failed to load chatconfig.ini or section [CustomColors] is missing`n")
    }

    ; Цвета событий
    try {
        sectionContent := IniRead(filepath, "MsgFilter")

        Loop Parse, sectionContent, "`n", "`r" {
            if RegExMatch(A_LoopField, "^\s*(\d+)\s*=\s*(0x[0-9A-Fa-f]{6})", &Match) { ; Match[1] = строка ID, Match[2] = строка Цвета
                colorHex := Format("0x{:06X}", Integer(Match[2]))
                ColorsConfMap[Number(Match[1])] := colorHex
            }
        }
    } catch Error {
        OutputDebug("Failed to load config.ini or section [MsgFilter] is missing`n")
    }
}


; Функция покраски строк таблицы цветами, указанными в конфиг-файле
ApplyColorConfig(*) {
    global ColorsConfMap, lv, CLV

    ; для ускорения поиска создаем временный словарь с номерами строк таблицы сообщений, ключами к которым будут ID
    ; а перебор ID-шек осуществляем по словарю конфига, так как в нем обычно значительно меньше строк, чем в таблице сообщений
    idMap := Map()
    Loop lv.GetCount() {
        idMap[Number(lv.GetText(A_Index , 2))] := A_Index
    }

    lv.Opt("-Redraw")

    for curID, hCol in ColorsConfMap {
        if (!idMap.Has(curID))
            continue

        lv.Modify(idMap[curID], "Col1", hCol) ; 3ий параметр здесь - это значение переменной, которое запишем в 1ый стобец.
        CLV.UpdateProps()
        CLV.Row(idMap[curID], "", ColorsConfMap[curID]) ;здесь 3ий параметр - цвет, в который покрасим шрифт
    }

    lv.Opt("+Redraw")
}


;------------------------------------------------------------------------------------------------------------------------------------------------------------
; Интерактивная раскраска строк

; Логика кастомных клавиш:
; если нажали крестик - то сбрасываем цвет
; если выбраны строки - то (вызываем палитру, чтобы определить цвет, если уже задан - не вызываем) красим строки.
; если не выбраны - просто вызываем палитру и сохраняем цвет
; Кастомные клавиши определяем по наличию свойства .cCol
SetColor(color, GuiCtrl, Info) {
    global lv, CLV, isChanged, OnceChanged

    if (GuiCtrl.HasProp("cCol")) {
        MouseGetPos(,,&winHwnd, &ctrlHwnd, 2)
        if (ctrlHwnd = CustomBtnX[GuiCtrl.id].Hwnd) {      ; если клик по крестику
                CustomBtn[GuiCtrl.id].cCol := 0
                CustomBtn[GuiCtrl.id].Opt("BackgroundFFFFFF")
                CustomBtnX[GuiCtrl.id].Opt("BackgroundFFFFFF +Hidden")
                CustomBtn[GuiCtrl.id].Redraw()
                EnableSaveConfig()
                return
        }
    }

    SelectedRows := []
    RowNumber := 0
    while (RowNumber := lv.GetNext(RowNumber)) {
        SelectedRows.Push(RowNumber)
    }

    if (SelectedRows.Length > 0) {
        if (GuiCtrl.HasProp("cCol")) {
            if (GuiCtrl.cCol = 0) {
                ConfigureBtnBackgroundColor(GuiCtrl)    ; предлагаем настроить цвет
                if (GuiCtrl.cCol = 0) { ; если цвет не стали настраивать
                    return
                }
                else {
                    CustomBtnX[GuiCtrl.id].Opt("Background" GuiCtrl.cCol " -Hidden")
                }
            }
            color := GuiCtrl.cCol
        }

        lv.Opt("-Redraw")

        for idx, row in SelectedRows {
            CLV.UpdateProps()
            CLV.Row(row, DefaultBackColor, color)
            lv.Modify(row, "Col1 -Select -Focus", color) ; выделение строки имеет более высокий приоритет, поэтому снимаем выделение, чтобы отобразить перерисовки цвета
        }

        lv.Opt("+Redraw")
    }
    else {
        if (GuiCtrl.HasProp("cCol")) {
            CurCol := GuiCtrl.cCol
            ConfigureBtnBackgroundColor(GuiCtrl)
                if (GuiCtrl.cCol = CurCol) {    ; если цвет ячейки не стали менять
                    return
                }
                else {
                    CustomBtnX[GuiCtrl.id].Opt("Background" GuiCtrl.cCol " -Hidden")  ; если поменяли - отображаем крестик
                }
        } else {
            return
        }
    }

    EnableSaveConfig() ; считаем, что если цвет кастомной клавиши поменяли, то это уже повод, чтобы предложить сохранить конфиг.
}


; Удалить цвет
ClearColor() {
    global lv, CLV, isChanged, OnceChanged

    SelectedRows := []
    RowNumber := 0


    while (RowNumber := lv.GetNext(RowNumber)) {
        SelectedRows.Push(RowNumber)
    }
    if (SelectedRows.Length = 0) {
        return
    }

    lv.Opt("-Redraw")

    for idx, row in SelectedRows {
        CLV.UpdateProps()
        CLV.Row(row, DefaultBackColor, DefaultTextColor)
        lv.Modify(row, "Col1 -Select -Focus", "")
    }

    lv.Opt("+Redraw")

    EnableSaveConfig()
}

; Показать пользователю Палитру и присвоить кастомной клавише цвет, который он выберет
ConfigureBtnBackgroundColor(GuiCtrl) {

    defcolor := (GuiCtrl.cCol == 0) ? MainBtn[GuiCtrl.id].fCol : GuiCtrl.cCol ; если цвет еще не задан, то выберем такой же цвет, что в основной ячейке выше
    ChosenColor := WindowsColorPicker(defcolor, MyGui2.hwnd)

    if !(ChosenColor = "") {
        GuiCtrl.cCol := "0x" ChosenColor
        GuiCtrl.Opt("Background" ChosenColor)
        GuiCtrl.Redraw()
    }
}
;------------------------------------------------------------------------------------------------------------------------------------------------------------

EnableSaveConfig(*) {
global OnceChanged, isChanged

    if (OnceChanged = false) {  ; чтобы каждый раз при покраске не вызывать EnableSaveConfig() будем проверять только этот флаг.
        OnceChanged := true
        isChanged := true
        if (isListLoaded = true) {
            btnSave.Opt("-Disabled")
        }
    }
}

SaveConfig(*) {
    global configPath, OnceChanged, isChanged

    filepath := A_ScriptDir "\ChatConfig.ini"

    bothChatsHeight := 5 + GameChatHeight + Round(GameChatHeight * (Float(StrReplace(ddlWsize.Text, "%")) / 100))
    if (VResolY - bothChatsHeight > 0) {
        ChatPosY := VResolY - bothChatsHeight
        ChatHeight := Round(GameChatHeight * (Float(StrReplace(ddlWsize.Text, "%")) / 100))
    }
    else {
        ChatPosY := 2
        ChatHeight := Round(GameChatHeight * (Float(StrReplace(ddlWsize.Text, "%")) / 100))
    }

    strChatSizeAndPos := "ChatSize=" ddlWSize.Text "`nChatPosY=" ChatPosY "`nChatHeight=" ChatHeight "`nFont=" ddlFont.Text "`nFontSize=" ddlFontSize.Text "`nFontPath=" fontsMap[ddlFont.Text]

    strCellsColors := ""
    for obj in mColors {
        if !(CustomBtn[obj.ID].cCol = 0) {
            strCellsColors .= obj.ID "=" CustomBtn[obj.ID].cCol "`n"
        }
    }

    strCount := 0
    strID := "; Message_ID (decimal) = Color (hex)`n; If no ID in this list — message would not be displayed in game`n"
    Loop lv.GetCount() {
        hCol := lv.GetText(A_Index, 1)
        if (hCol != "") {
            strID .= lv.GetText(A_Index, 2) "=" hCol "`n"
            strCount++
        }
    }

    if (strCount = 0) {
        MsgBox("No message colors are configured", "Error", "IconX Owner" MyGui2.Hwnd)
        return false
    }

    try {
        IniWrite(strChatSizeAndPos, filepath, "AdditionalChat")
        FileAppend("`n", filepath)
        IniWrite(strCellsColors, filepath, "CustomColors")
        FileAppend("`n", filepath)
        IniWrite(strID, filepath, "MsgFilter")
    }
    catch OSError as err {
        MsgBox("Failed to save .ini file!`n`n" err.Message, "Error", "IconX Owner" MyGui2.Hwnd)
        return false
    }

    if (!ExportTextures() || !DrawChatBackPNG(CustomSystemChatBkgrnd, ChatHeight, mTextureNames[2].Path, mTextureNames[3].Path, mTextureNames[4].Path)) {
        MsgBox("Ошибка сохранения файла фона.`nБудет использован стандартный фон", "Ошибка", "IconX Owner" MyGui2.Hwnd)
        gdipCreatePng(CustomSystemChatBkgrnd, 345, ChatHeight, DefaultBackColor, 90)
    }

    gdipCreatePng(CustomSystemChatBkgrnd, 345, ChatHeight, DefaultBackColor, 90) ; Пока не реализована работа с полупрозрачными таблицей и фоном в оверлее принудительно используем простую графику

    isChanged := false
    OnceChanged := false
    btnSave.Opt("+Disabled")
}


;------------------------------------------------------------------------------------------------------------------------------------------------------------
; Сейчас не используется. Для возможности рисовать крестик белого цвета, если цвет клавиши выбран темным.
GetContrastColor(color) {
    r := (color >> 16) & 0xFF
    g := (color >> 8) & 0xFF
    b := color & 0xFF

    ; Формула яркости YIQ для цветовой температуры в 6500К
    Y := (r * 299 + g * 587 + b * 114) / 1000

    ; Если яркость меньше половины (128), значит, фоновый цвет темный -> вернем белый
    return (Y < 128) ? "0xFFFFFF" : "0x000000"
}

;------------------------------------------------------------------------------------------------------------------------------------------------------------

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

;------------------------------------------------------------------------------------------------------------------------------------------------------------

; Вызов стандартной виндовой палитры
WindowsColorPicker(defaultColor := 0xFFFFFF, hwndParent := 0) {

    ; Выделяем память под структуру CHOOSECOLOR (36 байт на 32-бит / 72 байт на 64-бит)
    ccSize := A_PtrSize == 8 ? 72 : 36
    cc := Buffer(ccSize, 0)

    ; Выделяем память под 16 пользовательских (кастомных) цветов (16 * 4 байта = 64 байта)
    static customColors := Buffer(64, 0)

    ; Преобразуем входящий RGB в формат WinAPI BGR
    bgr := ((defaultColor & 0xFF) << 16) | (defaultColor & 0xFF00) | ((defaultColor >> 16) & 0xFF)

    ; Заполняем структуру CHOOSECOLOR
    NumPut("UInt", ccSize, cc, 0)             ; lStructSize
    NumPut("UPtr", hwndParent, cc, A_PtrSize) ; hwndOwner
    NumPut("UInt", bgr, cc, A_PtrSize * 3)    ; rgbResult
    NumPut("UPtr", customColors.Ptr, cc, A_PtrSize * 4) ; lpCustColors
    NumPut("UInt", 0x103, cc, A_PtrSize * 5)  ; Flags: CC_ANYCOLOR (0x100) | CC_RGBINIT (0x1) | CC_FULLOPEN (0x2)

    if !DllCall("comdlg32\ChooseColor", "UPtr", cc.Ptr, "UInt")
        return "" ; Пользователь закрыл окно или нажал "Отмена"

    resBGR := NumGet(cc, A_PtrSize * 3, "UInt")

    ; Конвертируем обратно из BGR в читаемый HEX формат RGB (RRGGBB)
    resRGB := ((resBGR & 0xFF) << 16) | (resBGR & 0xFF00) | ((resBGR >> 16) & 0xFF)

    return Format("{:06X}", resRGB)
}

;------------------------------------------------------------------------------------------------------------------------------------------------------------

mTextureNames := [
    {ID: 1,     Name: "ChatTab1",   Path: ""},
    {ID: 2,     Name: "Head",       Path: ""},
    {ID: 3,     Name: "Body",       Path: ""},
    {ID: 4,     Name: "Bottom",     Path: ""}
]


; Распаковка текстур с помощью umodel
ExportTextures() {
    wasErrors := false

    relL2UIPath      := A_ScriptDir "\..\..\SysTextures\L2UI.utx"
    L2UIutxPath := ""
    Loop Files, relL2UIPath
    L2UIutxPath := A_LoopFileFullPath

    ; Копирование L2UI.utx в \umodel
    try {
        FileCopy(L2UIutxPath, ".\umodel\", 1)
    } catch {
        OutputDebug("Ошибка копирования L2UI.utx в \umodel\ папку.")
        return false
    }

    oldWorkingDir := A_WorkingDir
    SetWorkingDir(A_ScriptDir "\umodel")

    for idx, obj in mTextureNames {
        obj.Path := A_ScriptDir "\umodel\Extracted\L2UI\Texture\" obj.Name ".png"
        try {
            if FileExist(obj.Path) {
                FileDelete(obj.Path)
            }
        }
        catch OSError as err {
            OutputDebug("Файл " obj.Path " открыт или заблокирован.`nДетали: " err.Message)
            wasErrors := true
        }

        if !wasErrors {
            args := ' -game=l2 -export -png -out=Extracted -obj=' obj.Name ' L2UI'
            RunWait("umodel.exe" args, , "Hide")

            if !FileExist(obj.Path) {
                OutputDebug("Ошибка распаковки текстуры " obj.Name)
                wasErrors := true
            }
        }
    }

    FileDelete(A_ScriptDir "\umodel\L2UI.utx")
    SetWorkingDir(oldWorkingDir)

    return !wasErrors
}

; Создание PNG файла фона
DrawChatBackPNG(targetPath, targetHeight, HeadPath, BodyPath, BottomPath) {
    wasError := false

    pToken := Gdip_Startup()
    if (!pToken) {
        OutputDebug("Не удалось запустить GDI+")
        return
    }

    pBitmapSrcHead := Gdip_CreateBitmapFromFile(HeadPath)
    if (!pBitmapSrcHead) {
        OutputDebug("Не удалось загрузить файл:`n" HeadPath)
        Gdip_Shutdown(pToken)
        return
    }

    pBitmapSrcBody := Gdip_CreateBitmapFromFile(BodyPath)
    if (!pBitmapSrcHead) {
        OutputDebug("Не удалось загрузить файл:`n" BodyPath)
        Gdip_Shutdown(pToken)
        return
    }

    pBitmapSrcBottom := Gdip_CreateBitmapFromFile(BottomPath)
    if (!pBitmapSrcHead) {
        OutputDebug("Не удалось загрузить файл:`n" BottomPath)
        Gdip_Shutdown(pToken)
        return
    }

    pBitmapDst := Gdip_CreateBitmap(345, targetHeight)
    pGraphics := Gdip_GraphicsFromImage(pBitmapDst)

    ; Контур (рисуем полый прямоугольник)
    pPen := Gdip_CreatePen(0xFF000000, 2)
    Gdip_DrawRectangle(pGraphics, pPen, 1, 1, 343, targetHeight - 2) ; так как толщина кисти 2px, то делаем отступ 1px от левого верхнего и правого нижнего угла

    Gdip_DeletePen(pPen)


    ; Копируем шапку окна из файла текстуры игры
    Gdip_DrawImage(pGraphics, pBitmapSrcHead, 0, 0, 25, 10, 0, 0, 25, 10) ; 23px ширина плашки со скролл-баром в игре + 2px тень; 10px высота оригинальной текстуры игры

    ; Клонируем тело окна (вертикально построчно, ориентируясь на цвет пикселя оригинальной текстуры игры)
    Loop 25 {
        x := A_Index - 1

        pixelColor := Gdip_GetPixel(pBitmapSrcBody, x, 0)
        PixelColor := (pixelColor & 0x00FFFFFF) | (90 << 24) ; выставляем значение alpha канала = 90

        pBrush := Gdip_BrushCreateSolid(PixelColor)
        Gdip_FillRectangle(pGraphics, pBrush, x, 10, 1, targetHeight - (10 + 1)) ; рисуем вертикальную линию (прямоугольник) шириной 1px от шапки до границы (высоты) холста
        Gdip_DeleteBrush(pBrush)
    }

    ; Сохраняем результат
    saveResult := Gdip_SaveBitmapToFile(pBitmapDst, targetPath)
    if (saveResult != 0) {
        OutputDebug("Ошибка сохранения файла фона. `nКод ошибки: " saveResult)
        wasError := true
    }

    ; Очистка
    Gdip_DeleteGraphics(pGraphics)
    Gdip_DisposeImage(pBitmapDst)
    Gdip_DisposeImage(pBitmapSrcHead)
    Gdip_DisposeImage(pBitmapSrcBody)
    Gdip_DisposeImage(pBitmapSrcBottom)
    Gdip_Shutdown(pToken)

    return !wasError
}


; Создание простого PNG файла для фона, если не смогли нарисовать на основе текстур
gdipCreatePng(filename, width, height, rgbColor, alpha := 255) {
    ; Загружаем GDI+
    hGdiplus := DllCall("Kernel32.dll\LoadLibrary", "Str", "gdiplus.dll", "Ptr")
    si := Buffer(A_PtrSize == 8 ? 24 : 16, 0), NumPut("UInt", 1, si, 0)
    DllCall("gdiplus.dll\GdiplusStartup", "Ptr*", &pToken := 0, "Ptr", si, "Ptr", 0)

    ; Создаем пустой холст с поддержкой альфа-канала (PixelFormat32bppARGB = 0x26200A)
    DllCall("gdiplus.dll\GdipCreateBitmapFromScan0", "Int", width, "Int", height, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &pBitmap := 0)
    DllCall("gdiplus.dll\GdipGetImageGraphicsContext", "Ptr", pBitmap, "Ptr*", &pGraphics := 0)

    ; Формируем ARGB цвет: сдвигаем альфа-байт влево и подмешиваем RGB цвет
    argb := ((alpha & 0xFF) << 24) | (rgbColor & 0xFFFFFF)

    ; Создаем кисть и закрашиваем область скролл-бара
    DllCall("gdiplus.dll\GdipCreateSolidFill", "UInt", argb, "Ptr*", &pBrush := 0)
    DllCall("gdiplus.dll\GdipFillRectangle", "Ptr", pGraphics, "Ptr", pBrush, "Float", 0, "Float", 0, "Float", 23, "Float", height)

    ; Создаем перо толщиной 2.0 и рисуем контур всего окна и области скроллбара черным цветом
    DllCall("gdiplus.dll\GdipCreatePen1", "UInt", 0xFF000000, "Float", 2.0, "Int", 2, "Ptr*", &pPen := 0)
    DllCall("gdiplus.dll\GdipDrawRectangle", "Ptr", pGraphics, "Ptr", pPen, "Float", 1, "Float", 1, "Float", Width - 2, "Float", Height - 2)
    DllCall("gdiplus.dll\GdipDrawRectangle", "Ptr", pGraphics, "Ptr", pPen, "Float", 1, "Float", 1, "Float", 22, "Float", Height - 2)

    ; Кодируем в PNG
    clsidPNG := Buffer(16)
    DllCall("Ole32.dll\CLSIDFromString", "Str", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "Ptr", clsidPNG)
    DllCall("gdiplus.dll\GdipSaveImageToFile", "Ptr", pBitmap, "WStr", filename, "Ptr", clsidPNG, "Ptr", 0)

    ; Освобождаем память
    DllCall("gdiplus.dll\GdipDeleteBrush", "Ptr", pBrush)
    DllCall("gdiplus.dll\GdipDeleteBrush", "Ptr", pPen)
    DllCall("gdiplus.dll\GdipDeleteGraphics", "Ptr", pGraphics)
    DllCall("gdiplus.dll\GdipDisposeImage", "Ptr", pBitmap)
    DllCall("gdiplus.dll\GdiplusShutdown", "Ptr", pToken)
    DllCall("Kernel32.dll\FreeLibrary", "Ptr", hGdiplus)
}

;------------------------------------------------------------------------------------------------------------------------------------------------------------

ConfirmAndExit(thisGui) {
    if (isChanged) {
        result := MsgBox("Changes has not been saved.`nDo you really want to quit?", "Exit...", "0x24 Owner" thisGui.Hwnd) ; 0x20 Icon?, 0x4 Y/N
        if (result = "No") {
            return 1
        }
    }

    for fontName, relPath in fontsMap {
        if !(fontName = "Segoe UI") {
            fullPath := A_ScriptDir . relPath
            DllCall("Gdi32.dll\RemoveFontResourceEx", "Str", fullPath, "UInt", 0x10, "UInt", 0)
        }
    }
}
