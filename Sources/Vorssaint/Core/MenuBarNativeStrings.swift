// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

struct MenuBarNativeStrings {
    let title: String
    let accessInfo: String
    let grant: String
    let ready: String
    let failed: String
    let enableCaption: String

    static func localized(_ language: AppLanguage) -> Self {
        let row = rows[language]!.components(separatedBy: "|")
        return .init(title: row[0], accessInfo: row[1], grant: row[2], ready: row[3], failed: row[4], enableCaption: row[5])
    }

    private static let rows: [AppLanguage: String] = [
        .enUS: "Menu bar access|macOS 27 stores icon positions in a protected file. Select com.apple.MenuBar.plist to let Aster save your icon order. Access is limited to this one file.|Grant Access|Access granted|Select the menu layout file shown in the picker, then try again.|Organize and hide app icons with native menu bar controls. macOS system icons stay visible.",
        .es: "Acceso a la barra de menús|macOS 27 guarda las posiciones en un archivo protegido. Selecciona com.apple.MenuBar.plist para que Aster guarde el orden. El acceso se limita a este archivo.|Permitir acceso|Acceso permitido|Selecciona el archivo de distribución que muestra el selector y vuelve a intentarlo.|Organiza y oculta los iconos de las apps con controles nativos. Los iconos del sistema permanecen visibles.",
        .ptBR: "Acesso à barra de menus|O macOS 27 guarda as posições num arquivo protegido. Selecione com.apple.MenuBar.plist para o Aster salvar a ordem. O acesso limita-se a esse arquivo.|Permitir acesso|Acesso permitido|Selecione o arquivo de layout mostrado e tente novamente.|Organize e oculte os ícones dos apps com controles nativos. Os ícones do sistema continuam visíveis.",
        .tr: "Menü çubuğu erişimi|macOS 27 konumları korumalı bir dosyada saklar. Aster’ın sıralamayı kaydetmesi için com.apple.MenuBar.plist dosyasını seçin. Erişim yalnız bu dosyayla sınırlıdır.|Erişim ver|Erişim verildi|Seçicide gösterilen düzen dosyasını seçip yeniden deneyin.|Uygulama simgelerini yerel menü çubuğu denetimleriyle düzenleyin ve gizleyin. Sistem simgeleri görünür kalır.",
        .ru: "Доступ к строке меню|macOS 27 хранит позиции в защищённом файле. Выберите com.apple.MenuBar.plist, чтобы Aster сохранял порядок. Доступ ограничен одним файлом.|Разрешить доступ|Доступ разрешён|Выберите показанный файл расположения и повторите попытку.|Упорядочивайте и скрывайте значки приложений. Системные значки macOS остаются видимыми.",
        .sk: "Prístup k lište menu|macOS 27 ukladá polohy v chránenom súbore. Vyberte com.apple.MenuBar.plist, aby Aster ukladal poradie. Prístup je obmedzený na tento súbor.|Povoliť prístup|Prístup povolený|Vyberte zobrazený súbor rozloženia a skúste to znova.|Usporiadajte a skryte ikony aplikácií natívnymi ovládacími prvkami. Systémové ikony zostávajú viditeľné.",
        .de: "Menüleistenzugriff|macOS 27 speichert Positionen in einer geschützten Datei. Wähle com.apple.MenuBar.plist, damit Aster die Reihenfolge speichern kann. Zugriff gilt nur für diese Datei.|Zugriff erlauben|Zugriff erlaubt|Wähle die angezeigte Layoutdatei und versuche es erneut.|Ordne und verstecke App-Symbole mit nativen Menüleistenfunktionen. Systemsymbole bleiben sichtbar.",
        .fr: "Accès à la barre de menus|macOS 27 conserve les positions dans un fichier protégé. Sélectionnez com.apple.MenuBar.plist pour qu’Aster enregistre l’ordre. L’accès est limité à ce fichier.|Autoriser l’accès|Accès autorisé|Sélectionnez le fichier de disposition affiché, puis réessayez.|Organisez et masquez les icônes des apps avec les commandes natives. Les icônes du système restent visibles.",
        .it: "Accesso alla barra dei menu|macOS 27 conserva le posizioni in un file protetto. Seleziona com.apple.MenuBar.plist per consentire ad Aster di salvare l’ordine. L’accesso è limitato a questo file.|Consenti accesso|Accesso consentito|Seleziona il file di disposizione indicato e riprova.|Organizza e nascondi le icone delle app con i controlli nativi. Le icone del sistema restano visibili.",
        .ja: "メニューバーへのアクセス|macOS 27は位置を保護されたファイルに保存します。Asterが順序を保存できるようにcom.apple.MenuBar.plistを選択してください。アクセスはこのファイルだけに限定されます。|アクセスを許可|アクセス許可済み|表示された配置ファイルを選択して再試行してください。|ネイティブのメニューバー操作でアプリのアイコンを整理・非表示にします。システムアイコンは表示したままです。",
        .ko: "메뉴 막대 접근|macOS 27은 위치를 보호된 파일에 저장합니다. Aster가 순서를 저장하도록 com.apple.MenuBar.plist를 선택하세요. 접근은 이 파일로 제한됩니다.|접근 허용|접근 허용됨|표시된 배치 파일을 선택한 후 다시 시도하세요.|기본 메뉴 막대 기능으로 앱 아이콘을 정리하고 숨깁니다. 시스템 아이콘은 계속 표시됩니다.",
        .uk: "Доступ до рядка меню|macOS 27 зберігає позиції в захищеному файлі. Виберіть com.apple.MenuBar.plist, щоб Aster зберігав порядок. Доступ обмежено одним файлом.|Дозволити доступ|Доступ дозволено|Виберіть показаний файл розташування та спробуйте знову.|Упорядковуйте та приховуйте значки програм. Системні значки macOS залишаються видимими.",
        .zhHans: "菜单栏访问|macOS 27将位置保存在受保护的文件中。请选择com.apple.MenuBar.plist，让Aster保存图标顺序。访问仅限此文件。|允许访问|已允许访问|请选择文件选择器中显示的布局文件，然后重试。|使用原生菜单栏控件整理和隐藏应用图标。macOS系统图标保持可见。",
        .zhTW: "選單列存取|macOS 27將位置儲存在受保護的檔案中。請選擇com.apple.MenuBar.plist，讓Aster儲存圖示順序。存取僅限此檔案。|允許存取|已允許存取|請選擇檔案選擇器中顯示的配置檔案，再重試。|使用原生選單列控制項整理和隱藏App圖示。macOS系統圖示保持可見。",
        .zhHK: "選單列存取|macOS 27將位置儲存在受保護的檔案中。請選擇com.apple.MenuBar.plist，讓Aster儲存圖示順序。存取僅限此檔案。|允許存取|已允許存取|請選擇檔案選擇器中顯示的配置檔案，再重試。|使用原生選單列控制項整理和隱藏App圖示。macOS系統圖示保持可見。"
    ]
}
