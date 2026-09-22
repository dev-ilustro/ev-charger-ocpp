$ErrorActionPreference = "Stop"

$outDir = Join-Path (Get-Location) "presentation_output"
[System.IO.Directory]::CreateDirectory($outDir) | Out-Null
$pptxPath = Join-Path $outDir "EV_Charger_Omise_Executive_Briefing.pptx"
$pdfPath = Join-Path $outDir "EV_Charger_Omise_Executive_Briefing.pdf"
$pngDir = Join-Path $outDir "rendered"
[System.IO.Directory]::CreateDirectory($pngDir) | Out-Null

function Rgb([int]$r, [int]$g, [int]$b) {
  return ($r + ($g -shl 8) + ($b -shl 16))
}

$C = @{
  bg = (Rgb 247 249 251)
  white = (Rgb 255 255 255)
  ink = (Rgb 16 34 49)
  muted = (Rgb 91 105 117)
  rule = (Rgb 210 219 225)
  teal = (Rgb 11 114 133)
  blue = (Rgb 47 128 237)
  paleBlue = (Rgb 234 244 248)
  orange = (Rgb 242 153 74)
  paleOrange = (Rgb 255 242 229)
  green = (Rgb 43 138 62)
  paleGreen = (Rgb 232 245 233)
  red = (Rgb 201 76 76)
  paleRed = (Rgb 253 237 237)
  darkTeal = (Rgb 5 76 88)
}

$ppLayoutBlank = 12
$msoTextOrientationHorizontal = 1
$msoShapeRectangle = 1
$msoShapeRoundedRectangle = 5
$msoShapeOval = 9
$msoConnectorStraight = 1
$ppAlignLeft = 1
$ppAlignCenter = 2
$ppAlignRight = 3
$ppSaveAsOpenXMLPresentation = 24
$ppSaveAsPDF = 32

function AddShape($slide, [int]$type, [double]$left, [double]$top, [double]$width, [double]$height, [int]$fill, [int]$line = -1, [double]$radius = 0) {
  $s = $slide.Shapes.AddShape($type, $left, $top, $width, $height)
  $s.Fill.Solid()
  $s.Fill.ForeColor.RGB = $fill
  if ($line -eq -1) {
    $s.Line.Visible = 0
  } else {
    $s.Line.Visible = -1
    $s.Line.ForeColor.RGB = $line
    $s.Line.Weight = 1
  }
  return $s
}

function AddText($slide, [string]$text, [double]$left, [double]$top, [double]$width, [double]$height, [double]$size, [int]$color, [bool]$bold = $false, [int]$align = 1, [string]$font = "Leelawadee UI") {
  $tb = $slide.Shapes.AddTextbox($msoTextOrientationHorizontal, $left, $top, $width, $height)
  $tb.Fill.Visible = 0
  $tb.Line.Visible = 0
  $tf = $tb.TextFrame
  $tf.MarginLeft = 0
  $tf.MarginRight = 0
  $tf.MarginTop = 0
  $tf.MarginBottom = 0
  $tf.WordWrap = -1
  $tf.AutoSize = 0
  $tr = $tf.TextRange
  $tr.Text = $text
  $tr.Font.Name = $font
  $tr.Font.Size = $size
  $tr.Font.Bold = $bold
  $tr.Font.Color.RGB = $color
  $tr.ParagraphFormat.Alignment = $align
  return $tb
}

function AddRule($slide, [double]$left, [double]$top, [double]$width, [int]$color, [double]$weight = 1) {
  $line = $slide.Shapes.AddLine($left, $top, $left + $width, $top)
  $line.Line.ForeColor.RGB = $color
  $line.Line.Weight = $weight
  return $line
}

function AddArrow($slide, [double]$x1, [double]$y1, [double]$x2, [double]$y2, [int]$color = 0, [double]$weight = 1.5) {
  $line = $slide.Shapes.AddConnector($msoConnectorStraight, $x1, $y1, $x2, $y2)
  $line.Line.ForeColor.RGB = $color
  $line.Line.Weight = $weight
  $line.Line.EndArrowheadStyle = 3
  return $line
}

