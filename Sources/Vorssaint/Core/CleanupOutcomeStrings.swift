// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation

enum CleanupOutcomeStrings {
    static func trashedSize(_ size: String, language: AppLanguage) -> String {
        String(format: formats[language]!, size)
    }

    static func removedSize(_ size: String, language: AppLanguage) -> String {
        String(format: removalFormats[language]!, size)
    }

    static func recovery(language: AppLanguage) -> String { recoveryTexts[language]! }

    private static let recoveryTexts: [AppLanguage: String] = [
        .enUS: "To restore, open Trash in Finder and move the item to its original folder. Use Put Back if available.",
        .es: "Para restaurar, abre la Papelera en Finder y mueve el ítem a su carpeta original. Usa Sacar de la Papelera si está disponible.",
        .ptBR: "Para restaurar, abra a Lixeira no Finder e mova o item para a pasta original. Use Colocar de Volta se estiver disponível.",
        .tr: "Geri yüklemek için Finder’da Çöp Sepeti’ni açıp öğeyi özgün klasörüne taşıyın. Varsa Geri Koy’u kullanın.",
        .ru: "Для восстановления откройте Корзину в Finder и переместите объект в исходную папку. Используйте «Вернуть», если доступно.",
        .sk: "Na obnovenie otvorte Kôš vo Finderi a presuňte položku do pôvodného priečinka. Ak je dostupné, použite Vrátiť späť.",
        .de: "Zum Wiederherstellen den Papierkorb im Finder öffnen und das Objekt in seinen ursprünglichen Ordner verschieben. Wenn verfügbar, Zurücklegen verwenden.",
        .fr: "Pour restaurer, ouvrez la corbeille dans le Finder et déplacez l’élément vers son dossier d’origine. Utilisez Remettre si disponible.",
        .it: "Per ripristinare, apri il Cestino nel Finder e sposta l’elemento nella cartella originale. Usa Rimetti se disponibile.",
        .ja: "復元するにはFinderでゴミ箱を開き、項目を元のフォルダに移動します。「戻す」が利用できる場合は使えます。",
        .ko: "복원하려면 Finder에서 휴지통을 열고 항목을 원래 폴더로 이동하세요. 사용 가능한 경우 되돌려 놓기를 사용하세요.",
        .zhHans: "要恢复，请在访达中打开废纸篓，将项目移回原来的文件夹。如果可用，可选择放回原处。",
        .zhTW: "若要復原，請在Finder中開啟垃圾桶，將項目移回原來的資料夾。如果可用，可選擇放回原處。",
        .zhHK: "若要復原，請在Finder中開啟垃圾桶，將項目移回原來的資料夾。如果可用，可選擇放回原處。",
        .uk: "Для відновлення відкрийте Смітник у Finder і перемістіть об’єкт у початкову папку. Скористайтеся «Повернути», якщо доступно.",
    ]

    private static let removalFormats: [AppLanguage: String] = [
        .enUS: "%@ removed", .es: "%@ eliminados", .ptBR: "%@ removidos",
        .tr: "%@ kaldırıldı", .ru: "%@ удалено", .sk: "%@ odstránené",
        .de: "%@ entfernt", .fr: "%@ retirés", .it: "%@ rimossi",
        .ja: "%@ を削除しました", .ko: "%@ 제거됨", .zhHans: "%@ 已移除",
        .zhTW: "%@ 已移除", .zhHK: "%@ 已移除", .uk: "%@ видалено",
    ]

    private static let formats: [AppLanguage: String] = [
        .enUS: "%@ moved to Trash",
        .es: "%@ movidos a la Papelera",
        .ptBR: "%@ movidos para a Lixeira",
        .tr: "%@ Çöp Sepeti’ne taşındı",
        .ru: "%@ перемещено в Корзину",
        .sk: "%@ presunuté do Koša",
        .de: "%@ in den Papierkorb verschoben",
        .fr: "%@ déplacés vers la corbeille",
        .it: "%@ spostati nel Cestino",
        .ja: "%@ をゴミ箱に移動しました",
        .ko: "%@ 휴지통으로 이동됨",
        .zhHans: "%@ 已移到废纸篓",
        .zhTW: "%@ 已移到垃圾桶",
        .zhHK: "%@ 已移到垃圾桶",
        .uk: "%@ переміщено в Смітник",
    ]
}
