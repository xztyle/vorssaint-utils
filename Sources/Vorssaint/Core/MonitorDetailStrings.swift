// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

/// Labels for the iStat-style stat menus opened from Aster's own menu bar stats.
struct MonitorDetailStrings {
    let user: String
    let system: String
    let cores: String
    let loadAverage: String
    /// "%d performance · %d efficiency"
    let coreKindsFormat: String
    let app: String
    let wired: String
    let compressed: String
    let cached: String
    let free: String
    let sensors: String
    let used: String
    /// Names for SensorGroup cases, in declaration order.
    let sensorGroups: [String]

    static func localized(_ language: AppLanguage) -> Self {
        let row = rows[language]!.components(separatedBy: "|")
        return .init(user: row[0], system: row[1], cores: row[2], loadAverage: row[3], coreKindsFormat: row[4],
                     app: row[5], wired: row[6], compressed: row[7], cached: row[8], free: row[9],
                     sensors: row[10], used: row[20], sensorGroups: Array(row[11...19]))
    }

    private static let rows: [AppLanguage: String] = [
        .enUS: "User|System|Cores|Load average|%d performance · %d efficiency|App|Wired|Compressed|Cached|Free|Sensors|CPU performance cores|CPU efficiency cores|GPU|Memory|Battery|SSD|Wi‑Fi|Case|Ambient|Used",
        .es: "Usuario|Sistema|Núcleos|Carga media|%d de rendimiento · %d de eficiencia|Apps|Fija|Comprimida|En caché|Libre|Sensores|Núcleos de rendimiento|Núcleos de eficiencia|GPU|Memoria|Batería|SSD|Wi‑Fi|Carcasa|Ambiente|Usado",
        .ptBR: "Usuário|Sistema|Núcleos|Carga média|%d de desempenho · %d de eficiência|Apps|Fixa|Comprimida|Em cache|Livre|Sensores|Núcleos de desempenho|Núcleos de eficiência|GPU|Memória|Bateria|SSD|Wi‑Fi|Gabinete|Ambiente|Usado",
        .tr: "Kullanıcı|Sistem|Çekirdekler|Ortalama yük|%d performans · %d verimlilik|Uygulama|Kalıcı|Sıkıştırılmış|Önbellek|Boş|Sensörler|Performans çekirdekleri|Verimlilik çekirdekleri|GPU|Bellek|Pil|SSD|Wi‑Fi|Kasa|Ortam|Kullanılan",
        .ru: "Пользователь|Система|Ядра|Средняя нагрузка|%d производительных · %d энергоэффективных|Приложения|Зарезервировано|Сжато|Кэш|Свободно|Датчики|Производительные ядра|Энергоэффективные ядра|GPU|Память|Аккумулятор|SSD|Wi‑Fi|Корпус|Окружение|Занято",
        .sk: "Používateľ|Systém|Jadrá|Priemerná záťaž|%d výkonných · %d úsporných|Aplikácie|Pevná|Komprimovaná|Vo vyrov. pamäti|Voľná|Senzory|Výkonné jadrá|Úsporné jadrá|GPU|Pamäť|Batéria|SSD|Wi‑Fi|Telo|Okolie|Použité",
        .de: "Benutzer|System|Kerne|Durchschnittslast|%d Leistung · %d Effizienz|Apps|Reserviert|Komprimiert|Zwischengesp.|Frei|Sensoren|Leistungskerne|Effizienzkerne|GPU|Speicher|Batterie|SSD|WLAN|Gehäuse|Umgebung|Belegt",
        .fr: "Utilisateur|Système|Cœurs|Charge moyenne|%d performance · %d efficacité|Apps|Résidente|Compressée|En cache|Libre|Capteurs|Cœurs performance|Cœurs efficacité|GPU|Mémoire|Batterie|SSD|Wi‑Fi|Boîtier|Ambiante|Utilisé",
        .it: "Utente|Sistema|Core|Carico medio|%d prestazioni · %d efficienza|App|Wired|Compressa|In cache|Libera|Sensori|Core prestazioni|Core efficienza|GPU|Memoria|Batteria|SSD|Wi‑Fi|Scocca|Ambiente|Usato",
        .ja: "ユーザ|システム|コア|ロードアベレージ|高性能 %d · 高効率 %d|アプリ|確保|圧縮|キャッシュ|空き|センサー|高性能コア|高効率コア|GPU|メモリ|バッテリー|SSD|Wi‑Fi|筐体|周囲|使用済み",
        .ko: "사용자|시스템|코어|평균 부하|성능 %d · 효율 %d|앱|고정|압축|캐시|여유|센서|성능 코어|효율 코어|GPU|메모리|배터리|SSD|Wi‑Fi|케이스|주변|사용됨",
        .uk: "Користувач|Система|Ядра|Середнє навантаження|%d продуктивних · %d енергоефективних|Програми|Зарезервовано|Стиснуто|Кеш|Вільно|Датчики|Продуктивні ядра|Енергоефективні ядра|GPU|Пам’ять|Акумулятор|SSD|Wi‑Fi|Корпус|Довкілля|Зайнято",
        .zhHans: "用户|系统|核心|平均负载|%d 性能 · %d 能效|应用|联动|已压缩|已缓存|可用|传感器|性能核心|能效核心|GPU|内存|电池|SSD|Wi‑Fi|机身|环境|已用",
        .zhTW: "使用者|系統|核心|平均負載|%d 效能 · %d 節能|App|固定|已壓縮|已快取|可用|感測器|效能核心|節能核心|GPU|記憶體|電池|SSD|Wi‑Fi|機身|環境|已使用",
        .zhHK: "使用者|系統|核心|平均負載|%d 效能 · %d 節能|App|固定|已壓縮|已快取|可用|感應器|效能核心|節能核心|GPU|記憶體|電池|SSD|Wi‑Fi|機身|環境|已使用",
    ]
}
