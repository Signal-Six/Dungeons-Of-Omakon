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

# Bundle the data tables under a "data/" prefix and point a qml-module
# resource entry at it BEFORE qt_add_qml_module so the aliases apply.
foreach(f monsters.json equipment.json spells.json)
    set_source_files_properties(${f}
        PROPERTIES QT_RESOURCE_ALIAS "data/${f}")
endforeach()

qt_add_qml_module(omakon
    URI Omakon
    VERSION 1.0
    QML_FILES
        main.qml
        Panel.qml
    RESOURCES
        Dungeon.js
        Save.js
        Combat.js
        Stats.js
        Monsters.js
        Drops.js
        Dice.js
        CombatLoop.js
        Poison.js
        Spells.js
        Enchant.js
        monsters.json
        equipment.json
        spells.json
)

target_link_libraries(omakon PRIVATE
    Qt6::Quick Qt6::QuickControls2 Qt6::Qml Qt6::Gui Qt6::Core)

set_target_properties(omakon PROPERTIES
    WIN32_EXECUTABLE TRUE
    MACOSX_BUNDLE TRUE
)

install(TARGETS omakon BUNDLE DESTINATION . RUNTIME DESTINATION bin)
