$ErrorActionPreference = "Stop"

$outDir = Join-Path (Get-Location) "presentation_output_executive"
[System.IO.Directory]::CreateDirectory($outDir) | Out-Null
$pptxPath = Join-Path $outDir "EV_Charger_Omise_Executive_Story.pptx"
$pdfPath = Join-Path $outDir "EV_Charger_Omise_Executive_Story.pdf"
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
  darkTeal = (Rgb 5 76 88)
  blue = (Rgb 47 128 237)
  orange = (Rgb 242 153 74)
  green = (Rgb 43 138 62)
  red = (Rgb 201 76 76)
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

$ppt = New-Object -ComObject PowerPoint.Application
$ppt.Visible = -1
$pres = $ppt.Presentations.Add()
$pres.PageSetup.SlideWidth = 960
$pres.PageSetup.SlideHeight = 540

# Slide 1: executive decision
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddShape $s $msoShapeRectangle 0 0 16 540 $C.teal -1 | Out-Null
AddText $s "EV CHARGER PLATFORM" 58 48 280 18 11 $C.teal $true | Out-Null
AddText $s "เปลี่ยนการเติมเงินให้เป็นเงินจริง" 58 106 520 44 31 $C.ink $true | Out-Null
AddText $s "จาก Wallet แบบทดสอบ${nl}สู่การชำระผ่าน Omise แล้วใช้ชาร์จได้จริง" 58 166 520 70 22 $C.ink $false | Out-Null
AddShape $s $msoShapeRoundedRectangle 58 282 492 78 $C.darkTeal -1 | Out-Null
AddText $s "ขออนุมัติวันนี้" 84 298 150 18 12 $C.orange $true | Out-Null
AddText $s "Prepaid Wallet + Omise" 84 324 420 24 19 $C.white $true | Out-Null
AddText $s "OCPP / ระบบชาร์จเดิมยังคงทำงานเหมือนเดิม" 58 402 492 24 14 $C.muted | Out-Null
AddText $s "EXECUTIVE STORY" 58 468 220 18 11 $C.muted $true | Out-Null

AddBrowserFrame $s 620 92 270 342 "ภาพปลายทาง: เติมเงินเข้า Wallet" $C.green
AddShape $s $msoShapeRoundedRectangle 636 134 64 284 $C.darkTeal -1 | Out-Null
AddText $s "⚡" 648 154 40 24 20 $C.white $true $ppAlignCenter | Out-Null
AddText $s "หน้าหลัก" 644 206 48 14 8 $C.white $false $ppAlignCenter | Out-Null
AddText $s "Wallet" 644 240 48 14 8 $C.orange $true $ppAlignCenter | Out-Null
AddText $s "ชาร์จ" 644 274 48 14 8 $C.white $false $ppAlignCenter | Out-Null
AddText $s "เติมเงินเข้า Wallet" 722 150 148 18 13 $C.ink $true | Out-Null
AddText $s "ยอดคงเหลือ" 722 194 100 12 9 $C.muted | Out-Null
AddText $s "฿500.00" 722 210 130 30 22 $C.green $true | Out-Null
AddText $s "ช่องทางชำระเงิน" 722 262 120 12 9 $C.muted | Out-Null
AddShape $s $msoShapeRoundedRectangle 722 280 138 28 $C.paleBlue $C.blue | Out-Null
AddText $s "PromptPay" 732 288 118 14 11 $C.blue $true $ppAlignCenter | Out-Null
AddShape $s $msoShapeRoundedRectangle 722 328 138 34 $C.orange -1 | Out-Null
AddText $s "ชำระเงิน" 732 338 118 14 11 $C.white $true $ppAlignCenter | Out-Null
AddNotes $s ("เป้าหมายของโครงการในภาษาผู้บริหาร: เปลี่ยนการเติมเงินจาก mock ให้เป็นการชำระเงินจริงผ่าน Omise และคงระบบชาร์จเดิมไว้" + $nl + $nl + "[Sources]" + $nl + "- Local code: app/static/index.html:164-196, app/main.py:870-892" + $nl + "- Omise overview: https://docs.omise.co/thailand")

