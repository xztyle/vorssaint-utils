// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ScreenshotPreviewStrings {
    let lifetime: String
    let keepOpen: String
    let caption: String
}

extension FeatureStrings {
    static func screenshotPreview(_ language: AppLanguage) -> ScreenshotPreviewStrings {
        switch language {
        case .enUS: .init(lifetime: "Keep previews for", keepOpen: "Until closed", caption: "The timer pauses during hover, editing, dragging and sharing. Done returns edits to the corner. Up to six previews stay open; older captures remain in History.")
        case .ptBR: .init(lifetime: "Manter prévias por", keepOpen: "Até fechar", caption: "O tempo pausa ao apontar, editar, arrastar e compartilhar. Concluído devolve as edições ao canto. Até seis prévias ficam abertas; capturas anteriores ficam no Histórico.")
        case .tr: .init(lifetime: "Önizleme süresi", keepOpen: "Kapatılana kadar", caption: "Üzerine gelme, düzenleme, sürükleme ve paylaşma sırasında süre durur. Bitti, düzenlemeleri köşeye döndürür. En fazla altı önizleme açık kalır; eskileri Geçmiş’te kalır.")
        case .ru: .init(lifetime: "Показывать миниатюры", keepOpen: "До закрытия", caption: "Таймер останавливается при наведении, правке, перетаскивании и отправке. «Готово» возвращает результат в угол. Открыты до шести миниатюр; старые снимки остаются в истории.")
        case .es: .init(lifetime: "Mantener vistas previas", keepOpen: "Hasta cerrarlas", caption: "El tiempo se pausa al pasar el puntero, editar, arrastrar y compartir. Listo devuelve los cambios a la esquina. Se muestran hasta seis vistas previas; las capturas anteriores quedan en el Historial.")
        case .sk: .init(lifetime: "Zobraziť náhľady na", keepOpen: "Do zatvorenia", caption: "Časovač sa pozastaví pri ukázaní, úpravách, ťahaní a zdieľaní. Hotovo vráti úpravy do rohu. Otvorených zostane najviac šesť náhľadov; staršie snímky sú v histórii.")
        case .de: .init(lifetime: "Vorschauen anzeigen für", keepOpen: "Bis zum Schließen", caption: "Bei Zeigerkontakt, Bearbeiten, Ziehen und Teilen pausiert die Zeit. Fertig bringt Änderungen zurück in die Ecke. Bis zu sechs Vorschauen bleiben offen; ältere Aufnahmen bleiben im Verlauf.")
        case .fr: .init(lifetime: "Garder les aperçus", keepOpen: "Jusqu’à fermeture", caption: "Le délai est suspendu au survol, pendant la modification, le glissement et le partage. Terminé renvoie le résultat dans le coin. Six aperçus au maximum restent ouverts ; les anciennes captures restent dans l’historique.")
        case .it: .init(lifetime: "Mantieni anteprime per", keepOpen: "Fino alla chiusura", caption: "Il timer si ferma al passaggio del puntatore, durante modifica, trascinamento e condivisione. Fine riporta le modifiche nell’angolo. Restano aperte fino a sei anteprime; le precedenti sono nella cronologia.")
        case .ja: .init(lifetime: "プレビューの表示時間", keepOpen: "閉じるまで", caption: "ポインタを重ねている間、編集、ドラッグ、共有中はタイマーが停止します。「完了」で編集結果が隅に戻ります。最大6件を表示し、古い画像は履歴に残ります。")
        case .ko: .init(lifetime: "미리보기 표시 시간", keepOpen: "닫을 때까지", caption: "포인터를 올리거나 편집, 드래그, 공유하는 동안 타이머가 멈춥니다. 완료를 누르면 편집 결과가 모서리로 돌아옵니다. 최대 6개가 열리며 이전 캡처는 기록에 남습니다.")
        case .uk: .init(lifetime: "Показувати мініатюри", keepOpen: "До закриття", caption: "Таймер зупиняється під час наведення, редагування, перетягування та поширення. «Готово» повертає результат у кут. Відкрито до шести мініатюр; старі знімки залишаються в історії.")
        case .zhHans: .init(lifetime: "预览保留时间", keepOpen: "直到关闭", caption: "悬停、编辑、拖动和分享时暂停计时。点按“完成”将编辑结果放回角落。最多保留六个预览，较早的截图仍在历史记录中。")
        case .zhTW: .init(lifetime: "預覽保留時間", keepOpen: "直到關閉", caption: "移入游標、編輯、拖移和分享時暫停計時。按下「完成」將編輯結果放回角落。最多保留六個預覽，較早的截圖仍在歷史記錄中。")
        case .zhHK: .init(lifetime: "預覽保留時間", keepOpen: "直到關閉", caption: "移入游標、編輯、拖移和分享時暫停計時。按下「完成」將編輯結果放回角落。最多保留六個預覽，較早的截圖仍在歷史記錄中。")
        }
    }
}
