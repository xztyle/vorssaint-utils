// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation

enum PowerFlowText: Int, CaseIterable {
    case title, live, stale, mac, charging, paused, discharging, assisting, details
    case derived, settling, measured, display, leftPort, rightPort, activityNote, unavailable
    case chip, other, cpu, gpu, neuralEngine, chipNote, showChip, hideChip
}

struct PowerFlowStrings: CustomReflectable {
    let values: [String]
    var customMirror: Mirror {
        let fields = PowerFlowText.allCases.map { (String(describing: $0), self[$0]) }
        return Mirror(self, children: fields, displayStyle: .struct)
    }
    subscript(_ key: PowerFlowText) -> String { values[key.rawValue] }
    func state(_ state: PowerFlowModel.State) -> String {
        switch state {
        case .charging: return self[.charging]
        case .paused: return self[.paused]
        case .discharging: return self[.discharging]
        case .assisting: return self[.assisting]
        case .unavailable: return self[.unavailable]
        }
    }
    func chipComponent(_ component: ChipPowerComponent, memory: String) -> String {
        switch component {
        case .cpu: return self[.cpu]
        case .gpu: return self[.gpu]
        case .neuralEngine: return self[.neuralEngine]
        case .memory: return memory
        }
    }
    func component(_ component: PowerComponent, memory: String) -> String {
        switch component {
        case .display: return self[.display]
        case .memory: return memory
        case .leftPort: return self[.leftPort]
        case .rightPort: return self[.rightPort]
        }
    }
}

extension FeatureStrings {
    static func powerFlow(_ language: AppLanguage) -> PowerFlowStrings {
        PowerFlowStrings(values: (PowerFlowTranslations.rows[language] ?? PowerFlowTranslations.rows[.enUS]!)
            + (PowerFlowTranslations.chipRows[language] ?? PowerFlowTranslations.chipRows[.enUS]!))
    }
}

