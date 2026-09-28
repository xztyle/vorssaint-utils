// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors
import Foundation

enum ForkStrings {
    static func sourceUpdates(_ language: AppLanguage) -> String {
        switch language {
        case .enUS: "Aster is updated from its source repository. Automatic binary updates are disabled."
        case .ptBR: "O Aster é atualizado pelo repositório de código. As atualizações automáticas estão desativadas."
        case .tr: "Aster kaynak deposundan güncellenir. Otomatik uygulama güncellemeleri kapalıdır."
        case .ru: "Aster обновляется из репозитория исходного кода. Автоматические обновления приложения отключены."
        case .es: "Aster se actualiza desde su repositorio de código. Las actualizaciones automáticas están desactivadas."
        case .sk: "Aster sa aktualizuje zo zdrojového repozitára. Automatické aktualizácie aplikácie sú vypnuté."
        case .de: "Aster wird aus seinem Quellcode-Repository aktualisiert. Automatische App-Updates sind deaktiviert."
        case .fr: "Aster est mis à jour depuis son dépôt de code. Les mises à jour automatiques sont désactivées."
        case .it: "Aster viene aggiornato dal suo repository di codice. Gli aggiornamenti automatici sono disattivati."
        case .ja: "Asterはソースリポジトリから更新されます。アプリの自動更新は無効です。"
        case .ko: "Aster는 소스 저장소에서 업데이트됩니다. 자동 앱 업데이트는 비활성화되어 있습니다."
        case .uk: "Aster оновлюється з репозиторію вихідного коду. Автоматичні оновлення застосунку вимкнено."
        case .zhHans: "Aster 通过源代码仓库更新。应用自动更新已停用。"
        case .zhTW: "Aster 透過原始碼儲存庫更新。應用程式自動更新已停用。"
        case .zhHK: "Aster 透過原始碼儲存庫更新。應用程式自動更新已停用。"
        }
    }
}