# Slide 2: visible user experience
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddHeader $s "ผู้ใช้จะเห็นประสบการณ์ใหม่แบบนี้" "USER EXPERIENCE" 2
AddText $s "ผู้ใช้เห็นสถานะชัดเจนว่าเงินอยู่ขั้นตอนไหน จนกว่าจะยืนยันสำเร็จจึงจะเข้า Wallet" 48 126 840 26 15 $C.muted | Out-Null

AddShape $s $msoShapeRoundedRectangle 48 178 268 290 $C.white $C.rule | Out-Null
AddShape $s $msoShapeOval 150 158 42 42 $C.teal -1 | Out-Null
AddText $s "1" 150 168 42 18 13 $C.white $true $ppAlignCenter | Out-Null
AddText $s "เลือกยอดเติมเงิน" 78 210 208 24 17 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "ยอดที่ต้องการ" 86 250 190 16 10 $C.muted $false $ppAlignCenter | Out-Null
AddText $s "฿500" 86 270 190 30 24 $C.teal $true $ppAlignCenter | Out-Null
AddShape $s $msoShapeRoundedRectangle 86 324 86 30 $C.paleGray $C.rule | Out-Null
AddText $s "฿100" 86 333 86 12 11 $C.ink $false $ppAlignCenter | Out-Null
AddShape $s $msoShapeRoundedRectangle 182 324 86 30 $C.paleBlue $C.blue | Out-Null
AddText $s "฿500" 182 333 86 12 11 $C.blue $true $ppAlignCenter | Out-Null
AddShape $s $msoShapeRoundedRectangle 86 376 182 36 $C.orange -1 | Out-Null
AddText $s "ไปขั้นตอนชำระเงิน" 94 386 166 14 11 $C.white $true $ppAlignCenter | Out-Null

AddArrow $s 330 322 366 322 $C.teal 3 | Out-Null
AddShape $s $msoShapeRoundedRectangle 386 178 268 290 $C.paleOrange -1 | Out-Null
AddShape $s $msoShapeOval 488 158 42 42 $C.orange -1 | Out-Null
AddText $s "2" 488 168 42 18 13 $C.white $true $ppAlignCenter | Out-Null
AddText $s "ชำระผ่าน Omise" 416 210 208 24 17 $C.ink $true $ppAlignCenter | Out-Null
AddShape $s $msoShapeRectangle 486 254 68 68 $C.white $C.rule | Out-Null
AddText $s "QR" 486 278 68 20 18 $C.blue $true $ppAlignCenter | Out-Null
AddText $s "PromptPay" 416 340 208 18 13 $C.orange $true $ppAlignCenter | Out-Null
AddText $s "สถานะ: รอการชำระเงิน" 416 384 208 18 12 $C.muted $false $ppAlignCenter | Out-Null
AddText $s "ยังไม่เครดิตเข้า Wallet" 416 414 208 16 10 $C.red $true $ppAlignCenter | Out-Null

AddArrow $s 668 322 704 322 $C.orange 3 | Out-Null
AddShape $s $msoShapeRoundedRectangle 724 178 188 290 $C.paleGreen -1 | Out-Null
AddShape $s $msoShapeOval 797 158 42 42 $C.green -1 | Out-Null
AddText $s "3" 797 168 42 18 13 $C.white $true $ppAlignCenter | Out-Null
AddText $s "เงินเข้า Wallet" 744 210 148 24 17 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "ชำระเงินสำเร็จ" 744 258 148 18 12 $C.green $true $ppAlignCenter | Out-Null
AddText $s "฿500.00" 744 286 148 30 23 $C.green $true $ppAlignCenter | Out-Null
AddShape $s $msoShapeRoundedRectangle 748 350 140 36 $C.green -1 | Out-Null
AddText $s "พร้อมใช้งานชาร์จ" 754 360 128 14 10 $C.white $true $ppAlignCenter | Out-Null
AddNotes $s ("สไลด์นี้คือหน้าจอที่ควรใช้คุยกับผู้บริหาร เพราะเห็นผลลัพธ์เชิงประสบการณ์โดยตรง: เลือกยอด → ชำระ → เงินเข้า Wallet. หน้าจอเป็น proposed mockup ไม่ใช่ UI ที่ implement แล้ว" + $nl + $nl + "[Sources]" + $nl + "- Local code: app/static/index.html:164-196" + $nl + "- Omise PromptPay lifecycle: https://docs.omise.co/th/promptpay/thailand?version=2019-05-22")

