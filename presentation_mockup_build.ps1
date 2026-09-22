$ErrorActionPreference = "Stop"

$outDir = Join-Path (Get-Location) "presentation_output_mockup"
[System.IO.Directory]::CreateDirectory($outDir) | Out-Null
$pptxPath = Join-Path $outDir "EV_Charger_Omise_Executive_Mockup.pptx"
$pdfPath = Join-Path $outDir "EV_Charger_Omise_Executive_Mockup.pdf"
$pngDir = Join-Path $outDir "rendered"
[System.IO.Directory]::CreateDirectory($pngDir) | Out-Null
$nl = [char]10

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
  orange = (Rgb 242 153 74)
  green = (Rgb 43 138 62)
  red = (Rgb 201 76 76)
  darkTeal = (Rgb 5 76 88)
  paleBlue = (Rgb 234 244 248)
  paleOrange = (Rgb 255 242 229)
  paleGreen = (Rgb 232 245 233)
  paleRed = (Rgb 253 237 237)
  paleGray = (Rgb 241 244 246)
}

$ppLayoutBlank = 12
$msoShapeRectangle = 1
$msoShapeRoundedRectangle = 5
$msoShapeOval = 9
$ppAlignLeft = 1
$ppAlignCenter = 2
$ppAlignRight = 3
$ppSaveAsOpenXMLPresentation = 24
$ppSaveAsPDF = 32

