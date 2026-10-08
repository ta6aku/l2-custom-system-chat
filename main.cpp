#include <windows.h>
#include <tlhelp32.h>
#include <string>
#include <queue>
#include <thread>
#include <mutex>
#include <condition_variable>

// Смещения инструкций
const DWORD NET_OFFSET = 0xD732;      // network.dll (push eax) (Receive)SystemMessagePacket : Msg Number : %d
const DWORD NWINDOW_OFFSET = 0x5704A; // nwindow.dll (push ecx) (ParseL2ParamToFString : )

uintptr_t g_NetTargetAddress = 0;
uintptr_t g_NWindowTargetAddress = 0;

PVOID g_VehHandle = nullptr;
DWORD g_MainThreadId = 0;

// Состояние фильтрации
DWORD g_LastMatchId = 0;

// --- Очередь сообщений для фонового потока ---
struct ChatEvent {
    DWORD id;
    std::wstring text;  // UTF-16, как в игре
};

std::queue<ChatEvent> g_ChatQueue;
std::mutex            g_QueueMutex;
std::condition_variable g_QueueCV;
bool                  g_StopThread = false;
std::thread           g_WorkerThread;

const size_t MAX_QUEUE_SIZE = 200;
const wchar_t* const AHK_TARGET_TITLE = L"L2_SystemChat";
const DWORD SEND_TIMEOUT_MS = 200;

HWND g_CachedHwnd = nullptr;

// Поиск базового адреса модуля
uintptr_t GetModuleBaseAddress(DWORD procId, const wchar_t* modName) {
    uintptr_t modBaseAddr = 0;
    HANDLE hSnap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, procId);
    if (hSnap != INVALID_HANDLE_VALUE) {
        MODULEENTRY32W modEntry;
        modEntry.dwSize = sizeof(modEntry);
        if (Module32FirstW(hSnap, &modEntry)) {
            do {
                if (_wcsicmp(modEntry.szModule, modName) == 0) {
                    modBaseAddr = (uintptr_t)modEntry.modBaseAddr;
                    break;
                }
            } while (Module32NextW(hSnap, &modEntry));
        }
        CloseHandle(hSnap);
    }
    return modBaseAddr;
}

// Функция поиска главного потока
DWORD GetMainThreadId() {
    DWORD pid = GetCurrentProcessId();
    HANDLE hSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    if (hSnapshot == INVALID_HANDLE_VALUE) return 0;
    THREADENTRY32 te;
    te.dwSize = sizeof(THREADENTRY32);
    DWORD oldestThreadId = 0;
    ULONGLONG earliestTime = 0xFFFFFFFFFFFFFFFF;
    if (Thread32First(hSnapshot, &te)) {
        do {
            if (te.th32OwnerProcessID == pid) {
                HANDLE hThread = OpenThread(THREAD_QUERY_INFORMATION, FALSE, te.th32ThreadID);
                if (hThread) {
                    FILETIME createTime, exitTime, kernelTime, userTime;
                    if (GetThreadTimes(hThread, &createTime, &exitTime, &kernelTime, &userTime)) {
                        ULONGLONG time = ((ULONGLONG)createTime.dwHighDateTime << 32) | createTime.dwLowDateTime;
                        if (time < earliestTime) {
                            earliestTime = time;
                            oldestThreadId = te.th32ThreadID;
                        }
                    }
                    CloseHandle(hThread);
                }
            }
        } while (Thread32Next(hSnapshot, &te));
    }
    CloseHandle(hSnapshot);
    return oldestThreadId;
}

// Безопасное чтение UTF-16 строки из памяти игры
std::wstring SafeReadStringW(uintptr_t address) {
    if (!address) return L"";

    MEMORY_BASIC_INFORMATION mbi;
    if (!VirtualQuery((void*)address, &mbi, sizeof(mbi))) return L"";
    if (!(mbi.State & MEM_COMMIT)) return L"";
    if (mbi.Protect & (PAGE_NOACCESS | PAGE_GUARD)) return L"";

    const wchar_t* wstr = (const wchar_t*)address;
    size_t len = 0;
    while (len < 512 && wstr[len] != L'\0') {
        len++;
    }
    if (len == 0) return L"";
    return std::wstring(wstr, len);
}