function AddHeader($slide, [string]$title, [string]$section, [int]$page, $C) {
  AddText $slide $section.ToUpper() 48 28 300 16 10 $C.teal $true $ppAlignLeft | Out-Null
  AddText $slide $title 48 50 850 48 27 $C.ink $true $ppAlignLeft | Out-Null
  AddText $slide ("0" + $page) 884 30 28 18 10 $C.muted $true $ppAlignRight | Out-Null
  AddRule $slide 48 108 864 $C.rule 1 | Out-Null
}

function AddNotes($slide, [string]$notes) {
  try {
    $body = $slide.NotesPage.Shapes.Placeholders.Item(2)
    $body.TextFrame.TextRange.Text = $notes
  } catch {
    # Notes are supplementary; keep deck generation usable if a PowerPoint build has no body placeholder.
  }
}

function AddPill($slide, [string]$label, [double]$left, [double]$top, [double]$width, [int]$fill, [int]$textColor, $C) {
  AddShape $slide $msoShapeRoundedRectangle $left $top $width 24 $fill -1 | Out-Null
  AddText $slide $label $left ($top + 4) $width 24 10 $textColor $true $ppAlignCenter | Out-Null
}

function AddCallout($slide, [string]$number, [string]$title, [string]$body, [double]$left, [double]$top, [double]$width, [int]$accent, $C) {
  AddShape $slide $msoShapeRoundedRectangle $left $top $width 130 $C.white $C.rule | Out-Null
  AddShape $slide $msoShapeOval ($left + 18) ($top + 20) 34 34 $accent -1 | Out-Null
  AddText $slide $number ($left + 18) ($top + 26) 34 24 13 $C.white $true $ppAlignCenter | Out-Null
  AddText $slide $title ($left + 68) ($top + 17) ($width - 86) 24 15 $C.ink $true | Out-Null
  AddText $slide $body ($left + 18) ($top + 68) ($width - 36) 48 12 $C.muted $false | Out-Null
}

$ppt = New-Object -ComObject PowerPoint.Application
$ppt.Visible = -1
$pres = $ppt.Presentations.Add()
$pres.PageSetup.SlideWidth = 960
$pres.PageSetup.SlideHeight = 540

# Slide 1: Cover
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddShape $s $msoShapeRectangle 0 0 960 16 $C.teal -1 | Out-Null
AddShape $s $msoShapeRectangle 0 16 16 524 $C.teal -1 | Out-Null
AddText $s "EV CHARGER PLATFORM" 58 52 260 18 11 $C.teal $true | Out-Null
AddText $s "ก้าวจากโหมดทดสอบ`nสู่การรับชำระเงินจริง" 58 132 620 130 38 $C.ink $true | Out-Null
AddText $s "ข้อเสนอการเชื่อมต่อ Omise Payment Gateway`nสำหรับระบบ EV Charger / OCPP 1.6J" 60 296 520 58 17 $C.muted | Out-Null
AddShape $s $msoShapeRoundedRectangle 650 114 228 248 $C.darkTeal -1 | Out-Null
AddShape $s $msoShapeRectangle 684 150 160 8 $C.orange -1 | Out-Null
AddText $s "OCPP" 678 188 176 44 26 $C.white $true $ppAlignCenter | Out-Null
AddText $s "REAL`nCHARGER CONTROL" 678 250 176 56 13 $C.white $true $ppAlignCenter | Out-Null
AddText $s "PAYMENT" 678 334 176 24 13 $C.orange $true $ppAlignCenter | Out-Null
AddText $s "TEST → LIVE" 60 468 220 18 11 $C.muted $true | Out-Null
AddText $s "Executive Briefing  |  31 สิงหาคม 2026" 600 468 280 18 11 $C.muted $false $ppAlignRight | Out-Null
AddNotes $s "ผู้บริหารควรเห็นภาพรวมว่าแกน OCPP พร้อมเชื่อมเครื่องจริงแล้ว แต่ส่วนการเงินยังเป็นโหมดทดสอบ จึงเสนอให้เชื่อม Omise ในรูปแบบเติมเงินเข้า Wallet ก่อน`n`n[Sources]`n- Local code: app/main.py:140, app/ocpp_handler.py:90, app/main.py:870`n- Omise overview: https://docs.omise.co/thailand"

