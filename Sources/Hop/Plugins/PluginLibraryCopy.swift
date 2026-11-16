import Foundation
import HopCore

enum PluginLibraryResources {
    static let contribute = URL(string: "https://github.com/antonyshakirov/hop/blob/feat/community-plugins-20261116/docs/plugins/authoring.md")!
}

enum PluginLibraryCopy {
    static func text(_ key: PluginText, _ language: AppLanguage) -> String? {
        let index: Int
        switch key {
        case .overview: index = 0
        case .repository: index = 1
        case .contribute: index = 2
        case .noMatches: index = 3
        default: return nil
        }
        let strings: [String]
        switch language {
        case .en: strings = ["Change the panel, colors and timer. New plugins start off.", "open repository", "write a plugin", "No matching plugins."]
        case .ru: strings = ["Плагины меняют панель, цвета и таймер. Новые плагины изначально выключены.", "открыть репозиторий", "написать плагин", "Подходящие плагины не найдены."]
        case .de: strings = ["Plugins ändern Panel, Farben und Timerverhalten. Neue Plugins bleiben aus, bis du sie aktivierst.", "Repository öffnen", "Plugin schreiben", "Keine passenden Plugins."]
        case .es: strings = ["Los plugins cambian el panel, los colores y el temporizador. Los nuevos permanecen desactivados hasta que los actives.", "abrir repositorio", "crear un plugin", "No se encontraron plugins."]
        case .pt: strings = ["Os plugins alteram o painel, as cores e o temporizador. Os novos ficam desativados até os ativares.", "abrir repositório", "criar um plugin", "Nenhum plugin encontrado."]
        case .fr: strings = ["Les plugins modifient le panneau, les couleurs et le minuteur. Les nouveaux restent désactivés tant que vous ne les activez pas.", "ouvrir le dépôt", "écrire un plugin", "Aucun plugin correspondant."]
        case .it: strings = ["I plugin cambiano pannello, colori e timer. I nuovi restano disattivati finché non li attivi.", "apri repository", "crea un plugin", "Nessun plugin trovato."]
        case .zh: strings = ["插件可更改面板、颜色和计时器行为。新插件会保持停用，直到你主动启用。", "打开代码仓库", "编写插件", "未找到匹配的插件。"]
        case .ja: strings = ["プラグインでパネル、色、タイマーの動作を変更できます。新しいプラグインは自分で有効にするまで無効です。", "リポジトリを開く", "プラグインを作る", "一致するプラグインはありません。"]
        case .nl: strings = ["Plugins wijzigen het paneel, de kleuren en de timer. Nieuwe plugins blijven uit totdat je ze inschakelt.", "repository openen", "plugin schrijven", "Geen overeenkomende plugins."]
        case .ko: strings = ["플러그인으로 패널, 색상, 타이머 동작을 바꿀 수 있습니다. 새 플러그인은 직접 켜기 전까지 꺼져 있습니다.", "저장소 열기", "플러그인 만들기", "일치하는 플러그인이 없습니다."]
        case .th: strings = ["ปลั๊กอินเปลี่ยนแผง สี และการทำงานของตัวจับเวลาได้ ปลั๊กอินใหม่จะปิดอยู่จนกว่าคุณจะเปิดใช้เอง", "เปิดที่เก็บโค้ด", "เขียนปลั๊กอิน", "ไม่พบปลั๊กอินที่ตรงกัน"]
        case .vi: strings = ["Phần mở rộng thay đổi bảng, màu sắc và bộ hẹn giờ. Phần mở rộng mới luôn tắt cho đến khi bạn bật.", "mở kho mã", "viết phần mở rộng", "Không tìm thấy phần mở rộng."]
        case .hi: strings = ["प्लगइन से पैनल, रंग और टाइमर का व्यवहार बदलें। नए प्लगइन आपके चालू करने तक बंद रहते हैं।", "रिपॉज़िटरी खोलें", "प्लगइन लिखें", "कोई मेल खाता प्लगइन नहीं मिला।"]
        case .id: strings = ["Plugin mengubah panel, warna, dan perilaku timer. Plugin baru tetap nonaktif sampai kamu mengaktifkannya.", "buka repositori", "tulis plugin", "Tidak ada plugin yang cocok."]
        case .tr: strings = ["Eklentiler paneli, renkleri ve zamanlayıcıyı değiştirir. Yeni eklentiler siz açana kadar kapalı kalır.", "depoyu aç", "eklenti yaz", "Eşleşen eklenti yok."]
        case .pl: strings = ["Wtyczki zmieniają panel, kolory i działanie minutnika. Nowe pozostają wyłączone, dopóki ich nie włączysz.", "otwórz repozytorium", "napisz wtyczkę", "Brak pasujących wtyczek."]
        case .sr: strings = ["Додаци мењају панел, боје и рад тајмера. Нови остају искључени док их сам не укључиш.", "отвори репозиторијум", "напиши додатак", "Нема одговарајућих додатака."]
        case .ar: strings = ["تغيّر الإضافات اللوحة والألوان وسلوك المؤقّت. تبقى الإضافات الجديدة معطّلة حتى تفعّلها بنفسك.", "افتح المستودع", "اكتب إضافة", "لا توجد إضافات مطابقة."]
        case .he: strings = ["תוספים משנים את הלוח, הצבעים והתנהגות הטיימר. תוספים חדשים נשארים כבויים עד להפעלתם.", "פתח מאגר", "כתוב תוסף", "לא נמצאו תוספים מתאימים."]
        case .fa: strings = ["افزونه‌ها پنل، رنگ‌ها و رفتار تایمر را تغییر می‌دهند. افزونه‌های جدید تا زمانی که خودتان فعالشان نکنید خاموش می‌مانند.", "باز کردن مخزن", "نوشتن افزونه", "افزونه‌ای پیدا نشد."]
        case .ur: strings = ["پلگ ان سے پینل، رنگ اور ٹائمر کا رویہ بدلیں۔ نئے پلگ ان آپ کے فعال کرنے تک بند رہتے ہیں۔", "ریپوزٹری کھولیں", "پلگ ان لکھیں", "کوئی مماثل پلگ ان نہیں ملا۔"]
        }
        return L10n.gluedPluginText(strings[index], language)
    }
}
