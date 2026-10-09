#Requires AutoHotkey v2.0
#SingleInstance Ignore

; === 1. Блок автоперезапуска в 32-бита ===
if (A_PtrSize == 8) {
    ; Определяем путь к 32-битному интерпретатору AHK
    ahk32Path := String(A_AhkPath)
    ahk32Path := RegExReplace(ahk32Path, "i)AutoHotkey64\.exe$", "AutoHotkey32.exe")
    ahk32Path := RegExReplace(ahk32Path, "i)AutoHotkeyUX\.exe$", "v2\AutoHotkey32.exe")

    if FileExist(ahk32Path) {
        Run('"' ahk32Path '" "' A_ScriptFullPath '"') ; Перезапускаем этот же скрипт (%A_ScriptFullPath%), передавая ему те же аргументы
        ExitApp() ; Закрываем текущую 64-битную копию
    } else {
        MsgBox("Критическая ошибка: Не найден 32-битный интерпретатор AutoHotkey32.exe по адресу:`n" ahk32Path, "Ошибка разрядности", 16)
        ExitApp()
    }
}
/*
UNIQUE_MUTEX_NAME := "Local\ahkv2_32bit_dll_loader_l2_systemchat"

; 1. Пытаемся создать мьютекс
hMutex := DllCall("CreateMutex", "Ptr", 0, "Int", false, "Str", UNIQUE_MUTEX_NAME, "Ptr")

; 2. Проверяем системную ошибку "A_LastError" сразу после вызова Windows API
if (A_LastError == 183) {
    ; 183 = ERROR_ALREADY_EXISTS. То есть мьютекс уже был создан первой копией
    DllCall("CloseHandle", "Ptr", hMutex)
    ExitApp()
}

MsgBox(DllCall("GetCurrentProcessId"))
*/


global ChatScriptName := "SystemChat.ahk"
global L2Class := "ahk_class (?i)^L2UnrealWWindowsViewportWindow$"
SetTitleMatchMode "RegEx"


if !(l2Hwnd := WinExist(L2Class))
    ExitApp

l2PID := WinGetPID(l2Hwnd)

if (InjectDLL(l2PID, "systemmsgext.dll")) {
    Run(A_AhkPath ' "' A_ScriptDir '\' ChatScriptName '"')
}


InjectDLL(pid, dllPath) {

    if !(pid) {
        MsgBox("L2.exe не найден.", "Ошибка", 0x10)
        return false
    }

    fullDllPath := FileGetAttrib(dllPath) ? A_ScriptDir "\" dllPath : dllPath
    if not FileExist(fullDllPath) {
        MsgBox("DLL-файл не найден по указанному пути.", "Ошибка", 48)
        return false
    }

    ; 1. Конвертируем строку пути в формат UTF-16 (Unicode) и считаем размер в байтах
    pathLen := (StrLen(fullDllPath) + 1) * 2

    ; 2. Открываем процесс с правами на запись и создание потоков
    ; PROCESS_CREATE_THREAD (0x0002) | PROCESS_VM_OPERATION (0x0008) | PROCESS_VM_WRITE (0x0020) | PROCESS_VM_READ (0x0010)
    hProcess := DllCall("OpenProcess", "UInt", 0x0002 | 0x0008 | 0x0020 | 0x0010, "Int", false, "UInt", pid, "Ptr")
    if not hProcess {
        MsgBox("Не удалось открыть процесс.", "Ошибка", 48)
        return false
    }

    try {
        ; 3. Выделяем память внутри процесса под строку с путем к DLL
        ; MEM_COMMIT (0x1000), PAGE_READWRITE (0x04)
        pRemoteMem := DllCall("VirtualAllocEx", "Ptr", hProcess, "Ptr", 0, "Ptr", pathLen, "UInt", 0x1000, "UInt", 0x04, "Ptr")
        if not pRemoteMem
            throw Error("Не удалось выделить память в целевом процессе.")

        ; 4. Записываем путь к DLL в выделенную память
        if not DllCall("WriteProcessMemory", "Ptr", hProcess, "Ptr", pRemoteMem, "Str", fullDllPath, "Ptr", pathLen, "Ptr", 0)
            throw Error("Не удалось записать данные в память процесса.")

        ; 5. Получаем адрес функции LoadLibraryW из kernel32.dll
        hKernel32 := DllCall("GetModuleHandle", "Str", "kernel32.dll", "Ptr")
        pLoadLibrary := DllCall("GetProcAddress", "Ptr", hKernel32, "AStr", "LoadLibraryW", "Ptr")
        if not pLoadLibrary
            throw Error("Не удалось найти адрес LoadLibraryW.")

        ; 6. Создаем удаленный поток в целевом процессе, который вызовет LoadLibraryW(pRemoteMem)
        hThread := DllCall("CreateRemoteThread", "Ptr", hProcess, "Ptr", 0, "Ptr", 0, "Ptr", pLoadLibrary, "Ptr", pRemoteMem, "UInt", 0, "Ptr", 0, "Ptr")
        if not hThread
            throw Error("Не удалось создать удаленный поток.")

        ; Ожидаем завершения потока и закрываем его хэндл
        DllCall("WaitForSingleObject", "Ptr", hThread, "UInt", 0xFFFFFFFF)
        DllCall("CloseHandle", "Ptr", hThread)

        ;MsgBox("DLL успешно внедрена!", "Успех", 64)
        return true

    } catch Error as err {
        MsgBox("Произошла ошибка: " err.Message, "Ошибка", 48)
        return false
    } finally {
        ; В любом случае освобождаем хэндл процесса
        if hProcess
            DllCall("CloseHandle", "Ptr", hProcess)
    }
}

Persistent(true)

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

