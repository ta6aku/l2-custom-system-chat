cmake_minimum_required(VERSION 3.15) 
project(systemmsgext CXX) 

# Стандарт C++11
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# База данных компиляции для clangd/intellisense
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Target для сборки
add_library(systemmsgext SHARED 
    main.cpp
)

# Свойства
if(MSVC)
    # Использовать статическую линковку рантайма (/MT для Release, /MTd для Debug)
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    
    # Отключение части предупреждений MSVC
    add_compile_definitions(_CRT_SECURE_NO_WARNINGS)

    # Принудительная генерация PDB для конфигураций Release и RelWithDebInfo
    target_compile_options(systemmsgext PRIVATE $<$<CONFIG:Release,RelWithDebInfo>:/Zi>)
    target_link_options(systemmsgext PRIVATE $<$<CONFIG:Release,RelWithDebInfo>:/DEBUG>)
endif()

# Линковка библиотек Windows
target_link_libraries(systemmsgext 
    PRIVATE
    user32
    kernel32
)