// Отправка сообщения в AHK через WM_COPYDATA (UTF-16)
bool SendToAHK(const ChatEvent& ev) {
    HWND hwnd = g_CachedHwnd;

    if (!hwnd || !IsWindow(hwnd)) {
        hwnd = FindWindowW(nullptr, AHK_TARGET_TITLE);

        if (!hwnd) {
            HWND gameHwnd = FindWindowW(L"L2UnrealWWindowsViewportWindow", nullptr);
            if (gameHwnd) {
                hwnd = FindWindowExW(gameHwnd, nullptr, nullptr, AHK_TARGET_TITLE);
            }
        }

        g_CachedHwnd = hwnd;
    }

    if (!hwnd) {
        OutputDebugStringW(L"[L2 Chat] SendToAHK: FindWindowW/FindWindowExW failed, HWND not found\n");
        return false;
    }

    // COPYDATASTRUCT с UTF-16 данными
    COPYDATASTRUCT cds = { 0 };
    cds.dwData = (ULONG_PTR)ev.id;
    cds.cbData = (DWORD)((ev.text.size() + 1) * sizeof(wchar_t));
    cds.lpData = (PVOID)ev.text.c_str();

    ULONG_PTR result = 0;
    BOOL ok = SendMessageTimeoutW(hwnd, WM_COPYDATA, 0, (LPARAM)&cds,
                                  SMTO_ABORTIFHUNG, SEND_TIMEOUT_MS, &result);
    if (!ok) {
        wchar_t dbg[128];
        wsprintfW(dbg, L"[L2 Chat] SendMessageTimeoutW failed, err=%lu\n", GetLastError());
        OutputDebugStringW(dbg);
    }
    return ok != 0;
}

// Фоновый поток-отправитель
void BackgroundWorker() {
    while (true) {
        ChatEvent eventToSend;

        {
            std::unique_lock<std::mutex> lock(g_QueueMutex);
            g_QueueCV.wait(lock, [] { return !g_ChatQueue.empty() || g_StopThread; });

            if (g_StopThread && g_ChatQueue.empty()) break;

            eventToSend = g_ChatQueue.front();
            g_ChatQueue.pop();
        }

        // Отправка с таймаутом — не блокирует игру
        if (!SendToAHK(eventToSend)) {
            OutputDebugStringW(L"[L2 Chat] Пакет пропущен, тк AHK недоступен\n");
        }
    }
}

void StartBackgroundThread() {
    g_StopThread = false;
    g_WorkerThread = std::thread(BackgroundWorker);
}

void StopBackgroundThread(bool isProcessTerminating) {
    {
        std::lock_guard<std::mutex> lock(g_QueueMutex);
        g_StopThread = true;
    }
    g_QueueCV.notify_one();

    if (isProcessTerminating) {
        return; 
    }

    if (g_WorkerThread.joinable()) {
        g_WorkerThread.join();
    }
}