# Slide 2: Executive summary
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddHeader $s "ระบบหลักพร้อมเชื่อมเครื่องจริง แต่การเงินยังเป็นโหมดทดสอบ" "EXECUTIVE SUMMARY" 2 $C
AddShape $s $msoShapeRoundedRectangle 48 144 250 258 $C.darkTeal -1 | Out-Null
AddText $s "สถานะวันนี้" 72 174 180 22 14 $C.orange $true | Out-Null
AddText $s "HYBRID" 72 218 190 54 34 $C.white $true | Out-Null
AddText $s "OCPP = พร้อมใช้งาน`nPayment = ยังจำลอง" 72 292 180 56 16 $C.white $false | Out-Null
AddPill $s "ควรเดินหน้าทดสอบ Omise" 72 362 190 $C.orange $C.ink $C
AddCallout $s "01" "OCPP เป็นระบบจริง" "รับสถานะและ meter จากเครื่องชาร์จผ่าน WebSocket และส่งคำสั่งกลับได้" 330 144 270 $C.teal $C
AddCallout $s "02" "Wallet ยังเติมแบบ Mock" "ปัจจุบันเพิ่มยอดในฐานข้อมูลโดยตรง ยังไม่ผ่าน payment gateway" 630 144 270 $C.orange $C
AddCallout $s "03" "เป้าหมายที่แนะนำ" "ใช้ Omise รับเงินตอนเติม Wallet แล้วค่อยใช้ Wallet จ่ายค่าชาร์จ" 330 300 570 $C.blue $C
AddText $s "ข้อเสนอเชิงธุรกิจ: เริ่มจาก Prepaid Wallet เพื่อจำกัดความเสี่ยงและไม่กระทบ flow OCPP ที่มีอยู่" 330 454 570 30 15 $C.ink $true | Out-Null
AddNotes $s "สรุปสำหรับผู้บริหาร: ระบบไม่ได้เป็น Mock ทั้งหมด แต่เป็น hybrid โดย OCPP และการบันทึก transaction เป็นระบบจริง ส่วนการเติมเงินลูกค้ายังเป็น mock`n`n[Sources]`n- Local code: app/main.py:140, app/main.py:870, app/ocpp_handler.py:317, app/database.py:145"

# Slide 3: Current state
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddHeader $s "วันนี้ระบบทำอะไรได้แล้ว" "CURRENT STATE" 3 $C
AddText $s "แกนปฏิบัติการของ EV Charger มีองค์ประกอบหลักครบสำหรับการทดลองกับเครื่องจริง" 48 126 760 30 16 $C.muted | Out-Null
AddShape $s $msoShapeRoundedRectangle 48 188 260 166 $C.paleBlue -1 | Out-Null
AddText $s "01  OCPP CENTRAL" 70 212 210 20 13 $C.teal $true | Out-Null
AddText $s "• WebSocket OCPP 1.6J`n• Boot / Heartbeat / Status`n• Remote Start / Stop / Reset" 70 250 210 78 14 $C.ink | Out-Null
AddShape $s $msoShapeRoundedRectangle 350 188 260 166 $C.paleGreen -1 | Out-Null
AddText $s "02  OPERATIONS" 372 212 210 20 13 $C.green $true | Out-Null
AddText $s "• RFID authorization`n• Transaction + MeterValues`n• คำนวณค่าไฟและหัก Wallet" 372 250 210 78 14 $C.ink | Out-Null
AddShape $s $msoShapeRoundedRectangle 652 188 260 166 $C.paleOrange -1 | Out-Null
AddText $s "03  DATA & CONTROL" 674 212 210 20 13 $C.orange $true | Out-Null
AddText $s "• SQLite database`n• Dashboard / Admin / Roles`n• Backup และ audit log" 674 250 210 78 14 $C.ink | Out-Null
AddArrow $s 308 271 348 271 $C.teal 2 | Out-Null
AddArrow $s 610 271 650 271 $C.teal 2 | Out-Null
AddRule $s 48 394 864 $C.rule 1 | Out-Null
AddText $s "ข้อสังเกต" 48 420 90 18 12 $C.teal $true | Out-Null
AddText $s "ใน repository ยังไม่มี charger simulator และยังไม่พบฐานข้อมูล runtime; การยืนยัน end-to-end ต้องใช้เครื่องจริงหรือ OCPP simulator เชื่อมเข้ามา" 152 418 760 38 14 $C.muted | Out-Null
AddNotes $s "สไลด์นี้แยกความพร้อมของระบบปฏิบัติการออกจาก payment: OCPP handlers และ transaction flow มีอยู่แล้ว แต่ใน workspace ยังไม่มี data/ocpp.db และไม่มี simulator`n`n[Sources]`n- Local code: app/main.py:140-169, app/ocpp_handler.py:90-417, app/database.py:21-28`n- Local file inventory: repository root contains no data/ directory"

