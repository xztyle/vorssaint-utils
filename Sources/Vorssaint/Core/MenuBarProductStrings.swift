// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

struct MenuBarProductStrings {
    let language: AppLanguage
    static func localized(_ language: AppLanguage) -> Self { Self(language: language) }
    private func string(_ key: String) -> String {
        let locales: [AppLanguage] = [.enUS, .ptBR, .tr, .ru, .es, .de, .fr, .it, .ja, .ko, .zhHans, .zhTW, .zhHK, .sk, .uk]
        return Self.values[key]![locales.firstIndex(of: language) ?? 0]
    }
    var search: String { string("search") }
    var profiles: String { string("profiles") }
    var name: String { string("name") }
    var save: String { string("save") }
    var apply: String { string("apply") }
    var rename: String { string("rename") }
    var delete: String { string("delete") }
    var rules: String { string("rules") }
    var addRule: String { string("addRule") }
    var edit: String { string("edit") }
    var enabled: String { string("enabled") }
    var condition: String { string("condition") }
    var action: String { string("action") }
    var value: String { string("value") }
    var endMinute: String { string("endMinute") }
    var duration: String { string("duration") }
    var priority: String { string("priority") }
    var item: String { string("item") }
    var profile: String { string("profile") }
    var noResults: String { string("noResults") }
    var keyboardHint: String { string("keyboardHint") }
    var corruptStore: String { string("corruptStore") }
    var restoreFailed: String { string("restoreFailed") }
    var cannotReach: String { string("cannotReach") }
    var automationPaused: String { string("automationPaused") }
    var restore: String { string("restore") }
    var diagnostics: String { string("diagnostics") }
    var rulesHint: String { string("rulesHint") }
    var shortcutReveal: String { FeatureStrings.menuBarOrganizer(language).contextShowHidden }
    var shortcutAlways: String { FeatureStrings.menuBarOrganizer(language).contextShowAlways }
    var shortcutPanel: String { FeatureStrings.menuBarOrganizer(language).secondaryBar }
    var shortcutSearch: String { search }
    var shortcutProfile: String { string("nextProfile") }
    func conditionName(_ value: MenuBarRuleCondition) -> String { string(value.rawValue) }
    func actionName(_ value: MenuBarRuleAction) -> String { string(value.rawValue) }

