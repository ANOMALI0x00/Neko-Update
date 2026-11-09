cmake_minimum_required(VERSION 3.16)
project(neko-updater-tray VERSION 5.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
# Optimizar tamaño y eliminar código muerto para minimizar la huella de memoria.
# -Os (tamaño), -s (strip), -ffunction-sections/-fdata-sections + gc-sections
# (descartan funciones y datos no usados), -fno-ident (menos metadatos).
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Os -s -ffunction-sections -fdata-sections -fno-ident -fno-exceptions -fno-rtti")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,--gc-sections -Wl,--as-needed")
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,--gc-sections -Wl,--as-needed")
add_link_options(-Wl,--gc-sections -Wl,--as-needed)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(QT NAMES Qt6 Qt5 REQUIRED COMPONENTS Core Gui Widgets)
find_package(Qt${QT_VERSION_MAJOR} COMPONENTS Core Gui Widgets REQUIRED)

add_executable(neko-updater-tray main.cpp)
target_link_libraries(neko-updater-tray PRIVATE Qt${QT_VERSION_MAJOR}::Core Qt${QT_VERSION_MAJOR}::Gui Qt${QT_VERSION_MAJOR}::Widgets)

# i18n: generar los .qm a partir de los .ts
find_program(LRELEASE_EXECUTABLE lrelease)
if(LRELEASE_EXECUTABLE)
    file(GLOB TS_FILES "${CMAKE_CURRENT_SOURCE_DIR}/translations/*.ts")
    set(QM_FILES "")
    foreach(ts ${TS_FILES})
        get_filename_component(base ${ts} NAME_WE)
        set(qm "${CMAKE_CURRENT_BINARY_DIR}/translations/${base}.qm")
        add_custom_command(
            OUTPUT ${qm}
            COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_CURRENT_BINARY_DIR}/translations"
            COMMAND ${LRELEASE_EXECUTABLE} ${ts} -qm ${qm}
            DEPENDS ${ts}
        )
        list(APPEND QM_FILES ${qm})
    endforeach()
    add_custom_target(translations ALL DEPENDS ${QM_FILES})
    install(FILES ${QM_FILES} DESTINATION share/neko-void/translations)
endif()