# Slide 4: Risk / gap
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddHeader $s "ถ้าเปิดใช้งานจริงโดยไม่เปลี่ยน Payment Flow จะเกิดความเสี่ยง" "BUSINESS GAP" 4 $C
AddText $s "ปัญหาไม่ได้อยู่ที่การควบคุมเครื่องชาร์จ แต่อยู่ที่การยืนยันว่าเงินเข้าจริงก่อนให้สิทธิ์ใช้งาน" 48 126 820 30 16 $C.muted | Out-Null
$rows = @(
  [pscustomobject]@{ Label = "เติมเงินปลอม"; Detail = "ยอด Wallet เพิ่มจาก database โดยตรง"; Impact = "รายได้รั่วไหล"; Fill = $C.paleRed; Accent = $C.red }
  [pscustomobject]@{ Label = "บัตรที่ไม่รู้จัก"; Detail = "ค่าเริ่มต้น auto-accept อาจรับบัตรที่ไม่ได้ลงทะเบียน"; Impact = "ชาร์จได้โดยไม่มีเจ้าของให้หักเงิน"; Fill = $C.paleOrange; Accent = $C.orange }
  [pscustomobject]@{ Label = "ยอดเงินไม่แม่นยำ"; Detail = "ใช้ Float และยังไม่มี payment reconciliation"; Impact = "ตรวจสอบย้อนหลังและปิดยอดยาก"; Fill = $C.paleBlue; Accent = $C.blue }
)
$y = 180
foreach ($row in $rows) {
  AddShape $s $msoShapeRoundedRectangle 48 $y 864 78 $row.Fill -1 | Out-Null
  AddText $s $row.Label 72 ($y + 16) 190 24 17 $row.Accent $true | Out-Null
  AddText $s $row.Detail 282 ($y + 16) 310 42 14 $C.ink | Out-Null
  AddText $s "ผลกระทบ: " 638 ($y + 17) 72 20 12 $C.muted $true | Out-Null
  AddText $s $row.Impact 710 ($y + 17) 176 42 13 $C.ink $true | Out-Null
  $y += 92
}
AddShape $s $msoShapeRoundedRectangle 48 472 864 34 $C.darkTeal -1 | Out-Null
AddText $s "หลักการที่ต้องเปลี่ยน: เครดิต Wallet หลัง Omise ยืนยันการชำระเงินสำเร็จเท่านั้น" 68 481 824 18 13 $C.white $true $ppAlignCenter | Out-Null
AddNotes $s "ความเสี่ยงในสไลด์นี้เป็นการอนุมานจากโค้ดปัจจุบัน ไม่ใช่ข้อมูลธุรกรรมจริง`n`n[Sources]`n- Local code: app/main.py:870-892 (mock top-up), app/database.py:168-175 (auto-accept setting), app/database.py:114-115 (Float wallet), app/ocpp_handler.py:317-352 (หัก Wallet ตอนจบ session)"

