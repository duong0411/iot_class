# -*- coding: utf-8 -*-
"""PDF hướng dẫn AloT + Xiaozhi — dễ hiểu, format đẹp."""
from pathlib import Path
from fpdf import FPDF

OUT = Path(__file__).resolve().parent / "Huong_Dan_AloT_Xiaozhi_STEM.pdf"
FONT_REG = r"C:\Windows\Fonts\arial.ttf"
FONT_BOLD = r"C:\Windows\Fonts\arialbd.ttf"


class Guide(FPDF):
    def __init__(self):
        super().__init__("P", "mm", "A4")
        self.set_auto_page_break(True, 18)
        self.add_font("VN", "", FONT_REG)
        self.add_font("VN", "B", FONT_BOLD)
        self.set_margins(16, 14, 16)

    def footer(self):
        self.set_y(-12)
        self.set_font("VN", "", 8)
        self.set_text_color(148, 163, 184)
        self.cell(
            0,
            6,
            f"AloT Smart Classroom + Xiaozhi  |  Trang {self.page_no()}/{{nb}}",
            align="C",
        )

    def _x(self):
        self.set_x(self.l_margin)

    def title_cover(self):
        self.add_page()
        self.set_fill_color(14, 165, 233)
        self.rect(0, 0, 210, 52, "F")
        self.set_y(16)
        self.set_font("VN", "B", 22)
        self.set_text_color(255, 255, 255)
        self.cell(0, 10, "HUONG DAN SU DUNG", align="C", new_x="LMARGIN", new_y="NEXT")
        # Use Vietnamese with accents for subtitle
        self.set_font("VN", "B", 13)
        self.cell(
            0,
            8,
            "Lop Hoc Thong Minh AloT + Loa AI Xiaozhi",
            align="C",
            new_x="LMARGIN",
            new_y="NEXT",
        )

        self.set_y(62)
        self.set_font("VN", "", 12)
        self.set_text_color(71, 85, 105)
        self.multi_cell(
            0,
            7,
            "Danh cho giao vien, phu huynh va hoc sinh STEM\n"
            "Khong can biet lap trinh - lam theo tung buoc la duoc",
            align="C",
        )
        self.ln(4)
        items = [
            ("01", "Ket noi Wi-Fi moi cho 2 thiet bi"),
            ("02", "Cac tinh nang trong App (mo ta ro)"),
            ("03", "Che do AUTO va MANUAL"),
            ("04", "Tro chuyen AI Xiaozhi & dieu khien thiet bi"),
            ("05", "Wake-up bang nut BOOT tren mach tim"),
            ("06", "Setup lich auto & loi dan hang ngay"),
            ("07", "Diem danh RFID tren dien thoai + mo cua"),
        ]
        for num, text in items:
            y = self.get_y()
            self.set_fill_color(240, 249, 255)
            self.set_draw_color(14, 165, 233)
            self.rect(22, y, 166, 11, "DF")
            self.set_xy(28, y + 2.5)
            self.set_font("VN", "B", 11)
            self.set_text_color(3, 105, 161)
            self.cell(14, 6, num)
            self.set_font("VN", "", 11)
            self.set_text_color(30, 41, 59)
            self.cell(0, 6, text)
            self.set_y(y + 13)

        self.ln(10)
        self.set_fill_color(224, 242, 254)
        y = self.get_y()
        self.rect(22, y, 166, 28, "F")
        self.set_xy(28, y + 4)
        self.set_font("VN", "B", 11)
        self.set_text_color(3, 105, 161)
        self.cell(0, 6, "Nho 3 phan nhu 3 nguoi ban:")
        self.set_xy(28, y + 12)
        self.set_font("VN", "", 10)
        self.set_text_color(30, 41, 59)
        self.multi_cell(
            154,
            5.5,
            "App = dieu khien tu xa   |   ESP32 lop = cam bien + den/quat/cua/RFID\n"
            "Xiaozhi (mach tim) = tro ly noi chuyen AI",
        )

    def h1(self, n, title):
        self.ln(2)
        if self.get_y() > 255:
            self.add_page()
        self.set_fill_color(14, 165, 233)
        self.set_text_color(255, 255, 255)
        self.set_font("VN", "B", 12.5)
        self._x()
        self.cell(0, 9, f"  {n}.  {title}", fill=True, new_x="LMARGIN", new_y="NEXT")
        self.ln(3)

    def h2(self, title):
        self.ln(1.5)
        self._x()
        self.set_font("VN", "B", 11)
        self.set_text_color(3, 105, 161)
        self.multi_cell(0, 6, title)
        self.ln(0.5)

    def p(self, text):
        self._x()
        self.set_font("VN", "", 10.5)
        self.set_text_color(30, 41, 59)
        self.multi_cell(0, 5.8, text)
        self.ln(1)

    def bullet(self, text):
        self._x()
        self.set_font("VN", "", 10.5)
        self.set_text_color(30, 41, 59)
        self.multi_cell(0, 5.8, f"   -  {text}")
        self.ln(0.25)

    def step(self, i, title, detail=""):
        self._x()
        self.set_font("VN", "B", 10.5)
        self.set_text_color(8, 145, 178)
        self.multi_cell(0, 5.8, f"Buoc {i}: {title}")
        if detail:
            self._x()
            self.set_font("VN", "", 10.5)
            self.set_text_color(51, 65, 85)
            self.multi_cell(0, 5.8, detail)
        self.ln(1)

    def box(self, title, text, kind="tip"):
        palette = {
            "tip": (3, 105, 161),
            "warn": (194, 65, 12),
            "ok": (21, 128, 61),
            "info": (71, 85, 105),
        }
        tr, tg, tb = palette.get(kind, palette["tip"])
        self.ln(1)
        if self.get_y() > 248:
            self.add_page()
        y0 = self.get_y()
        self.set_xy(self.l_margin + 3, y0)
        self.set_font("VN", "B", 10)
        self.set_text_color(tr, tg, tb)
        self.multi_cell(168, 5.2, title)
        self.set_x(self.l_margin + 3)
        self.set_font("VN", "", 10)
        self.set_text_color(30, 41, 59)
        self.multi_cell(168, 5.2, text)
        y1 = self.get_y() + 1
        self.set_draw_color(tr, tg, tb)
        self.set_line_width(1.4)
        self.line(self.l_margin, y0, self.l_margin, y1)
        self.set_y(y1 + 2)

    def table2(self, left_title, left_lines, right_title, right_lines):
        self.ln(1)
        w = 88
        y = self.get_y()
        self.set_xy(self.l_margin, y)
        self.set_fill_color(207, 250, 254)
        self.set_font("VN", "B", 10)
        self.set_text_color(14, 116, 144)
        self.cell(w, 7, f"  {left_title}", fill=True)
        self.set_xy(self.l_margin + w + 2, y)
        self.set_fill_color(255, 237, 213)
        self.set_text_color(194, 65, 12)
        self.cell(w, 7, f"  {right_title}", fill=True)
        y = y + 8
        self.set_font("VN", "", 9.5)
        self.set_text_color(30, 41, 59)
        max_n = max(len(left_lines), len(right_lines))
        for i in range(max_n):
            self.set_xy(self.l_margin, y)
            l = left_lines[i] if i < len(left_lines) else ""
            r = right_lines[i] if i < len(right_lines) else ""
            self.multi_cell(w, 5, l)
            yl = self.get_y()
            self.set_xy(self.l_margin + w + 2, y)
            self.multi_cell(w, 5, r)
            yr = self.get_y()
            y = max(yl, yr) + 0.8
        self.set_y(y + 2)