private enum PowerFlowTranslations {
    static let chipRows: [AppLanguage: [String]] = [
        .enUS: ["Chip", "Other", "CPU", "GPU", "Neural engine", "Chip power is CPU + GPU + neural engine energy measured over the last interval. Other is Mac power minus chip power, including memory, display and connected devices.", "Show chip power", "Hide chip power"],
        .es: ["Chip", "Otros", "CPU", "GPU", "Motor neuronal", "La energía del chip suma CPU, GPU y motor neuronal medidos durante el último intervalo. Otros es la energía al Mac menos la del chip e incluye memoria, pantalla y dispositivos conectados.", "Mostrar energía del chip", "Ocultar energía del chip"],
        .ptBR: ["Chip", "Outros", "CPU", "GPU", "Motor neural", "A potência do chip soma CPU, GPU e motor neural medidos no último intervalo. Outros é a potência do Mac menos a do chip, incluindo memória, tela e dispositivos conectados.", "Mostrar potência do chip", "Ocultar potência do chip"],
        .de: ["Chip", "Andere", "CPU", "GPU", "Neural Engine", "Die Chipleistung summiert CPU, GPU und Neural Engine im letzten Messintervall. Andere ist die Mac-Leistung abzüglich Chipleistung und umfasst Speicher, Display und angeschlossene Geräte.", "Chipleistung anzeigen", "Chipleistung ausblenden"],
        .fr: ["Puce", "Autres", "CPU", "GPU", "Moteur neuronal", "La puissance de la puce additionne CPU, GPU et moteur neuronal mesurés sur le dernier intervalle. Autres est la puissance du Mac moins celle de la puce, incluant mémoire, écran et appareils connectés.", "Afficher la puissance de la puce", "Masquer la puissance de la puce"],
        .it: ["Chip", "Altro", "CPU", "GPU", "Motore neurale", "La potenza del chip somma CPU, GPU e motore neurale misurati nell’ultimo intervallo. Altro è la potenza del Mac meno quella del chip e comprende memoria, schermo e dispositivi collegati.", "Mostra potenza del chip", "Nascondi potenza del chip"],
        .ru: ["Чип", "Остальное", "CPU", "GPU", "Нейронный движок", "Мощность чипа: сумма CPU, GPU и нейронного движка за последний интервал. Остальное: мощность Mac за вычетом чипа, включая память, экран и подключённые устройства.", "Показать мощность чипа", "Скрыть мощность чипа"],
        .uk: ["Чип", "Інше", "CPU", "GPU", "Нейронний рушій", "Потужність чипа: сума CPU, GPU й нейронного рушія за останній інтервал. Інше: потужність Mac без чипа, включно з пам’яттю, екраном і підключеними пристроями.", "Показати потужність чипа", "Приховати потужність чипа"],
        .tr: ["Çip", "Diğer", "CPU", "GPU", "Sinir motoru", "Çip gücü, son aralıkta ölçülen CPU, GPU ve sinir motorunun toplamıdır. Diğer, Mac gücünden çip gücü çıkarılarak hesaplanır; bellek, ekran ve bağlı aygıtları içerir.", "Çip gücünü göster", "Çip gücünü gizle"],
        .sk: ["Čip", "Ostatné", "CPU", "GPU", "Neurónový engine", "Výkon čipu je súčet CPU, GPU a neurónového enginu za posledný interval. Ostatné je výkon Macu mínus výkon čipu a zahŕňa pamäť, displej a pripojené zariadenia.", "Zobraziť výkon čipu", "Skryť výkon čipu"],
        .ja: ["チップ", "その他", "CPU", "GPU", "ニューラルエンジン", "チップ電力は直前の測定区間のCPU、GPU、ニューラルエンジンの合計です。その他はMac電力からチップ電力を引いた値で、メモリ、画面、接続機器を含みます。", "チップ電力を表示", "チップ電力を非表示"],
        .ko: ["칩", "기타", "CPU", "GPU", "뉴럴 엔진", "칩 전력은 최근 측정 구간의 CPU, GPU 및 뉴럴 엔진 합계입니다. 기타는 Mac 전력에서 칩 전력을 뺀 값으로 메모리, 화면 및 연결된 기기를 포함합니다.", "칩 전력 표시", "칩 전력 숨기기"],
        .zhHans: ["芯片", "其他", "CPU", "GPU", "神经网络引擎", "芯片功率是上一个测量间隔内 CPU、GPU 和神经网络引擎的总和。其他为 Mac 功率减去芯片功率，包括内存、屏幕和连接设备。", "显示芯片功率", "隐藏芯片功率"],
        .zhTW: ["晶片", "其他", "CPU", "GPU", "神經網路引擎", "晶片功率是上一個測量間隔內 CPU、GPU 和神經網路引擎的總和。其他為 Mac 功率減去晶片功率，包括記憶體、螢幕和連接裝置。", "顯示晶片功率", "隱藏晶片功率"],
        .zhHK: ["晶片", "其他", "CPU", "GPU", "神經網絡引擎", "晶片功率是上一個測量間隔內 CPU、GPU 和神經網絡引擎的總和。其他為 Mac 功率減去晶片功率，包括記憶體、螢幕和連接裝置。", "顯示晶片功率", "隱藏晶片功率"],
    ]