    private static let values: [String: [String]] = [
        "search": ["Search menu bar items", "Buscar itens da barra", "Menü öğelerini ara", "Поиск значков", "Buscar iconos del menú", "Menüleisteneinträge suchen", "Rechercher des icônes", "Cerca icone del menu", "メニューバー項目を検索", "메뉴 막대 항목 검색", "搜索菜单栏项目", "搜尋選單列項目", "搜尋選單列項目", "Hľadať ikony", "Пошук значків"],
        "profiles": ["Saved layouts", "Layouts salvos", "Kayıtlı düzenler", "Сохранённые макеты", "Diseños guardados", "Gespeicherte Anordnungen", "Dispositions enregistrées", "Disposizioni salvate", "保存した配置", "저장한 배치", "已保存布局", "已儲存配置", "已儲存配置", "Uložené rozloženia", "Збережені розташування"],
        "name": ["Name", "Nome", "Ad", "Имя", "Nombre", "Name", "Nom", "Nome", "名前", "이름", "名称", "名稱", "名稱", "Názov", "Назва"],
        "save": ["Save current layout", "Salvar layout atual", "Geçerli düzeni kaydet", "Сохранить текущий макет", "Guardar diseño actual", "Aktuelle Anordnung speichern", "Enregistrer la disposition", "Salva disposizione attuale", "現在の配置を保存", "현재 배치 저장", "保存当前布局", "儲存目前配置", "儲存目前配置", "Uložiť aktuálne rozloženie", "Зберегти поточне розташування"],
        "apply": ["Apply", "Aplicar", "Uygula", "Применить", "Aplicar", "Anwenden", "Appliquer", "Applica", "適用", "적용", "应用", "套用", "套用", "Použiť", "Застосувати"],
        "rename": ["Rename", "Renomear", "Yeniden adlandır", "Переименовать", "Renombrar", "Umbenennen", "Renommer", "Rinomina", "名前を変更", "이름 변경", "重命名", "重新命名", "重新命名", "Premenovať", "Перейменувати"],
        "delete": ["Delete", "Excluir", "Sil", "Удалить", "Eliminar", "Löschen", "Supprimer", "Elimina", "削除", "삭제", "删除", "刪除", "刪除", "Odstrániť", "Видалити"],
        "rules": ["Automatic reveal rules", "Regras de exibição automática", "Otomatik gösterme kuralları", "Правила показа", "Reglas de revelado automático", "Regeln zum automatischen Einblenden", "Règles d’affichage automatique", "Regole di visualizzazione", "自動表示ルール", "자동 표시 규칙", "自动显示规则", "自動顯示規則", "自動顯示規則", "Pravidlá automatického zobrazenia", "Правила автоматичного показу"],
        "addRule": ["Add rule", "Adicionar regra", "Kural ekle", "Добавить правило", "Añadir regla", "Regel hinzufügen", "Ajouter une règle", "Aggiungi regola", "ルールを追加", "규칙 추가", "添加规则", "新增規則", "新增規則", "Pridať pravidlo", "Додати правило"],
        "edit": ["Edit", "Editar", "Düzenle", "Изменить", "Editar", "Bearbeiten", "Modifier", "Modifica", "編集", "편집", "编辑", "編輯", "編輯", "Upraviť", "Змінити"],
        "enabled": ["Enabled", "Ativada", "Etkin", "Включено", "Activada", "Aktiviert", "Activée", "Attiva", "有効", "활성화", "启用", "啟用", "啟用", "Zapnuté", "Увімкнено"],
        "condition": ["When", "Quando", "Koşul", "Когда", "Cuando", "Wenn", "Quand", "Quando", "条件", "조건", "条件", "條件", "條件", "Podmienka", "Умова"],
        "action": ["Then", "Ação", "Eylem", "Действие", "Acción", "Dann", "Alors", "Azione", "動作", "동작", "操作", "動作", "動作", "Akcia", "Дія"],
        "value": ["Value", "Valor", "Değer", "Значение", "Valor", "Wert", "Valeur", "Valore", "値", "값", "值", "數值", "數值", "Hodnota", "Значення"],
        "endMinute": ["End minute (0–1439)", "Minuto final (0–1439)", "Bitiş dakikası (0–1439)", "Конечная минута (0–1439)", "Minuto final (0–1439)", "Endminute (0–1439)", "Minute de fin (0–1439)", "Minuto finale (0–1439)", "終了分 (0–1439)", "종료 분 (0–1439)", "结束分钟 (0–1439)", "結束分鐘 (0–1439)", "結束分鐘 (0–1439)", "Konečná minúta (0–1439)", "Кінцева хвилина (0–1439)"],
        "duration": ["Duration in seconds", "Duração em segundos", "Süre (saniye)", "Длительность в секундах", "Duración en segundos", "Dauer in Sekunden", "Durée en secondes", "Durata in secondi", "表示時間（秒）", "지속 시간(초)", "持续秒数", "持續秒數", "持續秒數", "Trvanie v sekundách", "Тривалість у секундах"],
        "priority": ["Priority", "Prioridade", "Öncelik", "Приоритет", "Prioridad", "Priorität", "Priorité", "Priorità", "優先順位", "우선순위", "优先级", "優先順序", "優先次序", "Priorita", "Пріоритет"],
        "item": ["Item", "Item", "Öğe", "Значок", "Icono", "Eintrag", "Élément", "Elemento", "項目", "항목", "项目", "項目", "項目", "Položka", "Значок"],
        "profile": ["Layout", "Layout", "Düzen", "Макет", "Diseño", "Anordnung", "Disposition", "Disposizione", "配置", "배치", "布局", "配置", "配置", "Rozloženie", "Розташування"],
        "noResults": ["No matching items", "Nenhum item encontrado", "Eşleşen öğe yok", "Ничего не найдено", "No hay resultados", "Keine passenden Einträge", "Aucun résultat", "Nessun risultato", "該当する項目なし", "일치하는 항목 없음", "没有匹配项目", "沒有符合的項目", "沒有符合的項目", "Žiadne výsledky", "Немає результатів"],
        "keyboardHint": ["↑ ↓ Select · Return Open · Esc Close", "↑ ↓ Selecionar · Enter Abrir · Esc Fechar", "↑ ↓ Seç · Enter Aç · Esc Kapat", "↑ ↓ Выбор · Enter Открыть · Esc Закрыть", "↑ ↓ Seleccionar · Intro Abrir · Esc Cerrar", "↑ ↓ Auswählen · Eingabe Öffnen · Esc Schließen", "↑ ↓ Choisir · Entrée Ouvrir · Échap Fermer", "↑ ↓ Seleziona · Invio Apri · Esc Chiudi", "↑ ↓ 選択 · Return 開く · Esc 閉じる", "↑ ↓ 선택 · Return 열기 · Esc 닫기", "↑ ↓ 选择 · 回车打开 · Esc 关闭", "↑ ↓ 選取 · Return 開啟 · Esc 關閉", "↑ ↓ 選取 · Return 開啟 · Esc 關閉", "↑ ↓ Vybrať · Enter Otvoriť · Esc Zavrieť", "↑ ↓ Вибір · Enter Відкрити · Esc Закрити"],
        "corruptStore": ["Saved menu bar data could not be read. It has been preserved.", "Não foi possível ler os dados salvos. Eles foram preservados.", "Kayıtlı veriler okunamadı. Veriler korundu.", "Не удалось прочитать данные. Они сохранены.", "No se pudieron leer los datos guardados. Se conservaron.", "Gespeicherte Daten konnten nicht gelesen werden. Sie wurden erhalten.", "Les données enregistrées sont illisibles. Elles sont conservées.", "Impossibile leggere i dati salvati. Sono stati conservati.", "保存データを読み取れません。データは保持されています。", "저장 데이터를 읽을 수 없습니다. 데이터는 보존됩니다.", "无法读取保存的数据。数据已保留。", "無法讀取儲存的資料。資料已保留。", "無法讀取儲存的資料。資料已保留。", "Uložené údaje sa nedajú čítať. Zostali zachované.", "Не вдалося прочитати збережені дані. Їх збережено."],
        "restoreFailed": ["Original order needs recovery. Re-enable with Accessibility access, then use Restore original layout.", "A ordem original precisa de recuperação. Reative com Acessibilidade e restaure o layout.", "İlk düzen kurtarılmalı. Erişilebilirlikle yeniden etkinleştirip ilk düzeni geri yükleyin.", "Нужно восстановить порядок. Включите доступ и восстановите исходный макет.", "El orden original necesita recuperación. Activa Accesibilidad y restaura el diseño original.", "Ursprüngliche Reihenfolge muss wiederhergestellt werden. Mit Bedienungshilfen aktivieren und wiederherstellen.", "L’ordre initial doit être restauré. Réactivez avec l’accessibilité puis restaurez-le.", "L’ordine originale richiede il ripristino. Riattiva con Accessibilità e ripristina.", "元の配置の復元が必要です。アクセシビリティを許可して再度有効にし、復元してください。", "원래 배치를 복구해야 합니다. 손쉬운 사용 권한으로 다시 활성화한 후 복구하세요.", "原始顺序需要恢复。授予辅助功能权限并重新启用，然后恢复原始布局。", "原始順序需要復原。授予輔助使用權限並重新啟用，再復原原始配置。", "原始次序需要還原。授予輔助使用權限並重新啟用，再還原原始配置。", "Pôvodné poradie potrebuje obnovu. Zapnite prístupnosť a obnovte pôvodné rozloženie.", "Потрібне відновлення початкового порядку. Увімкніть універсальний доступ і відновіть його."],
        "cannotReach": ["This item is not reachable on the current display.", "Este item não está acessível nesta tela.", "Bu öğeye geçerli ekranda ulaşılamıyor.", "Значок недоступен на этом экране.", "No se puede acceder a este icono en esta pantalla.", "Dieser Eintrag ist auf diesem Display nicht erreichbar.", "Cet élément est inaccessible sur cet écran.", "L’elemento non è raggiungibile su questo schermo.", "現在の画面ではこの項目を操作できません。", "현재 화면에서 이 항목에 접근할 수 없습니다.", "当前显示器无法访问此项目。", "目前顯示器無法存取此項目。", "目前顯示器無法存取此項目。", "Položka nie je dostupná na aktuálnom displeji.", "Значок недоступний на поточному екрані."],
        "automationPaused": ["Automatic moves stopped after repeated failures. Check the layout, then try again.", "Movimentos automáticos pararam após falhas. Verifique e tente novamente.", "Tekrarlanan hatalar sonrası otomatik taşıma durdu. Düzeni kontrol edip yeniden deneyin.", "Перемещения остановлены после ошибок. Проверьте макет и повторите.", "Se detuvieron los movimientos tras varios fallos. Revisa el diseño y reintenta.", "Automatische Verschiebungen wurden nach Fehlern gestoppt. Prüfen und erneut versuchen.", "Déplacements arrêtés après plusieurs échecs. Vérifiez puis réessayez.", "Spostamenti interrotti dopo ripetuti errori. Controlla e riprova.", "失敗が続いたため自動移動を停止しました。配置を確認して再試行してください。", "반복 실패로 자동 이동이 중지되었습니다. 배치를 확인하고 다시 시도하세요.", "多次失败后已停止自动移动。检查布局后重试。", "多次失敗後已停止自動移動。請檢查配置後重試。", "多次失敗後已停止自動移動。請檢查配置後重試。", "Automatické presuny sa po chybách zastavili. Skontrolujte rozloženie a skúste znova.", "Автоматичні переміщення зупинені після помилок. Перевірте розташування й повторіть."],
        "restore": ["Restore original layout", "Restaurar layout original", "İlk düzeni geri yükle", "Восстановить исходный макет", "Restaurar diseño original", "Ursprüngliche Anordnung wiederherstellen", "Restaurer la disposition initiale", "Ripristina disposizione originale", "元の配置を復元", "원래 배치 복구", "恢复原始布局", "復原原始配置", "還原原始配置", "Obnoviť pôvodné rozloženie", "Відновити початкове розташування"],
        "diagnostics": ["Copy diagnostics", "Copiar diagnóstico", "Tanılamayı kopyala", "Копировать диагностику", "Copiar diagnóstico", "Diagnose kopieren", "Copier le diagnostic", "Copia diagnosi", "診断をコピー", "진단 복사", "复制诊断", "複製診斷", "複製診斷", "Kopírovať diagnostiku", "Копіювати діагностику"],
        "nextProfile": ["Next saved layout", "Próximo layout salvo", "Sonraki kayıtlı düzen", "Следующий макет", "Siguiente diseño", "Nächste Anordnung", "Disposition suivante", "Disposizione successiva", "次の保存配置", "다음 저장 배치", "下一个布局", "下一個配置", "下一個配置", "Ďalšie uložené rozloženie", "Наступне розташування"],
        "rulesHint": ["Higher priority wins. Each rule runs once until its condition resets. Temporary changes restore your saved layout. Focus is not available as a reliable system signal.", "A maior prioridade vence. Cada regra executa uma vez até a condição reiniciar. Mudanças temporárias restauram o layout salvo. Foco não tem sinal confiável.", "Yüksek öncelik kazanır. Koşul sıfırlanana dek bir kez çalışır. Geçici değişiklikler kayıtlı düzeni geri yükler. Odak güvenilir değil.", "Выше приоритет — раньше запуск. Правило срабатывает один раз до сброса условия. Временные изменения восстанавливаются. Фокус недоступен.", "Gana la prioridad mayor. Cada regla se ejecuta una vez hasta que cambie la condición. Los cambios temporales restauran el diseño guardado. Enfoque no ofrece una señal fiable.", "Höhere Priorität gewinnt. Einmal pro Bedingungswechsel. Temporäre Änderungen stellen die Anordnung wieder her. Fokus bietet kein zuverlässiges Signal.", "La priorité supérieure gagne. Une exécution par changement de condition. Les changements temporaires sont restaurés. Concentration n’offre pas de signal fiable.", "Vince la priorità maggiore. Una volta per condizione. Le modifiche temporanee vengono ripristinate. Full immersion non offre un segnale affidabile.", "高い優先順位が優先されます。条件がリセットされるまで各ルールは一度だけ実行します。一時的な変更後は保存配置に戻ります。集中モードは未対応です。", "우선순위가 높은 규칙을 실행합니다. 조건이 초기화될 때까지 한 번만 실행합니다. 임시 변경 후 저장 배치를 복원합니다. 집중 모드는 지원하지 않습니다.", "优先级高的规则先执行。条件重置前仅执行一次。临时更改后恢复保存布局。专注模式没有可靠的系统信号。", "優先順序高的規則先執行。條件重設前僅執行一次。暫時變更後復原保存配置。專注模式沒有可靠的系統訊號。", "優先次序高的規則先執行。條件重設前僅執行一次。暫時變更後還原保存配置。專注模式沒有可靠的系統訊號。", "Vyššia priorita má prednosť. Pravidlo sa spustí raz do obnovenia podmienky. Dočasné zmeny obnovia uložené rozloženie. Sústredenie nemá spoľahlivý signál.", "Вищий пріоритет має перевагу. Правило працює раз до скидання умови. Тимчасові зміни відновлюють збережене розташування. Зосередження не має надійного сигналу."],
        "frontmostApp": ["Front app bundle identifier", "Identificador do app em foco", "Öndeki uygulama kimliği", "ID активного приложения", "Identificador de la app activa", "Kennung der aktiven App", "Identifiant de l’app active", "Identificatore app attiva", "最前面アプリの識別子", "전면 앱 식별자", "前台应用标识符", "前景應用程式識別碼", "前景應用程式識別碼", "Identifikátor aktívnej aplikácie", "Ідентифікатор активної програми"],
        "onBattery": ["On battery", "Na bateria", "Pil gücünde", "От батареи", "Con batería", "Batteriebetrieb", "Sur batterie", "A batteria", "バッテリー使用中", "배터리 사용 중", "使用电池", "使用電池", "使用電池", "Napájanie z batérie", "Від акумулятора"],
        "onPower": ["Connected to power", "Conectado à energia", "Güce bağlı", "От сети", "Conectado a corriente", "Am Netzteil", "Sur secteur", "Collegato alla corrente", "電源接続中", "전원 연결됨", "连接电源", "連接電源", "連接電源", "Pripojené k napájaniu", "Підключено до живлення"],
        "batteryBelow": ["Battery below percent", "Bateria abaixo de %", "Pil yüzdesi altında", "Батарея ниже %", "Batería por debajo de %", "Batterie unter Prozent", "Batterie sous le pourcentage", "Batteria sotto percentuale", "バッテリー残量が指定値未満", "배터리 잔량 미만(%)", "电池低于百分比", "電池低於百分比", "電池低於百分比", "Batéria pod percentom", "Акумулятор нижче відсотка"],
        "timeRange": ["Start minute (0–1439)", "Minuto inicial (0–1439)", "Başlangıç dakikası (0–1439)", "Начальная минута (0–1439)", "Minuto inicial (0–1439)", "Startminute (0–1439)", "Minute de début (0–1439)", "Minuto iniziale (0–1439)", "開始分 (0–1439)", "시작 분 (0–1439)", "开始分钟 (0–1439)", "開始分鐘 (0–1439)", "開始分鐘 (0–1439)", "Počiatočná minúta (0–1439)", "Початкова хвилина (0–1439)"],
        "displayCount": ["Number of displays", "Número de telas", "Ekran sayısı", "Число экранов", "Número de pantallas", "Anzahl Displays", "Nombre d’écrans", "Numero di schermi", "画面数", "화면 수", "显示器数量", "顯示器數量", "顯示器數量", "Počet displejov", "Кількість екранів"],
        "itemPresent": ["Item available", "Item disponível", "Öğe mevcut", "Значок доступен", "Icono disponible", "Eintrag verfügbar", "Élément disponible", "Elemento disponibile", "項目が利用可能", "항목 사용 가능", "项目可用", "項目可用", "項目可用", "Položka dostupná", "Значок доступний"],
        "revealHidden": ["Reveal hidden section", "Mostrar seção oculta", "Gizli bölümü göster", "Показать скрытый раздел", "Mostrar sección oculta", "Verborgenen Bereich einblenden", "Afficher les éléments masqués", "Mostra sezione nascosta", "非表示項目を表示", "숨긴 구역 표시", "显示隐藏部分", "顯示隱藏區域", "顯示隱藏區域", "Zobraziť skrytú sekciu", "Показати прихований розділ"],
        "revealItem": ["Reveal one item", "Mostrar um item", "Bir öğeyi göster", "Показать значок", "Mostrar un icono", "Eintrag einblenden", "Afficher un élément", "Mostra un elemento", "項目を一つ表示", "항목 하나 표시", "显示一个项目", "顯示一個項目", "顯示一個項目", "Zobraziť jednu položku", "Показати один значок"],
        "applyProfile": ["Apply saved layout", "Aplicar layout salvo", "Kayıtlı düzeni uygula", "Применить макет", "Aplicar diseño guardado", "Gespeicherte Anordnung anwenden", "Appliquer une disposition", "Applica disposizione salvata", "保存配置を適用", "저장 배치 적용", "应用保存布局", "套用保存配置", "套用保存配置", "Použiť uložené rozloženie", "Застосувати збережене розташування"],
    ]
}