# Slide 3: change vs no change
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddHeader $s "เราเปลี่ยนที่จุดเติมเงิน ไม่ใช่ที่จุดชาร์จ" "SCOPE" 3
AddText $s "การลงทุนอยู่ที่ payment experience และการยืนยันเงิน ส่วน OCPP charging flow เดิมยังใช้ต่อได้" 48 126 840 26 15 $C.muted | Out-Null

AddText $s "สิ่งที่เพิ่ม" 64 178 180 22 17 $C.orange $true | Out-Null
AddShape $s $msoShapeRoundedRectangle 48 216 392 184 $C.paleOrange -1 | Out-Null
AddText $s "หน้าจอเติมเงินจริง" 76 242 320 22 16 $C.ink $true | Out-Null
AddText $s "เลือกช่องทางชำระเงิน${nl}เห็น QR / สถานะ pending${nl}เห็นผลสำเร็จจาก Omise${nl}เครดิต Wallet เมื่อยืนยันแล้ว" 76 282 320 86 15 $C.ink | Out-Null
AddShape $s $msoShapeRoundedRectangle 76 372 320 18 $C.orange -1 | Out-Null
AddText $s "Omise + Payment status + Wallet ledger" 84 375 304 12 10 $C.white $true $ppAlignCenter | Out-Null

AddText $s "สิ่งที่คงเดิม" 520 178 180 22 17 $C.teal $true | Out-Null
AddShape $s $msoShapeRoundedRectangle 504 216 408 184 $C.paleBlue -1 | Out-Null
AddText $s "ระบบควบคุมเครื่องชาร์จ" 532 242 350 22 16 $C.ink $true | Out-Null
AddText $s "Authorize${nl}Start / Stop${nl}MeterValues${nl}คำนวณและหักค่าไฟจาก Wallet" 532 282 350 86 15 $C.ink | Out-Null
AddShape $s $msoShapeRoundedRectangle 532 372 350 18 $C.teal -1 | Out-Null
AddText $s "OCPP 1.6J + Charging session เดิม" 540 375 334 12 10 $C.white $true $ppAlignCenter | Out-Null

AddShape $s $msoShapeRoundedRectangle 48 446 864 42 $C.darkTeal -1 | Out-Null
AddText $s "จุดเปลี่ยนมีจุดเดียว: เงินเข้า Wallet ต้องมาจากการชำระที่ยืนยันแล้ว" 64 457 832 18 14 $C.white $true $ppAlignCenter | Out-Null
AddNotes $s ("สื่อสารขอบเขตให้ผู้บริหารเห็นว่าความเสี่ยงถูกจำกัด: เพิ่ม payment layer ที่จุดเติมเงิน แต่ไม่รื้อ charging flow ที่มีอยู่" + $nl + $nl + "[Sources]" + $nl + "- Local code: app/ocpp_handler.py:217-352" + $nl + "- Local code: app/main.py:491-573, 870-892" + $nl + "- Local code: app/database.py:145-175")

# Slide 4: money flow
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddHeader $s "เงินจะเดินทางตามลำดับนี้" "MONEY FLOW" 4
AddText $s "ทุกขั้นมีสถานะกำกับ และเงินจะไม่ถูกใช้ชาร์จก่อนระบบยืนยันผลสำเร็จ" 48 126 840 26 15 $C.muted | Out-Null

AddShape $s $msoShapeOval 72 222 70 70 $C.teal -1 | Out-Null
AddText $s "1" 72 242 70 26 18 $C.white $true $ppAlignCenter | Out-Null
AddText $s "ลูกค้า" 54 314 106 22 16 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "เลือกยอดเติม" 54 348 106 18 12 $C.muted $false $ppAlignCenter | Out-Null
AddArrow $s 152 257 214 257 $C.teal 3 | Out-Null

AddShape $s $msoShapeOval 224 222 70 70 $C.blue -1 | Out-Null
AddText $s "2" 224 242 70 26 18 $C.white $true $ppAlignCenter | Out-Null
AddText $s "EV App" 206 314 106 22 16 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "สร้างรายการ" 206 348 106 18 12 $C.muted $false $ppAlignCenter | Out-Null
AddArrow $s 304 257 366 257 $C.blue 3 | Out-Null