# Slide 5: Omise role
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddHeader $s "Omise ทำหน้าที่เป็น Payment Gateway ไม่ใช่ระบบควบคุมเครื่องชาร์จ" "OMISE ROLE" 5 $C
AddText $s "แยกสองเรื่องออกจากกัน: Omise ยืนยันเงินเข้า ส่วน OCPP ควบคุมการจ่ายไฟ" 48 126 820 30 16 $C.muted | Out-Null
$flowX = @(70, 270, 470, 670)
$labels = @(
  [pscustomobject]@{ Title = "ลูกค้า"; Body = "เลือกยอดเติมเงิน`nสแกน QR / ชำระ" }
  [pscustomobject]@{ Title = "Omise Charge"; Body = "สร้างรายการ`nสถานะ pending" }
  [pscustomobject]@{ Title = "Webhook"; Body = "แจ้งผลสำเร็จ`nComplete event" }
  [pscustomobject]@{ Title = "EV Wallet"; Body = "เครดิตเงิน`nใช้งานชาร์จ" }
)
for ($i=0; $i -lt 4; $i++) {
  $fill = if ($i -eq 1) { $C.paleBlue } elseif ($i -eq 2) { $C.paleOrange } else { $C.white }
  $accent = if ($i -eq 1) { $C.blue } elseif ($i -eq 2) { $C.orange } else { $C.teal }
  AddShape $s $msoShapeRoundedRectangle $flowX[$i] 212 160 112 $fill $C.rule | Out-Null
  AddShape $s $msoShapeOval ($flowX[$i] + 58) 184 44 44 $accent -1 | Out-Null
  AddText $s ("0" + ($i + 1)) ($flowX[$i] + 58) 195 44 24 12 $C.white $true $ppAlignCenter | Out-Null
  AddText $s $labels[$i].Title $flowX[$i] 232 160 22 14 $C.ink $true $ppAlignCenter | Out-Null
  AddText $s $labels[$i].Body $flowX[$i] 270 160 46 12 $C.muted $false $ppAlignCenter | Out-Null
  if ($i -lt 3) { AddArrow $s ($flowX[$i] + 164) 268 ($flowX[$i] + 194) 268 $C.teal 2 | Out-Null }
}
AddRule $s 48 374 864 $C.rule 1 | Out-Null
AddText $s "สิ่งที่ Omise ช่วยให้เราได้" 48 400 250 22 15 $C.ink $true | Out-Null
AddText $s "• รับ PromptPay / ช่องทางออนไลน์ตามที่เปิดใช้`n• แยก Test Mode และ Live Mode`n• ส่ง Webhook เพื่อแจ้งผลแบบ asynchronous`n• ไม่ต้องให้ server ของเราเก็บเลขบัตร" 48 438 410 66 13 $C.muted | Out-Null
AddText $s "สิ่งที่ Omise ไม่ได้ทำ" 522 400 250 22 15 $C.ink $true | Out-Null
AddText $s "• ไม่ได้คุยกับ charger`n• ไม่ได้คำนวณ kWh`n• ไม่ได้แทนที่ OCPP transaction`n• ไม่ควรเครดิต Wallet จากหน้า redirect อย่างเดียว" 522 438 390 66 13 $C.muted | Out-Null
AddNotes $s "Omise เป็น PCI-certified payment gateway; integration ใช้ public/secret keys, source/charge และ webhook. สำหรับ PromptPay เอกสารระบุให้สร้าง source แล้วสร้าง charge และรอ charge.complete ก่อนยืนยันรายการ`n`n[Sources]`n- Omise overview and keys: https://docs.omise.co/thailand`n- PromptPay flow: https://docs.omise.co/th/promptpay/thailand?version=2019-05-22`n- Webhooks and charge.complete: https://docs.omise.co/th/api-webhooks/thailand`n- Card data tokenization: https://docs.omise.co/th/collecting-card-information/thailand"