def vn_fix():
    """Rewrite cover/body with full Vietnamese accents after ASCII scaffold test.
    We embed Vietnamese properly here."""
    pass


def build():
    # Full Vietnamese content
    pdf = Guide()
    pdf.alias_nb_pages()

    # ---- COVER (Vietnamese) ----
    pdf.add_page()
    pdf.set_fill_color(14, 165, 233)
    pdf.rect(0, 0, 210, 52, "F")
    pdf.set_y(14)
    pdf.set_font("VN", "B", 22)
    pdf.set_text_color(255, 255, 255)
    pdf.cell(0, 10, "HƯỚNG DẪN SỬ DỤNG", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("VN", "B", 13)
    pdf.cell(
        0,
        8,
        "Lớp Học Thông Minh AloT + Loa AI Xiaozhi",
        align="C",
        new_x="LMARGIN",
        new_y="NEXT",
    )
    pdf.set_y(60)
    pdf.set_font("VN", "", 12)
    pdf.set_text_color(71, 85, 105)
    pdf.multi_cell(
        0,
        7,
        "Dành cho giáo viên, phụ huynh và học sinh STEM\n"
        "Không cần biết lập trình — làm theo từng bước là được",
        align="C",
    )
    pdf.ln(4)
    items = [
        ("01", "Kết nối Wi-Fi mới cho 2 thiết bị"),
        ("02", "Các tính năng trong App (mô tả rõ)"),
        ("03", "Chế độ AUTO và MANUAL"),
        ("04", "Trò chuyện AI Xiaozhi & điều khiển thiết bị"),
        ("05", "Wake-up bằng nút BOOT trên mạch tím"),
        ("06", "Setup lịch auto & lời dẫn hàng ngày"),
        ("07", "Điểm danh RFID trên điện thoại + mở cửa"),
    ]
    for num, text in items:
        y = pdf.get_y()
        pdf.set_fill_color(240, 249, 255)
        pdf.set_draw_color(14, 165, 233)
        pdf.rect(22, y, 166, 11, "DF")
        pdf.set_xy(28, y + 2.5)
        pdf.set_font("VN", "B", 11)
        pdf.set_text_color(3, 105, 161)
        pdf.cell(14, 6, num)
        pdf.set_font("VN", "", 11)
        pdf.set_text_color(30, 41, 59)
        pdf.cell(0, 6, text)
        pdf.set_y(y + 13)

    pdf.ln(8)
    y = pdf.get_y()
    pdf.set_fill_color(224, 242, 254)
    pdf.rect(22, y, 166, 32, "F")
    pdf.set_xy(28, y + 4)
    pdf.set_font("VN", "B", 11)
    pdf.set_text_color(3, 105, 161)
    pdf.cell(0, 6, "Nhớ 3 phần như 3 người bạn:")
    pdf.set_xy(28, y + 12)
    pdf.set_font("VN", "", 10.5)
    pdf.set_text_color(30, 41, 59)
    pdf.multi_cell(
        154,
        6,
        "App = điều khiển từ xa\n"
        "ESP32 lớp = cảm biến + đèn / quạt / cửa / RFID\n"
        "Xiaozhi (mạch tím) = trợ lý nói chuyện AI",
    )

    # ---- 1 WIFI ----
    pdf.add_page()
    pdf.h1("1", "Kết nối Wi-Fi mới (cả 2 thiết bị)")
    pdf.p(
        "Khi sang Wi-Fi mới (trường / nhà), bạn phải cấu hình lại trên CẢ HAI máy: "
        "(A) mạch ESP32 lớp học và (B) loa Xiaozhi. Hai thiết bị không tự chia sẻ mật khẩu Wi-Fi."
    )

    pdf.h2("A) Mạch ESP32 lớp học (đèn, quạt, cửa, RFID)")
    pdf.step(
        1,
        "Rút điện ESP32, rồi cắm lại 2 lần liên tiếp (double reset).",
        "Cách này xóa Wi-Fi cũ và mở trang cấu hình (Portal).",
    )
    pdf.step(
        2,
        "Trên điện thoại: mở Wi-Fi, kết nối mạng tên SmartClassroom_ESP32.",
        "Thường không cần mật khẩu.",
    )
    pdf.step(3, "Mở trình duyệt Chrome, vào địa chỉ: http://192.168.4.1")
    pdf.step(
        4,
        "Bấm Quét danh sách Wi-Fi → chọn Wi-Fi mới → nhập mật khẩu → Lưu / Kết nối.",
    )
    pdf.step(
        5,
        "Đợi thiết bị khởi động lại. Trên App, chữ ONLINE phải chuyển màu xanh.",
    )
    pdf.box(
        "Mẹo",
        "Không thấy mạng SmartClassroom_ESP32? Đứng gần ESP32 hơn, tắt VPN điện thoại, "
        "thử double-reset lại (rút–cắm–rút–cắm trong vài giây).",
        "tip",
    )

    pdf.h2("B) Loa Xiaozhi (mạch tím)")
    pdf.step(
        1,
        "Rút điện Xiaozhi rồi cắm lại. Ngay lúc đang khởi động, bấm 1 cái nút BOOT.",
        "Nút BOOT nằm gần cổng USB trên mạch tím.",
    )
    pdf.step(
        2,
        "Thiết bị vào chế độ cấu hình Wi-Fi (màn hình báo Config / Wi-Fi).",
        "Điện thoại sẽ thấy mạng Wi-Fi phát ra từ Xiaozhi (tên dạng Xiaozhi-XXXX).",
    )
    pdf.step(
        3,
        "Kết nối điện thoại vào mạng đó, mở trang cấu hình (thường tự mở, hoặc vào 192.168.4.1).",
    )
    pdf.step(4, "Chọn Wi-Fi mới, nhập mật khẩu, Lưu. Xiaozhi tự kết nối lại.")
    pdf.step(
        5,
        "Khi xong, Xiaozhi về trạng thái Chờ (Idle). Bấm BOOT lần nữa để thử trò chuyện.",
    )
    pdf.box(
        "Lưu ý quan trọng",
        "ESP32 lớp và Xiaozhi nên cùng một Wi-Fi (hoặc mạng có Internet). "
        "Xiaozhi cần Internet để nói chuyện AI. ESP32 lớp cần mạng để App điều khiển.",
        "warn",
    )

    # ---- 2 APP ----
    pdf.h1("2", "Cách dùng App — các tính năng")
    pdf.p(
        "Sau khi cài App và đăng nhập bằng email / mật khẩu được cấp, "
        "bạn thấy 2 tab ở thanh dưới màn hình."
    )

    pdf.h2("Tab 1 — Lớp Học")
    pdf.bullet("ONLINE / OFFLINE: xanh = mạch lớp đang sống; đỏ = mất điện hoặc mất Wi-Fi.")
    pdf.bullet("Sỉ số điểm danh RFID: số học sinh có mặt / tổng số.")
    pdf.bullet("Cảm biến môi trường: Nhiệt độ (°C), Độ ẩm (%), Ánh sáng (Tốt / Yếu).")
    pdf.bullet("Thẻ Lịch Auto & Lời dẫn Xiaozhi: đặt giờ nhắc (xem mục 6).")
    pdf.bullet("Chế độ AUTO / MANUAL: máy tự chạy hay bạn bấm tay (xem mục 3).")
    pdf.bullet("Điều khiển: Quạt, Đèn, Cửa sổ / Cửa lớp (servo mở 90° / đóng 0°).")
    pdf.bullet("Đầu đọc RFID: trạng thái đang chờ quẹt thẻ.")

    pdf.h2("Tab 2 — Điểm Danh RFID")
    pdf.bullet("Danh sách học sinh; tìm theo tên / MSSV / mã thẻ.")
    pdf.bullet("Thêm / sửa học sinh và gắn mã thẻ RFID (UID).")
    pdf.bullet("Khi quẹt thẻ: App hiện Có mặt + giờ quẹt; thẻ chưa đăng ký sẽ báo để gắn.")
    pdf.bullet("Nhật ký điểm danh; reset điểm danh đầu ngày.")

    pdf.box(
        "Thứ tự dùng App mỗi ngày",
        "1) Mở App → đăng nhập   2) Tab Lớp Học → nhìn ONLINE xanh   "
        "3) Chọn MANUAL nếu muốn bấm tay   4) Tab Điểm danh khi học sinh vào lớp.",
        "ok",
    )

    # ---- 3 AUTO MANUAL ----
    pdf.add_page()
    pdf.h1("3", "Chế độ AUTO và MANUAL")
    pdf.table2(
        "TỰ ĐỘNG (AUTO)",
        [
            "Máy tự quyết định theo cảm biến.",
            "Nhiệt >= 27°C → thường bật quạt.",
            "Ánh sáng yếu → thường bật đèn.",
            "Hợp khi lớp đang học bình thường.",
            "Ít phải chạm App.",
        ],
        "THỦ CÔNG (MANUAL)",
        [
            "Bạn tự bật / tắt trên App.",
            "Bấm Quạt / Đèn / Cửa theo ý.",
            "Dùng khi demo STEM, tan học,",
            "hoặc cảm biến đang sai / nhiễu.",
            "An toàn khi muốn tắt hết thiết bị.",
        ],
    )
    pdf.h2("Cách chuyển chế độ trên App")
    pdf.step(1, "Vào tab Lớp Học.")
    pdf.step(
        2,
        "Ở thẻ Chế Độ, chọn TỰ ĐỘNG (AUTO) hoặc THỦ CÔNG (MANUAL), hoặc gạt công tắc.",
    )
    pdf.step(3, "Đọc dòng chú thích ngay bên dưới để biết đang ở chế độ nào.")
    pdf.box(
        "Mẹo thực tế",
        "Muốn bật/tắt đèn–quạt bằng tay: PHẢI ở MANUAL. "
        "Nếu vẫn để AUTO, mạch có thể bật/tắt lại theo cảm biến.",
        "warn",
    )

    # ---- 4 CHAT ----
    pdf.h1("4", "Trò chuyện AI Xiaozhi & điều khiển thiết bị")
    pdf.p(
        "Xiaozhi nghe bạn nói → gửi lên máy chủ nhận dạng giọng (ASR) → suy nghĩ (AI) "
        "→ đọc trả lời (TTS). Nếu có lệnh lớp học, AI gọi công cụ điều khiển đèn / quạt / cửa."
    )
    pdf.h2("Cách nói để AI hiểu")
    pdf.bullet("Nói ngắn, rõ, đứng gần loa. Tắt TV / YouTube quanh mic.")
    pdf.bullet('Ví dụ: "Tắt đèn", "Bật quạt", "Mở cửa", "Nhiệt độ bao nhiêu?".')
    pdf.bullet("Đợi nghe tiếng ting / thấy trạng thái Đang nghe, rồi mới nói lệnh.")
    pdf.box(
        'Vì sao Xiaozhi nói linh tinh kiểu "đăng ký kênh..."?',
        "Mic đang nghe tiếng nền YouTube. Hãy tắt tiếng nền, đứng gần hơn, nói ngắn sau tiếng ting. "
        "Hoặc dùng App ở MANUAL để bật/tắt chắc chắn.",
        "warn",
    )

    # ---- 5 BOOT ----
    pdf.h1("5", "Wake-up Xiaozhi bằng nút BOOT trên mạch tím")
    pdf.p(
        "Trên mạch tím, nút BOOT dùng để bắt đầu / kết thúc phiên nói chuyện. "
        "Đây là cách ổn định nhất khi từ khóa giọng (wake word) khó nhận."
    )
    pdf.step(
        1,
        "Để Xiaozhi ở trạng thái Chờ (Idle) — không đang phát lịch hay đang nói.",
    )
    pdf.step(
        2,
        "Bấm 1 cái nút BOOT trên mạch tím.",
        "Thiết bị kết nối máy chủ, phát tiếng ting, rồi chuyển sang Đang nghe.",
    )
    pdf.step(3, 'Đợi khoảng 1 giây sau ting, rồi nói lệnh (ví dụ: "Bật quạt").')
    pdf.step(4, "Nghe Xiaozhi trả lời / thực hiện. Bấm BOOT lại nếu muốn dừng phiên.")
    pdf.box(
        "Ghi nhớ",
        "Bấm BOOT lúc thiết bị VỪA KHỞI ĐỘNG = vào cấu hình Wi-Fi (mục 1B). "
        "Bấm BOOT khi đã Chờ sẵn = bắt đầu trò chuyện AI.",
        "info",
    )

    # ---- 6 SCHEDULE ----
    pdf.add_page()
    pdf.h1("6", "Setup lịch auto & lời dẫn hàng ngày")
    pdf.p(
        "Bạn đặt mốc giờ + câu nói. Đến giờ, hệ thống tạo file giọng nói và Xiaozhi phát lời dẫn "
        "(ví dụ truy bài 7:45, tan học 17:00)."
    )
    pdf.step(
        1,
        'Tab Lớp Học → bấm biểu tượng đồng hồ (góc trên) hoặc thẻ "Cài Đặt Lịch Auto & Lời Dẫn Xiaozhi".',
    )
    pdf.step(2, "Bấm + Thêm Lịch (hoặc sửa lịch có sẵn).")
    pdf.step(3, "Chọn giờ : phút. Viết lời dẫn tiếng Việt dễ hiểu, 1–2 câu.")
    pdf.step(4, "Bật công tắc Enabled (bật lịch).")
    pdf.step(5, "Bấm Lưu / Đồng bộ. App gửi lịch lên máy chủ.")
    pdf.step(
        6,
        "Xiaozhi cần có Wi-Fi + đúng giờ Việt Nam. Đến giờ sẽ phát.",
    )
    pdf.h2("Ví dụ lời dẫn")
    pdf.bullet('"Đã đến giờ truy bài, các bạn chuẩn bị vào lớp!"')
    pdf.bullet('"Giờ giải lao 10 phút, nhớ uống nước."')
    pdf.bullet('"Đã đến giờ tan học, nhớ tắt đèn quạt trước khi ra về."')
    pdf.box(
        "Nếu đến giờ không nghe gì",
        "Kiểm tra lịch đã Lưu & đang bật; Xiaozhi online; không đang bận nói chuyện AI. "
        "Thử tạo lịch sau 2–3 phút để test ngay.",
        "tip",
    )

    # ---- 7 RFID ----
    pdf.h1("7", "Điểm danh RFID hiện trên điện thoại + mở cửa")
    pdf.p(
        "Khi học sinh quẹt thẻ RFID vào đầu đọc RC522 trên ESP32 lớp học: "
        "(1) Servo cửa mở khoảng 90° trong khoảng 3 giây rồi tự đóng, "
        "(2) Mã thẻ gửi lên App qua mạng, "
        "(3) App đánh dấu Có mặt nếu thẻ đã gắn học sinh."
    )

    pdf.h2("Trên App — bạn thấy gì?")
    pdf.step(1, 'Tab Lớp Học: số "Sỉ số điểm danh RFID" tăng (ví dụ 12/30).')
    pdf.step(2, "Tab Điểm Danh RFID: học sinh chuyển trạng thái Có mặt + giờ quẹt.")
    pdf.step(
        3,
        'Nếu thẻ CHƯA đăng ký: App báo "Thẻ RFID mới vừa quẹt" + mã UID để bạn gắn vào học sinh.',
    )

    pdf.h2("Gắn thẻ cho học sinh (làm 1 lần)")
    pdf.step(1, "Cho học sinh quẹt thẻ (hoặc nhìn UID hiện trên App).")
    pdf.step(2, "Tab Điểm Danh → Thêm/Sửa học sinh → dán mã RFID (UID) → Lưu.")
    pdf.step(3, "Lần sau quẹt: tự động điểm danh đúng tên.")

    pdf.h2("Cửa lớp (động cơ servo)")
    pdf.bullet("Quẹt thẻ: ESP32 mở cửa 90° khoảng 3 giây, rồi đóng về 0°.")
    pdf.bullet('Trên App (MANUAL): bấm "Cửa Sổ / Cửa Lớp" để mở/đóng thủ công.')
    pdf.bullet('Bằng Xiaozhi: nói "Mở cửa" / "Đóng cửa" sau khi wake bằng BOOT.')
    pdf.box(
        "An toàn",
        "Không để tay vào khe cửa khi servo đang quay. "
        "Chỉ giáo viên / kỹ thuật viên được thao dây điện.",
        "warn",
    )

    # ---- checklist ----
    pdf.h1("8", "Checklist 1 phút trước giờ STEM")
    pdf.bullet("[ ] ESP32 lớp: có điện, App ONLINE xanh")
    pdf.bullet("[ ] Xiaozhi: có điện, Wi-Fi, ở trạng thái Chờ")
    pdf.bullet("[ ] Biết đang AUTO hay MANUAL")
    pdf.bullet("[ ] Phòng đủ yên nếu demo giọng nói")
    pdf.bullet("[ ] Có sẵn 1 lịch test sau vài phút (tuỳ chọn)")
    pdf.bullet("[ ] Thẻ RFID mẫu đã gắn học sinh để demo điểm danh + mở cửa")

    pdf.ln(3)
    pdf.box(
        "Chúc bạn dạy và học vui!",
        "Bắt đầu từ App (dễ thấy kết quả), rồi thử nút BOOT Xiaozhi, "
        "cuối cùng mới thử wake bằng giọng. Mỗi lần thành công là một thí nghiệm STEM hoàn chỉnh.",
        "ok",
    )

    pdf.output(str(OUT))
    print(f"WROTE={OUT}")
    print(f"SIZE={OUT.stat().st_size}")


if __name__ == "__main__":
    build()