AddShape $s $msoShapeOval 376 222 70 70 $C.orange -1 | Out-Null
AddText $s "3" 376 242 70 26 18 $C.white $true $ppAlignCenter | Out-Null
AddText $s "Omise" 358 314 106 22 16 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "ชำระ / QR" 358 348 106 18 12 $C.muted $false $ppAlignCenter | Out-Null
AddArrow $s 456 257 518 257 $C.orange 3 | Out-Null

AddShape $s $msoShapeOval 528 222 70 70 $C.green -1 | Out-Null
AddText $s "4" 528 242 70 26 18 $C.white $true $ppAlignCenter | Out-Null
AddText $s "ยืนยันผล" 510 314 106 22 16 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "ตรวจแล้ว / กันซ้ำ" 510 348 106 18 12 $C.muted $false $ppAlignCenter | Out-Null
AddArrow $s 608 257 670 257 $C.green 3 | Out-Null

AddShape $s $msoShapeOval 680 222 70 70 $C.darkTeal -1 | Out-Null
AddText $s "5" 680 242 70 26 18 $C.white $true $ppAlignCenter | Out-Null
AddText $s "Wallet" 662 314 106 22 16 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "เครดิตแล้วใช้ชาร์จ" 654 348 122 18 12 $C.muted $false $ppAlignCenter | Out-Null

AddShape $s $msoShapeRoundedRectangle 48 420 864 54 $C.paleGreen -1 | Out-Null
AddText $s "กติกาเดียวที่ต้องจำ: หน้า redirect บอกแค่ผู้ใช้กลับมา แต่ webhook/การตรวจสอบคือหลักฐานว่าเงินสำเร็จ" 64 436 832 20 13 $C.green $true $ppAlignCenter | Out-Null
AddNotes $s ("นี่คือ business flow ของเงิน ไม่ใช่ technical sequence: ลูกค้าจ่าย → Omise แจ้งผล → ระบบตรวจสอบ → Wallet พร้อมใช้. ต้องไม่เครดิตจากหน้า redirect เพียงอย่างเดียว" + $nl + $nl + "[Sources]" + $nl + "- Omise PromptPay: https://docs.omise.co/th/promptpay/thailand?version=2019-05-22" + $nl + "- Omise webhooks: https://docs.omise.co/th/api-webhooks/thailand")

# Slide 5: roadmap
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddHeader $s "จากภาพ mockup สู่การเปิดเงินจริง" "ROADMAP" 5
AddText $s "แต่ละระยะมีของให้ทดลองและเกณฑ์ผ่านก่อนขยับไปขั้นถัดไป" 48 126 840 26 15 $C.muted | Out-Null
AddRule $s 92 274 776 $C.rule 2 | Out-Null

AddShape $s $msoShapeOval 84 250 50 50 $C.teal -1 | Out-Null
AddText $s "01" 84 264 50 20 13 $C.white $true $ppAlignCenter | Out-Null
AddText $s "ยืนยัน Mockup" 52 324 114 22 14 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "หน้าจอ + สถานะ${nl}ที่ผู้ใช้เห็น" 52 364 114 38 12 $C.muted $false $ppAlignCenter | Out-Null

AddShape $s $msoShapeOval 294 250 50 50 $C.blue -1 | Out-Null
AddText $s "02" 294 264 50 20 13 $C.white $true $ppAlignCenter | Out-Null
AddText $s "เชื่อม Test" 262 324 114 22 14 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "PromptPay${nl}และ webhook" 262 364 114 38 12 $C.muted $false $ppAlignCenter | Out-Null

AddShape $s $msoShapeOval 504 250 50 50 $C.orange -1 | Out-Null
AddText $s "03" 504 264 50 20 13 $C.white $true $ppAlignCenter | Out-Null
AddText $s "ทำให้พร้อมจริง" 466 324 126 22 14 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "กันซ้ำ + audit${nl}กระทบยอด" 466 364 126 38 12 $C.muted $false $ppAlignCenter | Out-Null