# Slide 6: Target architecture
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddHeader $s "รูปแบบที่แนะนำ: เติมเงินก่อน แล้วใช้ Wallet ชำระค่าชาร์จ" "TARGET MODEL" 6 $C
AddText $s "ลดขอบเขตการเปลี่ยนแปลง โดยเชื่อม Omise เฉพาะจุดรับเงินเข้า ไม่ผูกกับทุก OCPP session" 48 126 840 30 16 $C.muted | Out-Null
# connectors first
AddArrow $s 200 238 334 238 $C.blue 2 | Out-Null
AddArrow $s 490 238 624 238 $C.blue 2 | Out-Null
AddArrow $s 624 318 490 318 $C.orange 2 | Out-Null
AddArrow $s 334 318 200 318 $C.teal 2 | Out-Null
AddShape $s $msoShapeRoundedRectangle 48 188 152 174 $C.white $C.rule | Out-Null
AddText $s "CUSTOMER" 68 210 112 18 12 $C.teal $true $ppAlignCenter | Out-Null
AddText $s "เลือกยอดเติม`nแสดง QR`nดูสถานะ Wallet" 68 250 112 70 15 $C.ink $true $ppAlignCenter | Out-Null
AddShape $s $msoShapeRoundedRectangle 334 174 156 202 $C.darkTeal -1 | Out-Null
AddText $s "EV BACKEND" 354 198 116 18 12 $C.orange $true $ppAlignCenter | Out-Null
AddText $s "Create Charge`nPayment Record`nWebhook Verify`nCredit Ledger" 354 236 116 100 15 $C.white $true $ppAlignCenter | Out-Null
AddShape $s $msoShapeRoundedRectangle 624 188 152 174 $C.paleBlue $C.rule | Out-Null
AddText $s "OMISE" 644 210 112 18 12 $C.blue $true $ppAlignCenter | Out-Null
AddText $s "Source / Charge`nPromptPay QR`nComplete event" 644 250 112 70 15 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "เงินเข้า" 232 222 80 18 11 $C.blue $true $ppAlignCenter | Out-Null
AddText $s "ผลชำระ" 526 300 80 18 11 $C.orange $true $ppAlignCenter | Out-Null
AddText $s "Wallet balance" 232 300 80 18 11 $C.teal $true $ppAlignCenter | Out-Null
AddRule $s 48 408 864 $C.rule 1 | Out-Null
AddText $s "Charging path ที่ยังคงเดิม" 48 434 240 20 14 $C.ink $true | Out-Null
AddText $s "Wallet > 0  →  Authorize  →  Start  →  MeterValues  →  Stop  →  หัก Wallet" 300 433 612 22 14 $C.muted $true | Out-Null
AddNotes $s "สถาปัตยกรรมนี้เป็นข้อเสนอเชิงออกแบบสำหรับ codebase ปัจจุบัน: Omise รับเงินเข้า Wallet; OCPP ยังทำหน้าที่เริ่ม/หยุด/เก็บ meter และหักค่าไฟเหมือนเดิม`n`n[Sources]`n- Local code: app/main.py:491-573, app/ocpp_handler.py:217-352, app/database.py:145-157`n- Omise PromptPay source/charge: https://docs.omise.co/th/promptpay/thailand?version=2019-05-22`n- Omise webhook verification: https://docs.omise.co/th/api-webhooks/thailand"

# Slide 7: Roadmap
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddHeader $s "Roadmap 4 ระยะ: ทดสอบให้ผ่านก่อน แล้วค่อยเปิดเงินจริง" "DELIVERY ROADMAP" 7 $C
AddText $s "แต่ละระยะมีเกณฑ์จบชัดเจน ลดความเสี่ยงจากการเปลี่ยนระบบเงินพร้อมกับระบบชาร์จ" 48 126 820 30 16 $C.muted | Out-Null
AddRule $s 88 288 784 $C.rule 2 | Out-Null
$phases = @(
  [pscustomobject]@{ Code = "01"; Title = "เตรียมบัญชี"; Body = "Test keys`nเลือกช่องทาง`nกำหนด payment model"; Accent = $C.teal }
  [pscustomobject]@{ Code = "02"; Title = "เชื่อม Test Mode"; Body = "Create charge`nQR / redirect`nWebhook + idempotency"; Accent = $C.blue }
  [pscustomobject]@{ Code = "03"; Title = "Hardening"; Body = "Integer satang`nAudit / reconciliation`nปิด mock + security"; Accent = $C.orange }
  [pscustomobject]@{ Code = "04"; Title = "Go-live"; Body = "Live keys`nHTTPS webhook`nPilot + monitoring"; Accent = $C.green }
)
$xs = @(88, 300, 512, 724)
for ($i=0; $i -lt 4; $i++) {
  AddShape $s $msoShapeOval $xs[$i] 265 46 46 $phases[$i].Accent -1 | Out-Null
  AddText $s $phases[$i].Code $xs[$i] 277 46 22 12 $C.white $true $ppAlignCenter | Out-Null
  AddText $s $phases[$i].Title ($xs[$i] - 25) 332 96 22 15 $C.ink $true $ppAlignCenter | Out-Null
  AddText $s $phases[$i].Body ($xs[$i] - 25) 370 96 62 12 $C.muted $false $ppAlignCenter | Out-Null
}
AddShape $s $msoShapeRoundedRectangle 48 472 864 34 $C.paleGreen -1 | Out-Null
AddText $s "เกณฑ์ผ่านก่อนเปิดเงินจริง: เงินเข้า Wallet ได้ครั้งเดียวต่อ Charge และทุกยอดตรวจสอบย้อนกลับได้" 68 481 824 18 13 $C.green $true $ppAlignCenter | Out-Null
AddNotes $s "Roadmap เป็นข้อเสนอจากสภาพระบบปัจจุบัน ไม่ใช่ commitment ด้านระยะเวลา`n`n[Sources]`n- Local code: app/main.py:870-892, app/database.py:145-157, app/auth.py:21-34`n- Omise test/live keys: https://docs.omise.co/thailand`n- Omise webhook requirements: https://docs.omise.co/th/api-webhooks/thailand"

