cmake_minimum_required(VERSION 3.24)
project(Omakon VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Quick QuickControls2 Qml Core Gui)

qt_standard_project_setup(REQUIRES 6.6)

qt_add_executable(omakon
    main.cpp
    filestorage.cpp
    filestorage.h
)

# ---------------------------------------------------------------------------
# The game is developed at ../ (the Omarchy plugin repo root). We stage the
# shared sources into the build dir so:
#   (a) qt_add_qml_module sees a single-directory layout,
#   (b) relative imports in the QML/JS resolve unchanged,
#   (c) data JSONs get a clean qrc prefix.
# Edits to ../Panel.qml, ../Dungeon.js etc. take effect on the next
# `cmake --build` (configure_file reruns at configure time; ninja will
# reconfigure the build automatically when CMakeLists.txt changes — for
# pure-content edits, just rerun `cmake --build`).
# ---------------------------------------------------------------------------
set(PARENT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/..")
set(STAGED_DIR "${CMAKE_CURRENT_BINARY_DIR}/game")
file(MAKE_DIRECTORY "${STAGED_DIR}/data")

set(GAME_SOURCES
    Panel.qml Dungeon.js Save.js Combat.js Stats.js Monsters.js Drops.js
    Dice.js CombatLoop.js Poison.js Spells.js Enchant.js
)
set(GAME_DATA monsters.json equipment.json spells.json)
# Icon glyphs are PUA characters from JetBrainsMono Nerd Font — bundle the
# TTFs into the binary so the app renders correctly on machines without the
# font installed (e.g. fresh Windows).
set(APP_FONTS
    fonts/JetBrainsMonoNerdFont-Regular.ttf
    fonts/JetBrainsMonoNerdFont-Bold.ttf
)

foreach(f ${GAME_SOURCES})
    if(EXISTS "${PARENT_DIR}/${f}")
        configure_file("${PARENT_DIR}/${f}" "${STAGED_DIR}/${f}" COPYONLY)
    else()
        message(FATAL_ERROR "Missing game source: ${PARENT_DIR}/${f}")
    endif()
endforeach()
foreach(f ${GAME_DATA})
    if(EXISTS "${PARENT_DIR}/${f}")
        configure_file("${PARENT_DIR}/${f}" "${STAGED_DIR}/data/${f}" COPYONLY)
    else()
        message(FATAL_ERROR "Missing game data: ${PARENT_DIR}/${f}")
    endif()
endforeach()

# QT_RESOURCE_ALIAS must be set on the file BEFORE qt_add_qml_module —
# the macro snapshots the properties at add time.
set_source_files_properties(${STAGED_DIR}/Panel.qml
    PROPERTIES QT_RESOURCE_ALIAS "Panel.qml")
foreach(f Dungeon.js Save.js Combat.js Stats.js Monsters.js Drops.js
          Dice.js CombatLoop.js Poison.js Spells.js Enchant.js)
    set_source_files_properties(${STAGED_DIR}/${f}
        PROPERTIES QT_RESOURCE_ALIAS "${f}")
endforeach()
foreach(f ${GAME_DATA})
    set_source_files_properties(${STAGED_DIR}/data/${f}
        PROPERTIES QT_RESOURCE_ALIAS "data/${f}")
endforeach()
foreach(f ${APP_FONTS})
    # f already includes the fonts/ subdir, so the alias is f verbatim.
    set_source_files_properties(${CMAKE_CURRENT_SOURCE_DIR}/${f}
        PROPERTIES QT_RESOURCE_ALIAS "${f}")
endforeach()

qt_add_qml_module(omakon
    URI Omakon
    VERSION 1.0
    QML_FILES
        main.qml
        ${STAGED_DIR}/Panel.qml
    RESOURCES
        ${STAGED_DIR}/Dungeon.js
        ${STAGED_DIR}/Save.js
        ${STAGED_DIR}/Combat.js
        ${STAGED_DIR}/Stats.js
        ${STAGED_DIR}/Monsters.js
        ${STAGED_DIR}/Drops.js
        ${STAGED_DIR}/Dice.js
        ${STAGED_DIR}/CombatLoop.js
        ${STAGED_DIR}/Poison.js
        ${STAGED_DIR}/Spells.js
        ${STAGED_DIR}/Enchant.js
        ${STAGED_DIR}/data/monsters.json
        ${STAGED_DIR}/data/equipment.json
        ${STAGED_DIR}/data/spells.json
        ${CMAKE_CURRENT_SOURCE_DIR}/fonts/JetBrainsMonoNerdFont-Regular.ttf
        ${CMAKE_CURRENT_SOURCE_DIR}/fonts/JetBrainsMonoNerdFont-Bold.ttf
)

target_link_libraries(omakon PRIVATE
    Qt6::Quick Qt6::QuickControls2 Qt6::Qml Qt6::Gui Qt6::Core)

set_target_properties(omakon PROPERTIES
    WIN32_EXECUTABLE TRUE
    MACOSX_BUNDLE TRUE
)

install(TARGETS omakon BUNDLE DESTINATION . RUNTIME DESTINATION bin)