AddShape $s $msoShapeOval 714 250 50 50 $C.green -1 | Out-Null
AddText $s "04" 714 264 50 20 13 $C.white $true $ppAlignCenter | Out-Null
AddText $s "Pilot → Live" 680 324 118 22 14 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "เปิดกลุ่มเล็ก${nl}monitoring + owner" 680 364 118 38 12 $C.muted $false $ppAlignCenter | Out-Null

AddShape $s $msoShapeRoundedRectangle 48 448 864 44 $C.darkTeal -1 | Out-Null
AddText $s "ไม่เปิดเงินจริงจนกว่า: เงินเข้า Wallet ครั้งเดียวต่อรายการ และตรวจสอบย้อนหลังได้" 64 460 832 20 13 $C.white $true $ppAlignCenter | Out-Null
AddNotes $s ("Roadmap นี้ช่วยให้ผู้บริหารเห็นลำดับการตัดสินใจและลดความเสี่ยง: เริ่มจาก mockup ก่อน, ทดสอบใน Test Mode, ทำ controls, แล้วค่อย pilot" + $nl + $nl + "[Sources]" + $nl + "- Local code: app/main.py:870-892, app/database.py:145-175" + $nl + "- Omise test/live accounts: https://docs.omise.co/thailand")

# Slide 6: decision
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddHeader $s "มติที่ต้องการจากผู้บริหาร" "DECISION" 6
AddShape $s $msoShapeRoundedRectangle 48 154 410 278 $C.darkTeal -1 | Out-Null
AddText $s "ข้อเสนอ" 78 184 120 20 14 $C.orange $true | Out-Null
AddText $s "Prepaid Wallet" 78 224 330 34 28 $C.white $true | Out-Null
AddText $s "เติมเงินผ่าน Omise${nl}แล้วจึงใช้ Wallet ชาร์จ" 78 284 320 54 18 $C.white | Out-Null
AddRule $s 78 370 320 $C.orange 2 | Out-Null
AddText $s "PromptPay เป็นช่องทางแรกใน Test Mode" 78 388 320 24 13 $C.orange $true | Out-Null

AddText $s "ขออนุมัติ 3 เรื่อง" 520 164 300 24 18 $C.ink $true | Out-Null
AddShape $s $msoShapeRoundedRectangle 520 214 32 32 $C.paleGreen $C.green | Out-Null
AddText $s "1" 520 221 32 18 13 $C.green $true $ppAlignCenter | Out-Null
AddText $s "ทิศทางการเงิน: Prepaid Wallet" 574 218 310 24 15 $C.ink $true | Out-Null
AddShape $s $msoShapeRoundedRectangle 520 270 32 32 $C.paleGreen $C.green | Out-Null
AddText $s "2" 520 277 32 18 13 $C.green $true $ppAlignCenter | Out-Null
AddText $s "เริ่มเชื่อม Omise ใน Test Mode" 574 274 310 24 15 $C.ink $true | Out-Null
AddShape $s $msoShapeRoundedRectangle 520 326 32 32 $C.paleGreen $C.green | Out-Null
AddText $s "3" 520 333 32 18 13 $C.green $true $ppAlignCenter | Out-Null
AddText $s "ขอบเขต: เปลี่ยนเฉพาะจุดเติมเงิน" 574 330 310 24 15 $C.ink $true | Out-Null
AddRule $s 520 394 364 $C.rule 1 | Out-Null
AddText $s "เริ่มทำต่อทันที" 520 414 126 18 12 $C.teal $true | Out-Null
AddText $s "ทำ clickable mockup + Test payment flow" 648 412 242 24 14 $C.teal $true | Out-Null
AddNotes $s ("สไลด์สุดท้ายต้องตอบให้ชัดว่าผู้บริหารต้องอนุมัติอะไร: รูปแบบ Prepaid Wallet, การเปิด Omise Test และ scope ที่ไม่รื้อ charging flow" + $nl + $nl + "[Sources]" + $nl + "- Local code: app/main.py:524-573, app/ocpp_handler.py:317-352" + $nl + "- Omise PromptPay: https://docs.omise.co/th/promptpay/thailand?version=2019-05-22")

if (Test-Path -LiteralPath $pptxPath) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $pptxPath = Join-Path $outDir "EV_Charger_Omise_Executive_Story-$stamp.pptx"
  $pdfPath = Join-Path $outDir "EV_Charger_Omise_Executive_Story-$stamp.pdf"
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