# Slide 8: Decision
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddHeader $s "สิ่งที่ขออนุมัติจากผู้บริหาร" "DECISION" 8 $C
AddShape $s $msoShapeRoundedRectangle 48 138 500 300 $C.darkTeal -1 | Out-Null
AddText $s "ข้อเสนอหลัก" 78 168 180 22 15 $C.orange $true | Out-Null
AddText $s "เริ่มจาก`nPromptPay + Prepaid Wallet" 78 214 400 86 31 $C.white $true | Out-Null
AddText $s "เชื่อม Omise เฉพาะตอนเติมเงิน`nและคง OCPP charging flow เดิม" 78 330 400 48 16 $C.white | Out-Null
AddText $s "ผลลัพธ์: รับเงินจริงได้เร็วขึ้น`nโดยกระทบระบบชาร์จน้อยที่สุด" 78 398 400 36 14 $C.orange $true | Out-Null
AddText $s "รายการตัดสินใจ" 600 150 230 24 18 $C.ink $true | Out-Null
AddText $s "01  อนุมัติ payment model แบบ Prepaid Wallet`n`n02  เปิดบัญชี Omise Test และยืนยันช่องทางที่จะใช้`n`n03  อนุมัติ production controls: webhook, audit, reconciliation`n`n04  แต่งตั้ง owner สำหรับการเงินและการกระทบยอด" 600 202 300 190 15 $C.ink | Out-Null
AddRule $s 600 424 300 $C.rule 1 | Out-Null
AddText $s "Next step: เริ่มออกแบบ Payment Transaction + Webhook ใน Test Mode" 600 446 300 42 14 $C.teal $true | Out-Null
AddNotes $s "ปิดการนำเสนอด้วยข้อเสนอที่ต้องการการตัดสินใจ: ใช้ Omise รับเงินตอนเติม Wallet แบบ Prepaid และไม่เปลี่ยน OCPP session flow ในระยะแรก`n`n[Sources]`n- Local code: app/main.py:524-573, app/ocpp_handler.py:317-352`n- Omise PromptPay: https://docs.omise.co/th/promptpay/thailand?version=2019-05-22`n- Omise webhook security: https://docs.omise.co/th/api-webhooks/thailand"

if (Test-Path -LiteralPath $pptxPath) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $pptxPath = Join-Path $outDir "EV_Charger_Omise_Executive_Briefing-$stamp.pptx"
  $pdfPath = Join-Path $outDir "EV_Charger_Omise_Executive_Briefing-$stamp.pdf"
}

$pres.SaveAs($pptxPath, $ppSaveAsOpenXMLPresentation)
$pres.SaveAs($pdfPath, $ppSaveAsPDF)
for ($i = 1; $i -le $pres.Slides.Count; $i++) {
  $pngPath = Join-Path $pngDir ("slide-{0:D2}.png" -f $i)
  $pres.Slides.Item($i).Export($pngPath, "PNG", 1600, 900)
}

$slideCount = $pres.Slides.Count
$pres.Close()
$ppt.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($pres) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($ppt) | Out-Null
[GC]::Collect()
[GC]::WaitForPendingFinalizers()

Write-Output "PPTX=$pptxPath"
Write-Output "PDF=$pdfPath"
Write-Output "PNG_DIR=$pngDir"
Write-Output "SLIDES=$slideCount"
