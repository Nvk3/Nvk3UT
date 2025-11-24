if GetCVar("Language.2") ~= "de" then
    return
end

local strings = {
    -- Sections
    SI_NVK3UT_LAM_SECTION_JOURNAL = "Journal Erweiterungen",
    SI_NVK3UT_LAM_SECTION_STATUS_TEXT = "Status Text",
    SI_NVK3UT_LAM_SECTION_TRACKER_HOST = "Tracker Host",
    SI_NVK3UT_LAM_SECTION_DEBUG = "Debug & Support",

    -- Journal section
    SI_NVK3UT_LAM_JOURNAL_HEADER_STORAGE = "Favoriten & Daten",
    SI_NVK3UT_LAM_OPTION_JOURNAL_FAVORITE_SCOPE = "Favoritenspeicherung:",
    SI_NVK3UT_LAM_OPTION_JOURNAL_FAVORITE_SCOPE_DESC = "Bestimmt, ob Favoriten global (Account) oder je Charakter gespeichert werden.",
    SI_NVK3UT_LAM_OPTION_JOURNAL_SCOPE_ACCOUNT = "Account-Weit",
    SI_NVK3UT_LAM_OPTION_JOURNAL_SCOPE_CHARACTER = "Charakter-Weit",
    SI_NVK3UT_LAM_OPTION_JOURNAL_RECENT_LIMIT = "Kürzlich-History (max. Einträge)",
    SI_NVK3UT_LAM_OPTION_JOURNAL_RECENT_LIMIT_DESC = "Hardcap für die Anzahl der Kürzlich-Einträge.",
    SI_NVK3UT_LAM_JOURNAL_HEADER_FEATURES = "Funktionen",
    SI_NVK3UT_LAM_OPTION_JOURNAL_FEATURE_COMPLETED = "Abgeschlossen aktiv",
    SI_NVK3UT_LAM_OPTION_JOURNAL_FEATURE_FAVORITES = "Favoriten aktiv",
    SI_NVK3UT_LAM_OPTION_JOURNAL_FEATURE_RECENT = "Kürzlich aktiv",
    SI_NVK3UT_LAM_OPTION_JOURNAL_FEATURE_TODO = "To-Do-Liste aktiv",

    -- Status Text
    SI_NVK3UT_LAM_STATUS_HEADER_DISPLAY = "Anzeige",
    SI_NVK3UT_LAM_OPTION_STATUS_SHOW_COMPASS = "Status über dem Kompass anzeigen",

    -- Tracker Host
    SI_NVK3UT_LAM_TRACKER_HOST_HEADER_WINDOW = "Fenster & Darstellung",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_SHOW = "Fenster anzeigen",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_LOCK = "Fenster sperren",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_ON_TOP = "Immer im Vordergrund",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_WIDTH = "Fensterbreite",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_HEIGHT = "Fensterhöhe",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_HEADER_HEIGHT = "Header-Höhe",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_HEADER_HEIGHT_DESC = "0 px blendet den Bereich aus.",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_FOOTER_HEIGHT = "Footer-Höhe",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_FOOTER_HEIGHT_DESC = "0 px blendet den Bereich aus.",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_RESET_POSITION = "Position zurücksetzen",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_RESET_POSITION_DESC = "Setzt Größe, Position und Verhalten des Tracker-Fensters zurück.",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_HIDE_DEFAULT = "Standard-Quest-Tracker verstecken",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_BACKGROUND = "Hintergrund anzeigen",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_BACKGROUND_ALPHA = "Hintergrund-Transparenz (%)",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_EDGE = "Rahmen anzeigen",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_EDGE_ALPHA = "Rahmen-Transparenz (%)",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_EDGE_THICKNESS = "Rahmenbreite",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_PADDING = "Innenabstand",
    SI_NVK3UT_LAM_TRACKER_HOST_HEADER_LAYOUT = "Auto-Resize & Layout",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_AUTOGROW_V = "Automatisch vertikal anpassen",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_AUTOGROW_H = "Automatisch horizontal anpassen",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_MIN_WIDTH = "Mindestbreite",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_MAX_WIDTH = "Maximalbreite",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_MIN_HEIGHT = "Mindesthöhe",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_MAX_HEIGHT = "Maximalhöhe",
    SI_NVK3UT_LAM_TRACKER_HOST_HEADER_BEHAVIOR = "Verhalten",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_HIDE_IN_COMBAT = "Tracker im Kampf ausblenden",
    SI_NVK3UT_LAM_OPTION_TRACKER_HOST_HIDE_IN_COMBAT_DESC = "Bei Aktivierung wird der gesamte Tracker-Host während des Kampfes ausgeblendet. Im Einstellungsmenü bleibt er sichtbar.",

    -- Debug
    SI_NVK3UT_LAM_OPTION_DEBUG_ENABLE = "Debug aktivieren",
    SI_NVK3UT_LAM_OPTION_SELF_TEST = "Self-Test ausführen",
    SI_NVK3UT_LAM_OPTION_SELF_TEST_DESC = "Führt einen kompakten Integritäts-Check aus. Bei aktiviertem Debug erscheinen ausführliche Chat-Logs.",
    SI_NVK3UT_LAM_OPTION_RELOAD_UI = "UI neu laden",
}

for stringId, value in pairs(strings) do
    SafeAddString(_G[stringId], value, 1)
end