    static let rows: [AppLanguage: [String]] = [
        .enUS: ["Power flow", "Live", "Waiting for fresh readings", "To Mac", "Charging", "Charging paused", "Battery power", "Charger + battery", "Power breakdown",
            "Power to Mac is calculated from charger input and battery flow. The system sensor is measured separately; readings can differ.", "Readings settling", "Measured sensors", "Display backlight", "Left Thunderbolt", "Right Thunderbolt", "App activity uses CPU and GPU usage. It is not measured watts per app.", "Power flow unavailable"],
        .es: ["Flujo de energía", "En vivo", "Esperando lecturas nuevas", "Al Mac", "Cargando", "Carga pausada", "Energía de batería", "Cargador + batería", "Desglose de energía",
            "La energía al Mac se calcula con la entrada del cargador y el flujo de la batería. El sensor del sistema se mide por separado; las lecturas pueden diferir.", "Estabilizando lecturas", "Sensores medidos", "Retroiluminación", "Thunderbolt izquierdo", "Thunderbolt derecho", "La actividad de las apps usa el uso de CPU y GPU. No son vatios medidos por app.", "Flujo no disponible"],
        .ptBR: ["Fluxo de energia", "Ao vivo", "Aguardando novas leituras", "Para o Mac", "Carregando", "Carga pausada", "Energia da bateria", "Carregador + bateria", "Detalhes de energia",
            "A energia para o Mac é calculada pela entrada do carregador e pelo fluxo da bateria. O sensor do sistema é medido separadamente; as leituras podem diferir.", "Estabilizando leituras", "Sensores medidos", "Luz da tela", "Thunderbolt esquerdo", "Thunderbolt direito", "A atividade dos apps usa o uso de CPU e GPU. Não são watts medidos por app.", "Fluxo indisponível"],
        .de: ["Energiefluss", "Live", "Neue Messwerte werden erwartet", "Zum Mac", "Lädt", "Laden pausiert", "Batteriestrom", "Netzteil + Batterie", "Energieübersicht",
            "Die Leistung zum Mac wird aus Netzteileingang und Batteriefluss berechnet. Der Systemsensor wird separat gemessen; Werte können abweichen.", "Messwerte stabilisieren sich", "Gemessene Sensoren", "Displaybeleuchtung", "Thunderbolt links", "Thunderbolt rechts", "Die App-Aktivität nutzt CPU- und GPU-Auslastung. Sie zeigt keine gemessenen Watt pro App.", "Energiefluss nicht verfügbar"],
        .fr: ["Flux d’énergie", "En direct", "En attente de nouvelles mesures", "Vers le Mac", "En charge", "Charge en pause", "Sur batterie", "Chargeur + batterie", "Détail de l’énergie",
            "La puissance vers le Mac est calculée à partir du chargeur et du flux de la batterie. Le capteur système est mesuré séparément ; les valeurs peuvent différer.", "Mesures en cours de stabilisation", "Capteurs mesurés", "Rétroéclairage", "Thunderbolt gauche", "Thunderbolt droit", "L’activité des apps utilise la charge CPU et GPU. Ce ne sont pas des watts mesurés par app.", "Flux indisponible"],
        .it: ["Flusso di energia", "In tempo reale", "In attesa di nuove letture", "Al Mac", "In carica", "Carica in pausa", "Energia della batteria", "Alimentatore + batteria", "Dettagli energia",
            "La potenza al Mac è calcolata dall’ingresso dell’alimentatore e dal flusso della batteria. Il sensore di sistema è misurato separatamente; i valori possono differire.", "Letture in stabilizzazione", "Sensori misurati", "Retroilluminazione", "Thunderbolt sinistro", "Thunderbolt destro", "L’attività delle app usa l’utilizzo di CPU e GPU. Non sono watt misurati per app.", "Flusso non disponibile"],
        .tr: ["Güç akışı", "Canlı", "Yeni okumalar bekleniyor", "Mac’e", "Şarj oluyor", "Şarj duraklatıldı", "Pil gücü", "Adaptör + pil", "Güç ayrıntıları",
            "Mac’e giden güç, adaptör girişi ve pil akışından hesaplanır. Sistem sensörü ayrı ölçülür; okumalar farklı olabilir.", "Okumalar dengeleniyor", "Ölçülen sensörler", "Ekran arka ışığı", "Sol Thunderbolt", "Sağ Thunderbolt", "Uygulama etkinliği CPU ve GPU kullanımına dayanır. Uygulama başına ölçülen watt değildir.", "Güç akışı kullanılamıyor"],
        .ru: ["Поток энергии", "Сейчас", "Ожидание новых показаний", "К Mac", "Заряжается", "Зарядка приостановлена", "Питание от батареи", "Адаптер + батарея", "Расход энергии",
            "Мощность для Mac рассчитывается по входу адаптера и потоку батареи. Датчик системы измеряется отдельно; показания могут различаться.", "Показания стабилизируются", "Измеренные датчики", "Подсветка экрана", "Левый Thunderbolt", "Правый Thunderbolt", "Активность приложений основана на загрузке CPU и GPU. Это не измеренные ватты каждого приложения.", "Поток энергии недоступен"],
        .uk: ["Потік енергії", "Наживо", "Очікування нових показників", "До Mac", "Заряджання", "Заряджання призупинено", "Живлення від батареї", "Адаптер + батарея", "Витрати енергії",
            "Потужність до Mac обчислюється за входом адаптера та потоком батареї. Датчик системи вимірюється окремо; показники можуть відрізнятися.", "Показники стабілізуються", "Виміряні датчики", "Підсвічування екрана", "Лівий Thunderbolt", "Правий Thunderbolt", "Активність програм базується на завантаженні CPU та GPU. Це не виміряні вати кожної програми.", "Потік енергії недоступний"],
        .sk: ["Tok energie", "Naživo", "Čaká sa na nové údaje", "Do Macu", "Nabíja sa", "Nabíjanie pozastavené", "Napájanie z batérie", "Adaptér + batéria", "Prehľad energie",
            "Výkon do Macu sa počíta zo vstupu adaptéra a toku batérie. Systémový snímač sa meria samostatne; údaje sa môžu líšiť.", "Údaje sa ustáľujú", "Merané snímače", "Podsvietenie displeja", "Ľavý Thunderbolt", "Pravý Thunderbolt", "Aktivita aplikácií používa vyťaženie CPU a GPU. Nie sú to merané watty na aplikáciu.", "Tok energie nie je dostupný"],
        .ja: ["電力の流れ", "ライブ", "新しい測定値を待機中", "Macへ", "充電中", "充電停止中", "バッテリー給電", "充電器＋バッテリー", "電力の内訳",
            "Macへの電力は充電器の入力とバッテリーの流れから計算します。システムセンサーは別に測定するため、値が異なる場合があります。", "測定値を安定化中", "測定センサー", "画面バックライト", "左Thunderbolt", "右Thunderbolt", "アプリの活動はCPUとGPUの使用率です。アプリごとの実測ワット数ではありません。", "電力の流れを取得できません"],
        .ko: ["전력 흐름", "실시간", "새 측정값 대기 중", "Mac으로", "충전 중", "충전 일시 정지", "배터리 전력", "충전기 + 배터리", "전력 분석",
            "Mac 전력은 충전기 입력과 배터리 흐름으로 계산합니다. 시스템 센서는 별도로 측정하므로 값이 다를 수 있습니다.", "측정값 안정화 중", "측정 센서", "화면 백라이트", "왼쪽 Thunderbolt", "오른쪽 Thunderbolt", "앱 활동은 CPU 및 GPU 사용률입니다. 앱별로 측정한 와트가 아닙니다.", "전력 흐름을 사용할 수 없음"],
        .zhHans: ["电力流向", "实时", "等待新读数", "供给 Mac", "正在充电", "充电暂停", "电池供电", "充电器＋电池", "电力明细",
            "供给 Mac 的电力根据充电器输入和电池流向计算。系统传感器单独测量，读数可能不同。", "读数稳定中", "实测传感器", "屏幕背光", "左侧雷雳", "右侧雷雳", "应用活动基于 CPU 和 GPU 使用率，并非各应用的实测瓦数。", "电力流向不可用"],
        .zhTW: ["電力流向", "即時", "等待新讀數", "供給 Mac", "正在充電", "充電暫停", "電池供電", "充電器＋電池", "電力明細",
            "供給 Mac 的電力根據充電器輸入和電池流向計算。系統感測器單獨測量，讀數可能不同。", "讀數穩定中", "實測感測器", "螢幕背光", "左側 Thunderbolt", "右側 Thunderbolt", "App 活動根據 CPU 和 GPU 使用率，並非各 App 的實測瓦數。", "電力流向無法使用"],
        .zhHK: ["電力流向", "即時", "等待新讀數", "供給 Mac", "正在充電", "充電暫停", "電池供電", "充電器＋電池", "電力明細",
            "供給 Mac 的電力根據充電器輸入和電池流向計算。系統感測器單獨測量，讀數可能不同。", "讀數穩定中", "實測感測器", "螢幕背光", "左側 Thunderbolt", "右側 Thunderbolt", "App 活動根據 CPU 和 GPU 使用率，並非各 App 的實測瓦數。", "電力流向無法使用"],
    ]
}
