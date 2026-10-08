cmake_minimum_required(VERSION 3.15) 
project(systemmsgext CXX) 

# Стандарт C++11
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# База данных компиляции для clangd/intellisense
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)


if(MSVC)
    # Использовать статическую линковку рантайма (/MT для Release, /MTd для Debug)
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    
    # Отключение части предупреждений MSVC
    add_compile_definitions(_CRT_SECURE_NO_WARNINGS)
endif()


# Список для сборки
add_library(systemmsgext SHARED 
    main.cpp
)

# Линковка библиотек Windows
target_link_libraries(systemmsgext 
    PRIVATE
    user32
    kernel32
)