// Единый VEH Обработчик для брейкпоинтов
LONG CALLBACK VectoredExceptionHandler(PEXCEPTION_POINTERS ExceptionInfo) {
    if (ExceptionInfo->ExceptionRecord->ExceptionCode == STATUS_SINGLE_STEP) {
        uintptr_t expAddr = (uintptr_t)ExceptionInfo->ExceptionRecord->ExceptionAddress;

        // --- ТОЧКА 1: network.dll (Перехват ID сообщения) ---
        if (expAddr == g_NetTargetAddress) {
            DWORD eventId = ExceptionInfo->ContextRecord->Eax;
            
            g_LastMatchId = eventId;

            ExceptionInfo->ContextRecord->Dr0 = 0;
            ExceptionInfo->ContextRecord->EFlags |= 0x100;
            return EXCEPTION_CONTINUE_EXECUTION;
        }

        // --- ТОЧКА 2: nwindow.dll (Перехват готового текста строки) ---
        if (expAddr == g_NWindowTargetAddress) {
            // Шлём ВСЕ сообщения, фильтрация будет в бизнес-логике
            uintptr_t stringAddress = ExceptionInfo->ContextRecord->Ecx;
            std::wstring logText = SafeReadStringW(stringAddress);

            if (!logText.empty()) {
                wchar_t dbg[512];
                wsprintfW(dbg, L"[L2 Chat] CAPTURED: ID=%lu TEXT=%s\n", g_LastMatchId, logText.c_str());
                OutputDebugStringW(dbg);

                std::lock_guard<std::mutex> lock(g_QueueMutex);
                if (g_ChatQueue.size() < MAX_QUEUE_SIZE) {
                    g_ChatQueue.push({ g_LastMatchId, logText });
                    g_QueueCV.notify_one();
                } else {
                    OutputDebugStringW(L"[L2 Chat] Queue OVERFLOW! Dropping packet.\n");
                }
            }

            ExceptionInfo->ContextRecord->Dr1 = 0;
            ExceptionInfo->ContextRecord->EFlags |= 0x100;
            return EXCEPTION_CONTINUE_EXECUTION;
        }

        // --- ВОССТАНОВЛЕНИЕ БРЕЙКПОИНТОВ ---
        if ((ExceptionInfo->ContextRecord->EFlags & 0x100) == 0) {
            ExceptionInfo->ContextRecord->Dr0 = g_NetTargetAddress;
            ExceptionInfo->ContextRecord->Dr1 = g_NWindowTargetAddress;
            return EXCEPTION_CONTINUE_EXECUTION;
        }
    }
    return EXCEPTION_CONTINUE_SEARCH;
}

DWORD WINAPI HookInitThread(LPVOID lpParam) {
    Sleep(300);

    DWORD pid = GetCurrentProcessId();
    uintptr_t networkBase = GetModuleBaseAddress(pid, L"network.dll");
    uintptr_t nwindowBase = GetModuleBaseAddress(pid, L"nwindow.dll");

    if (!networkBase || !nwindowBase) {
        OutputDebugStringW(L"[L2 Chat] Ошибка: Не удалось найти базы модулей!\n");
        return 0;
    }

    g_NetTargetAddress = networkBase + NET_OFFSET;
    g_NWindowTargetAddress = nwindowBase + NWINDOW_OFFSET;

    g_MainThreadId = GetMainThreadId();
    if (!g_MainThreadId) return 0;

    g_VehHandle = AddVectoredExceptionHandler(1, VectoredExceptionHandler);

    HANDLE hThread = OpenThread(THREAD_GET_CONTEXT | THREAD_SET_CONTEXT | THREAD_SUSPEND_RESUME, FALSE, g_MainThreadId);
    if (hThread) {
        SuspendThread(hThread);
        CONTEXT ctx = { 0 };
        ctx.ContextFlags = CONTEXT_DEBUG_REGISTERS;
        GetThreadContext(hThread, &ctx);

        ctx.Dr0 = g_NetTargetAddress;
        ctx.Dr1 = g_NWindowTargetAddress;
        ctx.Dr7 = 0x00000005; // DR0 local + DR1 local

        SetThreadContext(hThread, &ctx);
        ResumeThread(hThread);
        CloseHandle(hThread);

        OutputDebugStringW(L"[L2 Chat] Системный перехватчик текста успешно запущен!\n");
    }

    StartBackgroundThread();
    return 0;
}

BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved) {
    if (ul_reason_for_call == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(hModule);
        CreateThread(nullptr, 0, HookInitThread, nullptr, 0, nullptr);
    }
    else if (ul_reason_for_call == DLL_PROCESS_DETACH) {
        bool isTerminating = (lpReserved != nullptr);
        
        // Передаем флаг завершения, чтобы не вызывать .join()
        StopBackgroundThread(isTerminating); 
        
        if (g_VehHandle) {
            RemoveVectoredExceptionHandler(g_VehHandle);
        }
    }
    return TRUE;
}