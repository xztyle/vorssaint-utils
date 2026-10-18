// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation

struct StorageMapStrings {
    enum Key: Int, CaseIterable { case title, roots, other, empty, note }
    let language: AppLanguage
    subscript(_ key: Key) -> String { Self.values[language]![key.rawValue] }
    static let values: [AppLanguage: [String]] = [
        .enUS: ["Storage map", "Scanned folders", "Other items", "No measured local space here", "Circle area shows scanned local space. Excluded files are not included."],
        .es: ["Mapa de almacenamiento", "Carpetas analizadas", "Otros elementos", "No hay espacio local medido aquí", "El área de los círculos muestra el espacio local analizado. No incluye archivos excluidos."],
        .ptBR: ["Mapa de armazenamento", "Pastas analisadas", "Outros itens", "Nenhum espaço local medido aqui", "A área dos círculos mostra o espaço local analisado. Arquivos excluídos não estão incluídos."],
        .tr: ["Depolama haritası", "Taranan klasörler", "Diğer öğeler", "Burada ölçülen yerel alan yok", "Daire alanı taranan yerel alanı gösterir. Hariç tutulan dosyalar dahil değildir."],
        .ru: ["Карта хранилища", "Просканированные папки", "Другие объекты", "Здесь нет измеренного локального места", "Площадь кругов показывает просканированное локальное место. Исключённые файлы не учитываются."],
        .sk: ["Mapa úložiska", "Skenované priečinky", "Ostatné položky", "Žiadne namerané lokálne miesto", "Plocha kruhov zobrazuje skenované lokálne miesto. Vylúčené súbory nie sú zahrnuté."],
        .de: ["Speicherkarte", "Gescannte Ordner", "Weitere Objekte", "Hier kein gemessener lokaler Speicher", "Die Kreisfläche zeigt gescannten lokalen Speicher. Ausgeschlossene Dateien sind nicht enthalten."],
        .fr: ["Carte du stockage", "Dossiers analysés", "Autres éléments", "Aucun espace local mesuré ici", "La surface des cercles indique l’espace local analysé. Les fichiers exclus ne sont pas inclus."],
        .it: ["Mappa dello spazio", "Cartelle analizzate", "Altri elementi", "Nessuno spazio locale misurato qui", "L’area dei cerchi indica lo spazio locale analizzato. I file esclusi non sono inclusi."],
        .ja: ["ストレージマップ", "スキャンしたフォルダ", "その他の項目", "測定されたローカル容量はありません", "円の面積はスキャンしたローカル容量を示します。除外されたファイルは含まれません。"],
        .ko: ["저장 공간 지도", "검사한 폴더", "기타 항목", "측정된 로컬 공간 없음", "원의 면적은 검사한 로컬 공간을 나타냅니다. 제외된 파일은 포함되지 않습니다."],
        .zhHans: ["存储空间图", "已扫描文件夹", "其他项目", "此处没有测量到本地空间", "圆圈面积表示已扫描的本地空间。不包含已排除的文件。"],
        .zhTW: ["儲存空間圖", "已掃描資料夾", "其他項目", "此處沒有測量到本機空間", "圓圈面積表示已掃描的本機空間。不包含已排除的檔案。"],
        .zhHK: ["儲存空間圖", "已掃描資料夾", "其他項目", "此處沒有測量到本機空間", "圓圈面積表示已掃描的本機空間。不包含已排除的檔案。"],
        .uk: ["Карта сховища", "Проскановані папки", "Інші об’єкти", "Тут немає виміряного локального місця", "Площа кіл показує проскановане локальне місце. Виключені файли не враховуються."],
    ]
}