function AddShape($slide, [int]$type, [double]$left, [double]$top, [double]$width, [double]$height, [int]$fill, [int]$line = -1) {
  $s = $slide.Shapes.AddShape($type, $left, $top, $width, $height)
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

function AddText($slide, [string]$text, [double]$left, [double]$top, [double]$width, [double]$height, [double]$size, [int]$color, [bool]$bold = $false, [int]$align = 1) {
  $tb = $slide.Shapes.AddTextbox(1, $left, $top, $width, $height)
  $tb.Fill.Visible = 0
  $tb.Line.Visible = 0
  $tf = $tb.TextFrame
  $tf.MarginLeft = 0
  $tf.MarginRight = 0
  $tf.MarginTop = 0
  $tf.MarginBottom = 0
  $tf.WordWrap = -1
  $tf.AutoSize = 0
  $tf.VerticalAnchor = 1
  $tf.TextRange.Text = $text
  $tf.TextRange.ParagraphFormat.Alignment = $align
  $tf.TextRange.Font.Name = "Leelawadee UI"
  $tf.TextRange.Font.NameFarEast = "Leelawadee UI"
  $tf.TextRange.Font.Size = $size
  $tf.TextRange.Font.Bold = if ($bold) { -1 } else { 0 }
  $tf.TextRange.Font.Color.RGB = $color
  return $tb
}

function AddRule($slide, [double]$left, [double]$top, [double]$width, [int]$color, [double]$weight = 1) {
  $line = $slide.Shapes.AddLine($left, $top, ($left + $width), $top)
  $line.Line.ForeColor.RGB = $color
  $line.Line.Weight = $weight
  return $line
}

function AddArrow($slide, [double]$x1, [double]$y1, [double]$x2, [double]$y2, [int]$color, [double]$weight = 2) {
  $line = $slide.Shapes.AddLine($x1, $y1, $x2, $y2)
  $line.Line.ForeColor.RGB = $color
  $line.Line.Weight = $weight
  $line.Line.EndArrowheadStyle = 3
  return $line
}

function AddHeader($slide, [string]$title, [string]$section, [int]$page) {
  AddText $slide $section.ToUpper() 48 28 300 16 10 $C.teal $true $ppAlignLeft | Out-Null
  AddText $slide $title 48 50 850 48 26 $C.ink $true $ppAlignLeft | Out-Null
  AddText $slide ("0" + $page) 884 30 28 18 10 $C.muted $true $ppAlignRight | Out-Null
  AddRule $slide 48 108 864 $C.rule 1 | Out-Null
}

function AddNotes($slide, [string]$notes) {
  try {
    $slide.NotesPage.Shapes.Placeholders.Item(2).TextFrame.TextRange.Text = $notes
  } catch {}
}

function AddBrowserFrame($slide, [double]$left, [double]$top, [double]$width, [double]$height, [string]$caption, [int]$captionColor) {
  AddShape $slide $msoShapeRoundedRectangle $left $top $width $height $C.white $C.rule | Out-Null
  AddShape $slide $msoShapeRectangle ($left + 1) ($top + 1) ($width - 2) 26 $C.paleGray -1 | Out-Null
  AddShape $slide $msoShapeOval ($left + 12) ($top + 9) 7 7 $C.red -1 | Out-Null
  AddShape $slide $msoShapeOval ($left + 24) ($top + 9) 7 7 $C.orange -1 | Out-Null
  AddShape $slide $msoShapeOval ($left + 36) ($top + 9) 7 7 $C.green -1 | Out-Null
  AddText $slide $caption ($left + 60) ($top + 7) ($width - 72) 14 9 $captionColor $true $ppAlignLeft | Out-Null
}

# Slide 1: cover
$ppt = New-Object -ComObject PowerPoint.Application
$ppt.Visible = -1
$pres = $ppt.Presentations.Add()
$pres.PageSetup.SlideWidth = 960
$pres.PageSetup.SlideHeight = 540
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddShape $s $msoShapeRectangle 0 0 16 540 $C.teal -1 | Out-Null
AddText $s "EV CHARGER PLATFORM" 58 52 260 18 11 $C.teal $true | Out-Null
AddText $s "จากเติมเงินแบบ Mock${nl}สู่ Payment ที่ตรวจสอบได้" 58 132 540 110 36 $C.ink $true | Out-Null
AddText $s "Mockup proposal: เติมเงินผ่าน Omise แล้วจึงเครดิตเข้า Wallet" 60 286 510 26 17 $C.muted | Out-Null
AddText $s "สำหรับระบบ EV Charger / OCPP 1.6J" 60 320 430 24 15 $C.muted | Out-Null
AddShape $s $msoShapeRoundedRectangle 650 116 226 284 $C.darkTeal -1 | Out-Null
AddText $s "เติมเงินเข้า Wallet" 678 150 170 22 15 $C.white $true $ppAlignCenter | Out-Null
AddText $s "฿500.00" 678 195 170 42 30 $C.white $true $ppAlignCenter | Out-Null
AddShape $s $msoShapeRoundedRectangle 678 258 170 34 $C.paleBlue -1 | Out-Null
AddText $s "PromptPay" 692 268 142 16 12 $C.blue $true $ppAlignCenter | Out-Null
AddShape $s $msoShapeRoundedRectangle 678 310 170 36 $C.orange -1 | Out-Null
AddText $s "สร้างรายการชำระเงิน" 688 321 150 16 11 $C.white $true $ppAlignCenter | Out-Null
AddText $s "Executive Mockup" 60 468 220 18 11 $C.muted $true | Out-Null
AddText $s "Omise × EV Charger" 690 468 190 18 11 $C.muted $false $ppAlignRight | Out-Null
AddNotes $s ("เปิดด้วยภาพปลายทาง: ผู้ใช้เลือกยอดเติมเงินและชำระผ่าน Omise จากนั้นระบบจึงเครดิต Wallet โดยมีหลักฐานธุรกรรมตรวจสอบย้อนกลับได้" + $nl + $nl + "[Sources]" + $nl + "- Local code: app/static/index.html:164-196, app/static/app.js:159-178" + $nl + "- Omise overview: https://docs.omise.co/thailand")

# Slide 2: before and after UI
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddHeader $s "ผู้บริหารจะเห็นอะไรบนหน้าจอ: วันนี้ vs หลังเชื่อม Omise" "AS-IS → TO-BE" 2
AddText $s "เราเพิ่มขั้นตอนชำระเงินเข้ามาเฉพาะตอนเติม Wallet ไม่รบกวนหน้าควบคุมเครื่องชาร์จ" 48 126 840 26 15 $C.muted | Out-Null

AddBrowserFrame $s 48 174 372 286 "วันนี้: เติมเงินแบบ Mock" $C.red
AddShape $s $msoShapeRoundedRectangle 64 214 88 226 $C.darkTeal -1 | Out-Null
AddText $s "⚡ OCPP" 74 234 68 16 10 $C.white $true $ppAlignCenter | Out-Null
AddText $s "หน้าหลัก" 74 276 68 14 9 $C.white | Out-Null
AddText $s "ตั้งค่า" 74 304 68 14 9 $C.orange $true | Out-Null
AddText $s "เครื่องชาร์จ" 74 332 68 14 9 $C.white | Out-Null
AddText $s "กระเป๋าเงินของฉัน" 174 234 184 20 14 $C.ink $true | Out-Null
AddText $s "ยอดเงินคงเหลือ" 174 266 120 14 9 $C.muted | Out-Null
AddText $s "฿0.00" 174 282 100 24 20 $C.green $true | Out-Null
AddShape $s $msoShapeRoundedRectangle 174 326 220 48 $C.paleRed -1 | Out-Null
AddText $s "⚠ โหมดทดสอบ เงินไม่ได้เคลื่อนไหวจริง" 184 339 198 20 10 $C.red $true | Out-Null
AddText $s "จำนวนเงิน (บาท)" 174 392 120 14 9 $C.muted | Out-Null
AddShape $s $msoShapeRoundedRectangle 174 408 96 24 $C.white $C.rule | Out-Null
AddText $s "500" 184 414 76 12 10 $C.ink | Out-Null
AddShape $s $msoShapeRoundedRectangle 282 408 112 24 $C.red -1 | Out-Null
AddText $s "เติมเงิน (ทดสอบ)" 290 414 96 12 9 $C.white $true $ppAlignCenter | Out-Null

AddArrow $s 434 318 500 318 $C.orange 3 | Out-Null
AddText $s "เพิ่ม payment step" 430 278 84 30 10 $C.orange $true $ppAlignCenter | Out-Null

AddBrowserFrame $s 516 174 396 286 "หลังเชื่อม Omise: เติมเงินจริง" $C.green
AddShape $s $msoShapeRoundedRectangle 532 214 88 226 $C.darkTeal -1 | Out-Null
AddText $s "⚡ OCPP" 542 234 68 16 10 $C.white $true $ppAlignCenter | Out-Null
AddText $s "หน้าหลัก" 542 276 68 14 9 $C.white | Out-Null
AddText $s "ตั้งค่า" 542 304 68 14 9 $C.orange $true | Out-Null
AddText $s "เครื่องชาร์จ" 542 332 68 14 9 $C.white | Out-Null
AddText $s "กระเป๋าเงินของฉัน" 642 234 224 20 14 $C.ink $true | Out-Null
AddText $s "ยอดเงินคงเหลือ" 642 266 120 14 9 $C.muted | Out-Null
AddText $s "฿0.00" 642 282 100 24 20 $C.green $true | Out-Null
AddText $s "จำนวนเงิน (บาท)" 642 326 100 14 9 $C.muted | Out-Null
AddShape $s $msoShapeRoundedRectangle 642 342 94 24 $C.white $C.rule | Out-Null
AddText $s "500" 652 348 74 12 10 $C.ink | Out-Null
AddText $s "ช่องทางชำระเงิน" 750 326 120 14 9 $C.muted | Out-Null
AddShape $s $msoShapeRoundedRectangle 750 342 124 24 $C.paleBlue $C.blue | Out-Null
AddText $s "PromptPay" 758 348 108 12 10 $C.blue $true $ppAlignCenter | Out-Null
AddShape $s $msoShapeRoundedRectangle 642 386 232 30 $C.orange -1 | Out-Null
AddText $s "สร้างรายการชำระเงิน" 650 394 216 14 10 $C.white $true $ppAlignCenter | Out-Null
AddText $s "สถานะ: รอการยืนยันจาก Omise" 642 426 232 12 9 $C.muted | Out-Null
AddNotes $s ("สไลด์นี้ใช้หน้าจอจริงของระบบเป็นฐาน: ปัจจุบันมี Wallet card, input จำนวนเงิน และปุ่มเติมเงินทดสอบ เพิ่ม mockup ของหน้าจอเป้าหมายที่มีช่องทางชำระและสถานะรอการยืนยัน" + $nl + $nl + "[Sources]" + $nl + "- Local code: app/static/index.html:164-196, app/static/app.js:159-178" + $nl + "- Proposed UI: payment method selector, payment status, verified credit")

# Slide 3: current behavior
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddHeader $s "As-is: วันนี้กดปุ่มเติมเงินทดสอบ แล้วเกิดอะไรขึ้น" "CURRENT FLOW" 3
AddText $s "เงินถูกเพิ่มในฐานข้อมูลทันที จึงยังไม่มีหลักฐานว่าเงินจากผู้ใช้เคลื่อนย้ายจริง" 48 126 840 26 15 $C.muted | Out-Null
AddShape $s $msoShapeRoundedRectangle 48 178 316 244 $C.white $C.rule | Out-Null
AddText $s "หน้าจอปัจจุบัน" 72 202 230 20 15 $C.ink $true | Out-Null
AddShape $s $msoShapeRoundedRectangle 72 244 264 54 $C.paleRed -1 | Out-Null
AddText $s "เติมเงินเข้ากระเป๋า" 88 257 232 16 13 $C.red $true | Out-Null
AddText $s "โหมดทดสอบ ยังไม่เชื่อมระบบชำระเงินจริง" 88 279 232 12 9 $C.red | Out-Null
AddText $s "Input: amount = 500" 72 326 264 20 13 $C.ink | Out-Null
AddShape $s $msoShapeRoundedRectangle 72 364 264 32 $C.red -1 | Out-Null
AddText $s "เติมเงิน (ทดสอบ)" 82 373 244 14 11 $C.white $true $ppAlignCenter | Out-Null
AddText $s "จุดที่ต้องเปลี่ยน" 72 432 264 18 12 $C.orange $true | Out-Null
AddText $s "ปุ่มนี้ต้องเปลี่ยนเป็น สร้างรายการชำระเงิน" 72 452 264 28 12 $C.ink | Out-Null
AddArrow $s 392 290 452 290 $C.red 3 | Out-Null
AddArrow $s 392 366 452 366 $C.red 3 | Out-Null
AddText $s "ตรงเข้าฐานข้อมูล" 386 322 76 28 9 $C.red $true $ppAlignCenter | Out-Null
AddShape $s $msoShapeRoundedRectangle 484 178 428 244 $C.paleGray -1 | Out-Null
AddText $s "Backend ปัจจุบัน" 512 202 250 20 15 $C.ink $true | Out-Null
AddShape $s $msoShapeRoundedRectangle 512 244 372 46 $C.white $C.rule | Out-Null
AddText $s "POST /api/me/wallet/topup" 530 258 336 18 13 $C.blue $true | Out-Null
AddText $s "1" 512 316 24 24 16 $C.red $true $ppAlignCenter | Out-Null
AddText $s "wallet_balance += amount" 552 316 290 20 14 $C.ink $true | Out-Null
AddText $s "2" 512 354 24 24 16 $C.red $true $ppAlignCenter | Out-Null
AddText $s "สร้าง ledger reason = topup" 552 354 290 20 14 $C.ink | Out-Null
AddShape $s $msoShapeRoundedRectangle 512 390 372 30 $C.paleRed -1 | Out-Null
AddText $s "ไม่มี Charge ID / Webhook / Reconciliation" 524 398 348 14 11 $C.red $true $ppAlignCenter | Out-Null
AddNotes $s ("นี่คือพฤติกรรมของ mock top-up ในระบบปัจจุบัน: endpoint เพิ่มยอด Wallet โดยตรงและสร้าง ledger ฝั่ง topup ไม่ได้ผูกกับ payment gateway" + $nl + $nl + "[Sources]" + $nl + "- Local code: app/main.py:870-892" + $nl + "- Local code: app/database.py:145-157, 173-175")

# Slide 4: target journey
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddHeader $s "To-be: ผู้ใช้จะเดินผ่าน 5 ขั้นตอนก่อน Wallet ได้รับเงิน" "TARGET JOURNEY" 4
AddText $s "แต่ละสถานะต้องเห็นได้จากหน้าจอ เพื่อให้รู้ว่าเงินอยู่ขั้นตอนไหนและยังใช้ชาร์จไม่ได้จนกว่าจะยืนยันสำเร็จ" 48 126 850 26 15 $C.muted | Out-Null
AddShape $s $msoShapeRoundedRectangle 48 190 160 210 $C.white $C.rule | Out-Null
AddShape $s $msoShapeOval 104 166 48 48 $C.teal -1 | Out-Null
AddText $s "01" 104 178 48 20 13 $C.white $true $ppAlignCenter | Out-Null
AddText $s "เลือกยอดเติมเงิน" 68 226 120 20 14 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "จำนวนเงิน${nl}฿500.00" 68 270 120 44 18 $C.teal $true $ppAlignCenter | Out-Null
AddShape $s $msoShapeRoundedRectangle 68 344 120 28 $C.orange -1 | Out-Null
AddText $s "ดำเนินการต่อ" 76 352 104 14 10 $C.white $true $ppAlignCenter | Out-Null
AddArrow $s 216 292 246 292 $C.teal 2 | Out-Null
AddShape $s $msoShapeRoundedRectangle 254 190 160 210 $C.paleBlue -1 | Out-Null
AddShape $s $msoShapeOval 310 166 48 48 $C.blue -1 | Out-Null
AddText $s "02" 310 178 48 20 13 $C.white $true $ppAlignCenter | Out-Null
AddText $s "สร้างรายการ" 274 226 120 20 14 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "Payment Transaction" 274 274 120 20 13 $C.blue $true $ppAlignCenter | Out-Null
AddText $s "สถานะ: pending" 274 324 120 16 11 $C.muted $false $ppAlignCenter | Out-Null
AddArrow $s 422 292 452 292 $C.blue 2 | Out-Null
AddShape $s $msoShapeRoundedRectangle 460 190 160 210 $C.paleOrange -1 | Out-Null
AddShape $s $msoShapeOval 516 166 48 48 $C.orange -1 | Out-Null
AddText $s "03" 516 178 48 20 13 $C.white $true $ppAlignCenter | Out-Null
AddText $s "ชำระผ่าน Omise" 480 226 120 20 14 $C.ink $true $ppAlignCenter | Out-Null
AddShape $s $msoShapeRectangle 510 268 60 60 $C.white $C.rule | Out-Null
AddText $s "QR" 510 288 60 20 16 $C.blue $true $ppAlignCenter | Out-Null
AddText $s "PromptPay" 480 344 120 16 11 $C.orange $true $ppAlignCenter | Out-Null
AddArrow $s 628 292 658 292 $C.orange 2 | Out-Null
AddShape $s $msoShapeRoundedRectangle 666 190 160 210 $C.paleGreen -1 | Out-Null
AddShape $s $msoShapeOval 722 166 48 48 $C.green -1 | Out-Null
AddText $s "04" 722 178 48 20 13 $C.white $true $ppAlignCenter | Out-Null
AddText $s "Webhook" 686 226 120 20 14 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "charge.complete" 686 274 120 18 12 $C.green $true $ppAlignCenter | Out-Null
AddText $s "ตรวจ signature${nl}และกันซ้ำ" 686 322 120 34 11 $C.muted $false $ppAlignCenter | Out-Null
AddArrow $s 834 292 864 292 $C.green 2 | Out-Null
AddShape $s $msoShapeRoundedRectangle 866 190 60 210 $C.darkTeal -1 | Out-Null
AddText $s "05" 872 214 48 20 13 $C.white $true $ppAlignCenter | Out-Null
AddText $s "เครดิต${nl}Wallet" 872 266 48 42 14 $C.white $true $ppAlignCenter | Out-Null
AddText $s "฿500" 872 342 48 18 13 $C.orange $true $ppAlignCenter | Out-Null
AddShape $s $msoShapeRoundedRectangle 48 444 878 42 $C.paleGreen -1 | Out-Null
AddText $s "เกณฑ์สำคัญ: เครดิต Wallet หลังได้รับผลสำเร็จจาก Omise เท่านั้น ไม่ใช่จากหน้า redirect" 64 456 846 18 13 $C.green $true $ppAlignCenter | Out-Null
AddNotes $s ("นี่คือ user journey ที่ควรอยู่ใน mockup: ก่อนเครดิตต้องผ่าน pending → ชำระ → webhook → verify → ledger" + $nl + $nl + "[Sources]" + $nl + "- Omise PromptPay: https://docs.omise.co/th/promptpay/thailand?version=2019-05-22" + $nl + "- Omise webhooks: https://docs.omise.co/th/api-webhooks/thailand")

# Slide 5: architecture
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddHeader $s "สิ่งที่จะเพิ่มในระบบ: Payment Layer แยกจาก OCPP Layer" "SYSTEM CHANGE" 5
AddText $s "เพิ่ม payment flow เฉพาะจุดเติมเงิน แล้วส่งผลลัพธ์เข้า Wallet ledger อย่างมีหลักฐาน" 48 126 840 26 15 $C.muted | Out-Null
AddShape $s $msoShapeRoundedRectangle 48 188 188 184 $C.white $C.rule | Out-Null
AddText $s "CUSTOMER UI" 72 210 140 18 12 $C.teal $true $ppAlignCenter | Out-Null
AddText $s "เลือกยอดเติมเงิน${nl}เลือกช่องทาง${nl}ดู QR / สถานะ" 72 254 140 66 15 $C.ink $true $ppAlignCenter | Out-Null
AddArrow $s 244 278 304 278 $C.blue 3 | Out-Null
AddShape $s $msoShapeRoundedRectangle 316 164 276 232 $C.darkTeal -1 | Out-Null
AddText $s "EV BACKEND" 350 188 208 18 12 $C.orange $true $ppAlignCenter | Out-Null
AddShape $s $msoShapeRoundedRectangle 344 226 220 34 $C.white -1 | Out-Null
AddText $s "Payment Transaction" 354 236 200 14 12 $C.ink $true $ppAlignCenter | Out-Null
AddShape $s $msoShapeRoundedRectangle 344 274 220 34 $C.white -1 | Out-Null
AddText $s "Webhook Verify + Idempotency" 354 284 200 14 11 $C.ink $true $ppAlignCenter | Out-Null
AddShape $s $msoShapeRoundedRectangle 344 322 220 34 $C.paleGreen -1 | Out-Null
AddText $s "Credit Wallet Ledger" 354 332 200 14 12 $C.green $true $ppAlignCenter | Out-Null
AddArrow $s 600 248 652 248 $C.blue 3 | Out-Null
AddArrow $s 652 328 600 328 $C.orange 3 | Out-Null
AddText $s "Create" 604 220 54 16 9 $C.blue $true $ppAlignCenter | Out-Null
AddText $s "Webhook" 604 340 56 16 9 $C.orange $true $ppAlignCenter | Out-Null
AddShape $s $msoShapeRoundedRectangle 664 188 248 184 $C.paleBlue -1 | Out-Null
AddText $s "OMISE" 720 210 136 18 12 $C.blue $true $ppAlignCenter | Out-Null
AddText $s "Source / Charge${nl}PromptPay QR${nl}charge.complete" 704 254 168 82 13 $C.ink $true $ppAlignCenter | Out-Null
AddRule $s 48 414 864 $C.rule 1 | Out-Null
AddText $s "ขอบเขตงานที่เพิ่ม" 48 438 160 18 14 $C.ink $true | Out-Null
AddText $s "Payment API  •  payment_transactions  •  webhook endpoint  •  ledger idempotency  •  reconciliation view" 218 438 694 20 13 $C.muted | Out-Null
AddNotes $s ("สถาปัตยกรรมเป้าหมายแยก payment layer ออกจาก OCPP layer: EV backend สร้าง charge, รับ webhook, ตรวจซ้ำ และเครดิต ledger" + $nl + $nl + "[Sources]" + $nl + "- Local code: app/main.py:140-169, app/ocpp_handler.py:90-417" + $nl + "- Local code: app/database.py:145-157, app/ocpp_handler.py:317-352" + $nl + "- Omise PromptPay and webhooks: https://docs.omise.co/th/promptpay/thailand?version=2019-05-22")

# Slide 6: data and API
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddHeader $s "จาก endpoint เดิม สู่ payment record ที่ตรวจสอบย้อนหลังได้" "DATA & API" 6
AddText $s "การเปลี่ยนแปลงหลักอยู่ในข้อมูลธุรกรรมและการรับผล asynchronous ไม่ใช่ใน OCPP session" 48 126 840 26 15 $C.muted | Out-Null
AddText $s "วันนี้" 64 176 120 20 15 $C.red $true | Out-Null
AddShape $s $msoShapeRoundedRectangle 48 210 392 224 $C.paleRed -1 | Out-Null
AddText $s "POST /api/me/wallet/topup" 72 236 344 20 14 $C.red $true | Out-Null
AddText $s "amount = 500" 72 278 300 18 13 $C.ink | Out-Null
AddText $s "wallet_balance += amount" 72 314 300 18 13 $C.ink $true | Out-Null
AddText $s "ledger: reason = topup" 72 350 300 18 13 $C.ink | Out-Null
AddShape $s $msoShapeRoundedRectangle 72 388 344 28 $C.white $C.red | Out-Null
AddText $s "ไม่มี payment status / charge id" 84 395 320 14 11 $C.red $true $ppAlignCenter | Out-Null
AddArrow $s 458 322 506 322 $C.orange 3 | Out-Null
AddText $s "replace + add" 452 284 60 26 9 $C.orange $true $ppAlignCenter | Out-Null
AddText $s "ข้อเสนอ" 540 176 120 20 15 $C.green $true | Out-Null
AddShape $s $msoShapeRoundedRectangle 524 210 388 224 $C.paleGreen -1 | Out-Null
AddText $s "POST /payments/create" 548 232 340 18 13 $C.blue $true | Out-Null
AddText $s "payment_transactions" 548 268 340 18 13 $C.ink $true | Out-Null
AddText $s "• internal_id / provider_charge_id" 548 298 340 16 12 $C.ink | Out-Null
AddText $s "• amount_satang / status / user_id" 548 324 340 16 12 $C.ink | Out-Null
AddText $s "POST /payments/webhook" 548 358 340 18 13 $C.blue $true | Out-Null
AddText $s "verified → wallet_ledger +1" 548 392 340 18 13 $C.green $true | Out-Null
AddShape $s $msoShapeRoundedRectangle 48 466 864 34 $C.darkTeal -1 | Out-Null
AddText $s "ทุกยอดผูกกับ Charge ID เดียว และเครดิต Wallet ได้สูงสุดครั้งเดียว" 64 475 832 16 13 $C.white $true $ppAlignCenter | Out-Null
AddNotes $s ("สไลด์นี้เป็นข้อเสนอ data/API ที่ต้องเพิ่ม: เก็บ payment transaction แยกจาก wallet ledger และใช้ amount หน่วยย่อย เช่น satang พร้อม provider charge id และสถานะ" + $nl + $nl + "[Sources]" + $nl + "- Local code: app/database.py:114-157, app/main.py:870-892" + $nl + "- Omise API keys and amounts: https://docs.omise.co/thailand" + $nl + "- Omise charge lifecycle: https://docs.omise.co/th/promptpay/thailand?version=2019-05-22")

# Slide 7: unchanged charging path
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddHeader $s "สิ่งที่ไม่เปลี่ยน: Charging Flow และการควบคุมเครื่อง" "NO CHANGE" 7
AddText $s "Omise จบหน้าที่ที่การยืนยันเงินเข้า จากนั้นระบบชาร์จยังทำงานตาม OCPP flow เดิม" 48 126 840 26 15 $C.muted | Out-Null
AddShape $s $msoShapeRoundedRectangle 48 180 864 76 $C.paleOrange -1 | Out-Null
AddText $s "Payment side" 72 198 120 18 12 $C.orange $true | Out-Null
AddText $s "PromptPay / Omise → Webhook verify → Wallet balance เพิ่ม" 228 198 638 20 15 $C.ink $true | Out-Null
AddShape $s $msoShapeRoundedRectangle 48 300 864 138 $C.paleBlue -1 | Out-Null
AddText $s "Charging side (เดิม)" 72 322 160 18 12 $C.blue $true | Out-Null
AddText $s "Wallet > 0" 72 370 104 22 15 $C.ink $true $ppAlignCenter | Out-Null
AddArrow $s 186 381 232 381 $C.teal 2 | Out-Null
AddText $s "Authorize" 242 370 102 22 15 $C.ink $true $ppAlignCenter | Out-Null
AddArrow $s 354 381 400 381 $C.teal 2 | Out-Null
AddText $s "Start" 410 370 72 22 15 $C.ink $true $ppAlignCenter | Out-Null
AddArrow $s 492 381 538 381 $C.teal 2 | Out-Null
AddText $s "MeterValues" 548 370 112 22 15 $C.ink $true $ppAlignCenter | Out-Null
AddArrow $s 670 381 716 381 $C.teal 2 | Out-Null
AddText $s "Stop" 726 370 64 22 15 $C.ink $true $ppAlignCenter | Out-Null
AddArrow $s 800 381 846 381 $C.teal 2 | Out-Null
AddText $s "หัก Wallet" 850 370 54 22 12 $C.ink $true $ppAlignCenter | Out-Null
AddShape $s $msoShapeRoundedRectangle 48 468 864 32 $C.paleGreen -1 | Out-Null
AddText $s "จุดเปลี่ยนมีแค่ตอนเติมเงิน: ไม่ต้องผูก Omise เข้ากับทุก session ของเครื่องชาร์จ" 64 477 832 16 12 $C.green $true $ppAlignCenter | Out-Null
AddNotes $s ("สไลด์นี้ช่วยจำกัด scope: OCPP central, authorization, StartTransaction, MeterValues, StopTransaction และการหัก Wallet ยังคงเป็นแกนเดิม เราเปลี่ยนเฉพาะ source ของเงินใน Wallet" + $nl + $nl + "[Sources]" + $nl + "- Local code: app/ocpp_handler.py:217-352, app/main.py:491-573")

# Slide 8: roadmap
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddHeader $s "Roadmap จาก mockup สู่เงินจริง" "DELIVERY ROADMAP" 8
AddText $s "ให้แต่ละระยะมีของที่เปิดให้ทดลองได้และเกณฑ์ผ่านก่อนเปิด Live" 48 126 840 26 15 $C.muted | Out-Null
AddRule $s 88 292 784 $C.rule 2 | Out-Null
AddShape $s $msoShapeOval 88 268 48 48 $C.teal -1 | Out-Null
AddText $s "01" 88 280 48 20 13 $C.white $true $ppAlignCenter | Out-Null
AddText $s "Mockup + model" 58 334 108 20 13 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "ยืนยันหน้าจอ${nl}และ payment states" 58 370 108 34 11 $C.muted $false $ppAlignCenter | Out-Null
AddShape $s $msoShapeOval 300 268 48 48 $C.blue -1 | Out-Null
AddText $s "02" 300 280 48 20 13 $C.white $true $ppAlignCenter | Out-Null
AddText $s "Test Mode" 270 334 108 20 13 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "Create charge${nl}QR + webhook" 270 370 108 34 11 $C.muted $false $ppAlignCenter | Out-Null
AddShape $s $msoShapeOval 512 268 48 48 $C.orange -1 | Out-Null
AddText $s "03" 512 280 48 20 13 $C.white $true $ppAlignCenter | Out-Null
AddText $s "Hardening" 482 334 108 20 13 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "integer amount${nl}idempotency${nl}reconciliation" 482 370 108 48 11 $C.muted $false $ppAlignCenter | Out-Null
AddShape $s $msoShapeOval 724 268 48 48 $C.green -1 | Out-Null
AddText $s "04" 724 280 48 20 13 $C.white $true $ppAlignCenter | Out-Null
AddText $s "Pilot → Live" 694 334 108 20 13 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "HTTPS webhook${nl}monitoring + owner" 694 370 108 34 11 $C.muted $false $ppAlignCenter | Out-Null
AddShape $s $msoShapeRoundedRectangle 48 468 864 32 $C.paleGreen -1 | Out-Null
AddText $s "เกณฑ์ผ่าน: เงินเข้า Wallet ครั้งเดียวต่อ Charge, trace ได้ครบ และปิด mock top-up ก่อนเปิดเงินจริง" 64 477 832 16 12 $C.green $true $ppAlignCenter | Out-Null
AddNotes $s ("Roadmap นี้ตั้งใจให้เห็นลำดับการลงทุน: เริ่มจากยืนยัน mockup และ state ก่อนลงมือเชื่อมจริง แล้วจึง harden ด้านเงินและ audit" + $nl + $nl + "[Sources]" + $nl + "- Local code: app/main.py:870-892, app/database.py:145-175" + $nl + "- Omise test/live accounts: https://docs.omise.co/thailand" + $nl + "- Omise webhook requirements: https://docs.omise.co/th/api-webhooks/thailand")

# Slide 9: decision
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddHeader $s "สิ่งที่ขออนุมัติ เพื่อเริ่มทำ mockup ให้เป็นของจริง" "DECISION" 9
AddShape $s $msoShapeRoundedRectangle 48 150 420 300 $C.darkTeal -1 | Out-Null
AddText $s "ข้อเสนอหลัก" 78 182 160 20 14 $C.orange $true | Out-Null
AddText $s "Prepaid Wallet" 78 224 320 34 27 $C.white $true | Out-Null
AddText $s "เติมเงินผ่าน Omise${nl}แล้วจึงใช้ Wallet ชาร์จ" 78 284 320 52 18 $C.white $false | Out-Null
AddRule $s 78 368 330 $C.orange 2 | Out-Null
AddText $s "PromptPay เป็นช่องทางแรกใน Test Mode" 78 388 330 34 13 $C.orange $true | Out-Null
AddText $s "รายการตัดสินใจ" 520 162 260 22 18 $C.ink $true | Out-Null
AddShape $s $msoShapeRoundedRectangle 520 208 26 26 $C.paleGreen $C.green | Out-Null
AddText $s "✓" 520 212 26 18 14 $C.green $true $ppAlignCenter | Out-Null
AddText $s "อนุมัติ payment model แบบ Prepaid Wallet" 560 210 330 20 14 $C.ink | Out-Null
AddShape $s $msoShapeRoundedRectangle 520 254 26 26 $C.paleGreen $C.green | Out-Null
AddText $s "✓" 520 258 26 18 14 $C.green $true $ppAlignCenter | Out-Null
AddText $s "เปิด Omise Test และยืนยันช่องทางชำระ" 560 256 330 20 14 $C.ink | Out-Null
AddShape $s $msoShapeRoundedRectangle 520 300 26 26 $C.paleGreen $C.green | Out-Null
AddText $s "✓" 520 304 26 18 14 $C.green $true $ppAlignCenter | Out-Null
AddText $s "ทำ webhook, audit และ reconciliation" 560 302 330 20 14 $C.ink | Out-Null
AddShape $s $msoShapeRoundedRectangle 520 346 26 26 $C.paleGreen $C.green | Out-Null
AddText $s "✓" 520 350 26 18 14 $C.green $true $ppAlignCenter | Out-Null
AddText $s "แต่งตั้ง owner การเงินและการกระทบยอด" 560 348 330 20 14 $C.ink | Out-Null
AddRule $s 520 404 370 $C.rule 1 | Out-Null
AddText $s "Next step" 520 424 90 18 12 $C.teal $true | Out-Null
AddText $s "ทำ clickable mockup + Test payment flow" 612 422 278 22 14 $C.teal $true | Out-Null
AddNotes $s ("สิ่งที่ต้องการจากผู้บริหารคือการอนุมัติทิศทางและขอบเขต: Prepaid Wallet, Omise Test, PromptPay เป็นช่องทางแรก และ production controls ก่อนเปิดเงินจริง" + $nl + $nl + "[Sources]" + $nl + "- Local code: app/main.py:524-573, app/ocpp_handler.py:317-352" + $nl + "- Omise PromptPay: https://docs.omise.co/th/promptpay/thailand?version=2019-05-22" + $nl + "- Omise webhooks: https://docs.omise.co/th/api-webhooks/thailand")

if (Test-Path -LiteralPath $pptxPath) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $pptxPath = Join-Path $outDir "EV_Charger_Omise_Executive_Mockup-$stamp.pptx"
  $pdfPath = Join-Path $outDir "EV_Charger_Omise_Executive_Mockup-$stamp.pdf"
}

$pres.SaveAs($pptxPath, $ppSaveAsOpenXMLPresentation)
$pres.SaveAs($pdfPath, $ppSaveAsPDF)
$slideCount = $pres.Slides.Count
for ($i = 1; $i -le $slideCount; $i++) {
  $pngPath = Join-Path $pngDir ("slide-{0:D2}.png" -f $i)
  $pres.Slides.Item($i).Export($pngPath, "PNG", 1600, 900)
}
$pres.Close()
$ppt.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($pres) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($ppt) | Out-Null
Write-Output "PPTX=$pptxPath"
Write-Output "PDF=$pdfPath"
Write-Output "PNG_DIR=$pngDir"
Write-Output "SLIDES=$slideCount"
