<div align="center">

<img src="../../assets/icon/hop-icon-app.svg" width="96" alt="Biểu tượng ứng dụng Hop — dấu hoa thị bốn nét">

# Hop

**Một trợ thủ nhỏ gọn trên thanh menu của macOS: hẹn giờ, theo dõi thời
gian, việc cần làm, chống ngủ, giám sát hệ thống, lịch sử clipboard, chuyển
đổi tệp, quản lý cửa sổ và trình torrent gọn nhẹ — trải trên tối đa bốn tab
ở biểu tượng. Một cú nhấp — mọi thứ bạn cần đều ở ngay đó.**

[![Latest release](https://img.shields.io/github/v/release/antonyshakirov/hop)](https://github.com/antonyshakirov/hop/releases/latest)
[![Installs](https://img.shields.io/endpoint?url=https%3A%2F%2Fwww.antonshakirov.com%2Fapi%2Fhop%2Finstalls&color=ffd60a)](https://www.antonshakirov.com/api/hop/installs)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-black)
[![Stars](https://img.shields.io/github/stars/antonyshakirov/hop?style=social)](https://github.com/antonyshakirov/hop/stargazers)

[![CI](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml)
[![CodeQL](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml)

[Bahasa Indonesia](README.id.md) · [Deutsch](README.de.md) · [English](../../README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Italiano](README.it.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · **Tiếng Việt** · [Türkçe](README.tr.md) · [Русский](README.ru.md) · [Українська](README.uk.md) · [עברית](README.he.md) · [اردو](README.ur.md) · [العربية](README.ar.md) · [فارسی](README.fa.md) · [हिन्दी](README.hi.md) · [ไทย](README.th.md) · [한국어](README.ko.md) · [中文](README.zh.md) · [日本語](README.ja.md)

<img src="https://www.antonshakirov.com/products/hop/screens/en/overview.png" width="360" alt="Bảng điều khiển Hop — đồng hồ hẹn giờ trên thanh menu với màn hình ma trận điểm, các mức cài sẵn và chu kỳ làm việc-nghỉ ngơi">

</div>

Hop nằm trên thanh menu của máy Mac và thay thế cả một nắm tiện ích nhỏ:
đồng hồ hẹn giờ kiểu Pomodoro, trình theo dõi thời gian kèm danh sách việc
cần làm, trình chặn ngủ kiểu caffeinate, trình giám sát hệ thống, trình
quản lý clipboard, trình chuyển đổi tệp kéo-thả, công cụ sắp xếp cửa sổ và
trình torrent gọn nhẹ — một ứng dụng native nhẹ nhàng, với các mô-đun bạn
dùng được trải trên tối đa bốn tab ở biểu tượng.

## Tải về

- **[Hop.dmg](https://github.com/antonyshakirov/hop/releases/latest/download/Hop.dmg)** — mở ra rồi kéo `Hop.app` vào Applications (khuyên dùng)
- Homebrew: `brew install --cask antonyshakirov/tap/hop`
- `Hop-x.y.z.zip` — vẫn là ứng dụng đó dưới dạng tệp nén thông thường (dùng cho trình cập nhật tích hợp); xem [bản phát hành mới nhất](https://github.com/antonyshakirov/hop/releases/latest)
- Mirror tốc độ cao: [hop-dl.b-cdn.net/products/hop/Hop.dmg](https://hop-dl.b-cdn.net/products/hop/Hop.dmg)

Lần khởi chạy đầu tiên trên macOS 15 trở lên: hãy thử mở Hop một lần, sau
đó vào **Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Vẫn mở** và xác nhận
**Mở**. Hop không được notarize vì tác giả không có quyền sử dụng tư cách
thành viên Apple Developer Program. Mã nguồn được công khai và các bản cập
nhật tích hợp được xác minh bằng Ed25519. Yêu cầu macOS 14 trở lên.

## Tính năng

### Không gian

Biểu tượng chứa được tối đa bốn tab, và bạn kéo từng mô-đun vào tab bạn
muốn: hẹn giờ ở một tab, giám sát ở tab khác, thứ ít mở thì để sang bên. Kệ
«không hoạt động» giữ lại những gì bạn gác qua một bên mà không xóa đi.

### Hẹn giờ & chu kỳ

Đồng hồ đếm ngược ma trận điểm mà bạn đặt chỉ bằng một thao tác: kéo các
con số, gõ thời gian như trên lò vi sóng, hoặc chọn một mức cài sẵn. Chu kỳ
làm việc-nghỉ ngơi (Pomodoro 25/5, 52/17, 90/15 — hoặc tự đặt), đồng hồ bấm
giờ, ngăn cất giữ giúp đồng hồ đang chạy không bị mất khi bạn thử một đồng
hồ khác, và thông báo kết thúc còn có thể tạm dừng nhạc hay video của bạn.
Khi đếm ngược kết thúc, một tiếng chuông vang lên và các con số nhấp nháy
cho đến khi bạn đặt lại.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/timer.png" width="420" alt="Hop — Hẹn giờ & chu kỳ">
</div>

### Theo dõi thời gian & việc cần làm

Ghi lại thời gian trên một danh sách công việc phẳng: mỗi hàng hiển thị thời
gian hôm nay và tổng tích lũy, và bạn có thể sửa con số hôm nay bằng tay.
Nếu một việc chạy quá lâu, sau tám giờ sẽ có một dải nhắc bạn. Bên cạnh là
một danh sách việc cần làm riêng, nơi việc đã xong chìm xuống dưới.

Nhấn vào một công việc và dòng đó mở ra: toàn bộ nội dung ở dòng đầu, mô tả bên
dưới, một ngôi sao cho mục yêu thích. Một việc cần làm còn có thể mang lời nhắc —
ngày, giờ và những thứ trong tuần bạn muốn lặp lại — và Hop sẽ báo khi đến giờ:
biểu ngữ có «hoãn» và «xong», âm thanh, dấu trên thanh menu; mỗi thứ bật riêng.

**Trợ lý AI của bạn cũng có thể thêm công việc.** Danh sách là một tệp JSON bình
thường, và Hop đọc thay đổi ngay khi đang chạy. Hop cũng thực thi lệnh từ một tệp
và hiểu liên kết `hop://`: chính trợ lý đó, hoặc một Phím tắt dựng quanh liên kết
ấy, có thể bắt đầu hẹn giờ, thêm việc kèm lời nhắc, hoặc đọc xem cái gì đang
chạy. Xem [docs/automation.md](../automation.md).

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/tracker.png" width="420" alt="Hop — Theo dõi thời gian & việc cần làm">
</div>

### Chống ngủ

Giữ máy Mac luôn thức trong 15 phút, 8 giờ hoặc mãi mãi — một cú nhấp,
không cần mật khẩu. Tùy chọn giữ màn hình luôn sáng, hoặc tiếp tục làm việc
khi gập nắp máy (tiện cho việc tải xuống, các bản build dài và màn hình
ngoài).

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/awake.png" width="420" alt="Hop — Chống ngủ">
</div>

### Giám sát hệ thống

Tải và nhiệt độ CPU và GPU, bộ nhớ và swap, mạng, ổ đĩa, tình trạng pin và mức
tiêu thụ điện — số liệu trực tiếp kèm biểu đồ sparkline, ngưỡng màu do chính
bạn đặt, °C/°F và dòng hiển thị uptime. Số liệu lấy thẳng từ macOS và chỉ cập
nhật khi tab đang mở. Hàng bộ nhớ cũng cảnh báo khi nhiều bộ nhớ đã bị đẩy
xuống đĩa, chứ không chỉ khi macOS tự báo đang chật vật.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/system.png" width="420" alt="Hop — Giám sát hệ thống">
</div>

### Lịch sử clipboard

100 mục bạn sao chép gần nhất (tối đa 300) — văn bản, hình ảnh và tệp — một
cú nhấp để sao chép lại hoặc dán thẳng vào ứng dụng trước đó. Các tệp đã sao
chép được nhớ theo tên (nhiều tệp cùng lúc hiện là «tên +N»), và khi dán thì
chính tệp đó quay lại. Mật khẩu và các nội dung nhập ẩn khác không bao giờ
được lưu.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/clipboard.png" width="420" alt="Hop — Lịch sử clipboard">
</div>

### Chuyển đổi tệp

Thả cả loạt ảnh, PDF, video hoặc âm thanh vào bảng điều khiển: xuất ra
JPEG, PNG, HEIC, AVIF và WebP; nén PDF; thu nhỏ video bằng HEVC với ước
tính dung lượng trung thực, hiển thị trực tiếp trước khi chuyển đổi. Mọi
thứ đều được xử lý cục bộ.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/converter.png" width="480" alt="Hop — Chuyển đổi tệp">
</div>

### Quản lý cửa sổ

Sắp cửa sổ vào nửa màn hình, một phần tư, một phần ba và chính giữa bằng
một cú nhấp vào biểu tượng vùng hoặc phím tắt ⌃⌥ — không cần thêm ứng dụng
nào khác.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/windows.png" width="420" alt="Hop — Quản lý cửa sổ">
</div>

### Torrent

Một trình BitTorrent gọn nhẹ ngay trong cùng bảng điều khiển: thả tệp
.torrent hoặc dán liên kết magnet, chọn chính xác những tệp muốn tải —
trước hoặc thậm chí ngay trong lúc tải — tạm dừng, tiếp tục và seed, kèm
tùy chọn tự dừng khi đạt ratio 1.0. Mô-đun này mặc định tắt; khi bật, ứng
dụng sẽ tải engine mã nguồn mở dưới dạng gói nhỏ riêng (~26 MB, có xác
minh chữ ký) và engine chỉ giao tiếp với Hop qua một cổng cục bộ. Hop
cũng có thể trở thành ứng dụng mặc định cho tệp .torrent và liên kết
magnet.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/torrents.png" width="420" alt="Torrent trong Hop — trình BitTorrent gọn nhẹ trong bảng điều khiển trên thanh menu">
</div>

### Kho nén tệp

Dòng của mô-đun mở một cửa sổ, và bạn thả tệp vào chính cửa sổ đó — ⌘V cũng
được, nhiều tệp một lúc. Những gì bạn thêm vào chờ trong một danh sách cho tới
khi bạn bấm nút: tệp nén được bung, phần còn lại gộp vào một tệp nén. Kết quả
mặc định nằm trên màn hình nền, hoặc cạnh tệp gốc, hoặc trong thư mục bạn chọn.
Hỗ trợ zip, rar, 7z, tar, tar.gz, tar.bz2, tar.xz và gz; với rar và 7z, lần đầu
gặp sẽ tải một trợ thủ nhỏ (~6 MB) có kiểm tra chữ ký. Hop bung được rar nhưng
không bao giờ tạo — đó là định dạng độc quyền. «Hop làm mặc định cho kho nén» trong cài đặt chỉ đề xuất rar
khi không có ứng dụng Apple xử lý, và có thể giành lại rar từ ứng dụng bên thứ ba; zip, 7z
và các định dạng gốc vẫn thuộc Archive Utility. Nó chạy cả khi mô-đun bị ẩn, và thẻ hiện trạng thái thật. Nhấp đúp vào một tệp nén trong Finder sẽ giải nén ngay cạnh tệp đó, trong một cửa sổ tiến trình nhỏ riêng, và khi thất bại cũng không để lại thứ gì ẩn phía sau. Những tệp Hop mở đều mang biểu tượng riêng có ghi định dạng, nên cả thư mục đọc được chỉ trong một cái liếc.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/archives.png" width="480" alt="Hop — Kho nén tệp">
</div>

### Tài liệu

Bộ chuyển đổi đã biết làm tài liệu: markdown → PDF do chính Hop dàn trang, tệp
Word (.docx, .doc, .rtf) → PDF hoặc markdown, và trích văn bản của PDF ra
markdown — trang quét được đọc bằng Vision của Apple. Tất cả đều chạy trong máy
và ngoại tuyến, không kèm bộ ứng dụng văn phòng, không phải tải gì thêm.

### Ống hút màu

Lấy màu bất kỳ trên màn hình bằng kính lúp hệ thống: màu ở lại trong danh sách,
mỗi hàng mang hex, rgb và hsl ở cột riêng — bấm cái nào thì chép cách ghi ấy.
Thứ tự không đổi dưới con trỏ, giữ bao nhiêu màu và hiện bao nhiêu hàng là tuỳ
chọn, và không cần quyền ghi màn hình: kính lúp chỉ trả về một màu.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/colors.png" width="420" alt="Hop — Ống hút màu">
</div>

### Nhận dạng văn bản

Khoanh một vùng màn hình, hoặc thả ảnh vào cửa sổ và dán bằng ⌘V: chữ và mã QR
bên trong hiện ra trong một cửa sổ để đọc, sửa và sao chép, đồng thời vào lịch
sử clipboard. Ngắt dòng được giữ nên bảng vẫn đọc được. Nhận dạng bằng Vision
của Apple, hoàn toàn trên chiếc Mac này.

Nếu kết quả có địa chỉ web, nút «mở liên kết» sẽ xuất hiện: liên kết trong mã
QR trên hoá đơn mở thẳng trong trình duyệt, không cần đến điện thoại. Chỉ địa
chỉ web: mã quét được là dữ liệu từ bên ngoài, nên số điện thoại, mật khẩu
Wi-Fi hay danh thiếp vẫn là văn bản thường.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/recognition.png" width="480" alt="Hop — Nhận dạng văn bản">
</div>

### Khoá bàn phím

Bấm 1, 5 hoặc 15 phút — hoặc ∞ — và cả bàn phím ngừng phản hồi, để lau mà không
phải tắt máy hay gập nắp. Một tấm che toàn màn hình giải thích chuyện gì đang
xảy ra, còn biểu tượng trên thanh menu biến thành bàn phím. Có bốn lối ra: nút
trên tấm che, nút trong bảng, mở bảng, hoặc giữ esc + shift năm giây. Nhấn nhanh phím
nguồn cũng bị nuốt; giữ lâu thì Mac vẫn tắt cưỡng bức, vì đó là việc của phần
cứng.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/keyboard.png" width="480" alt="Hop — Khoá bàn phím">
</div>

### Kiểm tra tốc độ

Một chạm là đo đường truyền bằng chính networkQuality của macOS, đối với máy chủ của Apple — tải xuống, tải lên và độ phản hồi, kết quả cuối cùng ở lại trong hàng.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/speed.png" width="420" alt="Hop — Kiểm tra tốc độ">
</div>

### Biểu tượng trên thanh trình đơn

Biểu tượng mang những dấu nhỏ: thời gian đang chạy, chống ngủ, một lời nhắc vừa reo,
chấm khi vpn đang bật (chuyển cam nếu không còn gì đi qua) và mũi tên khi torrent đang
chạy — màu hay đơn sắc, tắt được từng cái. Cửa sổ của chính Hop hiện trong Dock khi
còn mở, nên một cú nhấp đưa cửa sổ trở lại thay vì mở bảng điều khiển, và biểu tượng
rời đi cùng cửa sổ cuối cùng.

### Chủ đề, phím tắt và chế độ an toàn

Chủ đề tối và sáng với kết cấu hạt phim, phím tắt toàn cục, khởi động khi đăng nhập, và một chế độ an toàn kéo ứng dụng ra khỏi vòng lặp treo — tất cả trong một cửa sổ cài đặt.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/settings.png" width="480" alt="Hop — Cài đặt">
</div>

### VPN

Mọi VPN mà máy Mac của bạn biết, mỗi cái một công tắc, của hãng nào cũng vậy. Hop
đọc danh sách thẳng từ cài đặt hệ thống: ứng dụng cài hôm qua tự xuất hiện, cái đã
gỡ thì biến mất. Ở đây không phải thêm hay cấu hình gì cả.

Bật tắt đường hầm mà không phải mở thứ gì. Khi một đường hầm đang chạy, một chấm nhỏ
sáng ở góc biểu tượng trên thanh menu, cạnh các đèn báo khác: xanh khi còn có gì đi
qua, cam khi đường hầm đang bật nhưng không có gì quay lại. Một kết nối chết lặng lẽ
không còn trông như đang chạy, và bảng cho biết đó là dòng nào. Bấm vào tên thì cửa sổ
của chính VPN đó mở ra; đóng cửa sổ, Hop tắt luôn ứng dụng. Kết nối vẫn còn: đường hầm
do hệ thống giữ, không phải ứng dụng.

Dòng hiển thị đúng những gì ứng dụng tự khai báo: tên của nó, và trong ngoặc là
phần cấu hình thêm vào, thường là quốc gia. Hop không đoán quốc gia từ địa chỉ máy
chủ: sổ đăng ký địa chỉ cho biết dải số đăng ký ở đâu, chứ không phải máy đặt ở
đâu.

Chấm này có thể tắt trong cài đặt; mô-đun và các công tắc vẫn hoạt động như thường.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/vpn.png" width="420" alt="Hop — Công tắc VPN">
</div>

### Ứng dụng

Một lưới các chương trình bạn mở suốt ngày, chỉ một cú nhấp mà không phải vào
thư mục Applications. Bấm + rồi chọn, hoặc kéo từ Finder vào; mỗi hàng chín cái, tối đa tám hàng.

Kéo một biểu tượng để đổi chỗ: vạch vàng cho biết nó sẽ nằm giữa hai biểu tượng
nào và các biểu tượng khác tự nhường chỗ như trên màn hình chính. Nút sửa bật
chế độ đung đưa, mỗi biểu tượng có dấu ✕ và lưới có thể đặt tên riêng; ở đó cũng
tắt được tên dưới biểu tượng, nếu bạn nhận ra ứng dụng chỉ bằng hình. Bạn muốn
bao nhiêu lưới cũng được — công việc ở một không gian, phần còn lại ở không gian
khác — mỗi lưới có ứng dụng riêng.

Lưới được tạo và xoá ngay nơi bạn sắp xếp các mô-đun: trong cài đặt, hoặc trong
chính bảng mô-đun, nơi dấu ✕ trên thẻ của một lưới xoá hẳn nó. Lưới mới bắt đầu
trống và nói rõ như vậy cho tới khi bạn lấp đầy.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/apps.png" width="420" alt="Hop — Lưới ứng dụng">
</div>

### Gỡ ứng dụng

Thả một ứng dụng vào hàng này, hoặc chọn từ danh sách mọi thứ đã cài, nó sẽ đi cùng những gì để lại ở khoảng ba chục nơi: application support, bộ đệm, tuỳ chọn, container, launch agents, phần mở rộng, biên nhận cài đặt và phần còn lại. Mỗi ứng dụng trong danh sách ghi rõ nó nặng bao nhiêu, phần ứng dụng và phần dữ liệu tách riêng. Ứng dụng đã nằm trong thùng rác vẫn được nhận ra: định danh đọc từ gói trong thùng rác, hoặc suy ra từ những phần sót có tên nó.

Không gì bị xoá thẳng. Mọi thứ chuyển vào thùng rác, nên một sai sót chỉ tốn một lần khôi phục chứ không mất tệp; và thứ macOS không giao ra được gọi tên kèm lý do, không lặng lẽ bỏ qua.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/uninstall.png" width="480" alt="Hop — Gỡ ứng dụng cùng mọi thứ nó để lại">
</div>

Cũng mô-đun ấy dọn dẹp mà không gỡ gì: mọi ứng dụng đang giữ bộ đệm, lớn trước; bộ cài còn trong Tải xuống, trên Màn hình nền và trong Tài liệu; dữ liệu của ứng dụng đã gỡ từ lâu; và thùng rác với dung lượng của nó. Một dấu tích lấy trọn một mục. Thứ nó cố ý không đụng cũng được liệt kê — container nơi bộ đệm và dữ liệu chung một thư mục, chẳng hạn hai mươi gigabyte của một ứng dụng nhắn tin: chỉ ứng dụng ấy mới biết nửa nào bỏ được.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/clean.png" width="480" alt="Hop — Dọn bộ đệm, bộ cài, phần sót và thùng rác">
</div>

## 22 ngôn ngữ

Bahasa Indonesia, Deutsch, English, Español, Français, Italiano, Nederlands, Polski, Português, Tiếng Việt, Türkçe, Русский, Українська, עברית, اردو, العربية, فارسی, हिन्दी, ไทย, 한국어, 中文, 日本語 — ứng dụng tự động theo ngôn ngữ hệ thống của
bạn ngay từ đầu.

## Ủng hộ dự án

Hop miễn phí và sẽ luôn như vậy. Nếu nó xứng một chỗ trên thanh menu của bạn, một
khoản ủng hộ tự nguyện giúp ra tính năng mới và trau chuốt những gì đang có — nó
mua thời gian, không gì khác.

**[→ Ủng hộ Hop](https://web.tribute.tg/d/Nvk)**

## Quyền riêng tư — và vì sao cấp quyền là an toàn

**Hop không thu thập bất cứ thứ gì. Bây giờ không, sau này cũng không.** Không
máy chủ riêng, không phân tích, không đo lường từ xa, không tài khoản, không báo
cáo sự cố. Mọi quyền bên dưới chỉ được macOS hỏi khi bạn thực sự dùng tính năng
cần nó, và nó tồn tại đúng để tính năng đó chạy — không có gì bị thu thập dọc
đường. Bạn không cần tin lời: ứng dụng là mã nguồn mở, và đoạn mã để thu thập
đơn giản là không tồn tại. Hãy thử tìm một SDK theo dõi hay một lệnh gọi phân
tích trong kho này — bạn sẽ không thấy.

Mọi thứ chạy cục bộ: không máy chủ, không thu thập dữ liệu, không tài
khoản. Ứng dụng chỉ dùng mạng để kiểm tra bản cập nhật, khi bạn chạy bài
kiểm tra tốc độ tích hợp, và — nếu bạn bật mô-đun torrent — để tải engine
một lần duy nhất và truyền chính lưu lượng torrent. Việc kiểm tra cập nhật
gửi đi phiên bản bạn đang dùng, và không có gì nhận dạng bạn hay chiếc Mac
của bạn. Các bản cập nhật và engine torrent được phân phối dưới dạng tệp nén
có chữ ký và được xác minh bằng chữ ký Ed25519 trước khi cài đặt.

## Quyền

Hop chỉ xin quyền khi bạn thật sự dùng tính năng cần đến nó, và cửa sổ thông tin
của ứng dụng liệt kê tất cả kèm trạng thái hiện tại:

- **mạng — antonshakirov.com** — kiểm tra và tải bản cập nhật, cùng hai trình hỗ
  trợ tuỳ chọn (engine torrent và trình nén 7-Zip)
- **mạng — torrent, đo tốc độ** — lưu lượng tới các peer khác khi bật mô-đun
  torrent; phép đo dùng networkQuality của macOS tới máy chủ Apple
- **trợ năng** — dán vào ứng dụng bên dưới, trình quản lý cửa sổ và khoá bàn phím
- **ghi màn hình** — chỉ mô-đun nhận dạng văn bản, và chỉ khi khoanh vùng; ống
  hút màu không cần
- **thông báo** — báo hết giờ của bộ đếm và torrent đã xong
- **mật khẩu quản trị** — một lần, cho chế độ gập màn hình (pmset chỉ chạy với root)
- **mở khi đăng nhập** — tắt cho đến khi bạn tự bật

Lúc khởi động không xin gì cả, và không xin gì cho một mô-đun bạn chưa bật.
Không phân tích, không đo lường từ xa, không tài khoản, không báo cáo sự cố:
antonshakirov.com chỉ được liên hệ để hỏi xem có phiên bản mới hay không — và để
tải nó, hoặc một trong hai trợ thủ tuỳ chọn, nếu bạn đồng ý. Mọi thứ còn lại ở
lại chiếc Mac này: lịch sử clipboard, thời gian đã ghi, danh sách việc cần làm,
văn bản nhận được và những màu đã lấy.

Mọi quyền ở trên chỉ để một tính năng chạy được — không vì gì khác. Bạn không
cần tin lời: Hop là mã nguồn mở, và đoạn mã để thu thập đơn giản là không tồn
tại — hãy đọc trong kho này. Cửa sổ thông tin của ứng dụng có thẻ «quyền của ứng
dụng» với đúng danh sách này và trạng thái hiện tại của từng quyền.

Trang web: [antonshakirov.com/products/hop](https://www.antonshakirov.com/products/hop)

## Miễn phí, và vì sao

Hop hoàn toàn miễn phí: không dùng thử, không bản pro, không mua trong ứng
dụng. Không quảng cáo, không thu thập dữ liệu, không tài khoản — chẳng có gì để
kiếm tiền và chẳng có gì để bán. Đây là dự án cá nhân: tôi làm Hop cho chính
mình, dùng nó mỗi ngày và chỉ đơn giản là chia sẻ. Nếu thấy hữu ích, hãy giới
thiệu cho người khác. Và nếu bạn muốn góp một tay, giờ đã có cách để ủng hộ
Hop — thuần túy là một món quà, không kèm bất kỳ đặc quyền nào.

## Biên dịch từ mã nguồn

Swift Package Manager, macOS 14+, không có phụ thuộc bên ngoài:

```bash
git clone https://github.com/antonyshakirov/hop.git
cd hop
swift build
./scripts/build-app.sh
```

Quy trình phát triển, pipeline phát hành và đặc tả hành vi nằm trong
[docs/development.md](../development.md) và [docs/spec.md](../spec.md).

## Ủng hộ dự án

Ba cách, cách nào cũng quý:

- **[Ủng hộ Hop bằng một khoản góp](https://web.tribute.tg/d/Nvk)** — đi thẳng vào
  tính năng mới và các bản sửa. Tự nguyện, không phần thưởng, không gì thu phí:
  mọi mô-đun đều như nhau với tất cả.
- **[Tặng repo một ngôi sao](https://github.com/antonyshakirov/hop/stargazers)** —
  người khác tìm ra nó nhờ những ngôi sao.
- **[Mở một issue](https://github.com/antonyshakirov/hop/issues)** — một báo lỗi hay
  một ý tưởng cũng đáng giá như vậy.

## Tác giả & giấy phép

Được tạo bởi [Anton Shakirov](https://www.antonshakirov.com/en). Phát hành
theo [giấy phép MIT](../../LICENSE): tự do sử dụng và chỉnh sửa, giữ nguyên
thông báo bản quyền — nhận ứng dụng này là sản phẩm của riêng bạn là vi
phạm giấy phép.
