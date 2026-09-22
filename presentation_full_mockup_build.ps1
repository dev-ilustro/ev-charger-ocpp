$ErrorActionPreference = "Stop"

$outDir = Join-Path (Get-Location) "presentation_output_actual_screenshots"
[System.IO.Directory]::CreateDirectory($outDir) | Out-Null
$pptxPath = Join-Path $outDir "EV_Charger_Actual_UI_Screenshots_User_Journey.pptx"
$pdfPath = Join-Path $outDir "EV_Charger_Actual_UI_Screenshots_User_Journey.pdf"
$pngDir = Join-Path $outDir "rendered"
[System.IO.Directory]::CreateDirectory($pngDir) | Out-Null
$nl = [char]10
$screenDir = Join-Path (Get-Location) "presentation_capture\screens"
$loginPng = Join-Path $screenDir "01-login.png"
$homePng = Join-Path $screenDir "02-home.png"
$walletPng = Join-Path $screenDir "03-settings-wallet.png"
$detailPng = Join-Path $screenDir "04-charger-detail.png"
$transactionsPng = Join-Path $screenDir "05-transactions.png"
foreach ($requiredScreenshot in @($loginPng, $homePng, $walletPng, $detailPng, $transactionsPng)) {
  if (-not (Test-Path -LiteralPath $requiredScreenshot)) {
    throw "ไม่พบ screenshot จากระบบจริง: $requiredScreenshot"
  }
}

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

function AddActualScreenshot($slide, [string]$path, [double]$left, [double]$top, [double]$width, [double]$height, [string]$caption, [int]$captionColor) {
  AddBrowserFrame $slide $left $top $width $height $caption $captionColor
  $pic = $slide.Shapes.AddPicture($path, 0, -1, ($left + 3), ($top + 29), ($width - 6), ($height - 32))
  $pic.LockAspectRatio = -1
  $pic.Width = $width - 6
  $pic.Left = $left + 3
  $pic.Top = $top + 29
}

function AddActualImage($slide, [string]$path, [double]$left, [double]$top, [double]$width, [double]$height) {
  $pic = $slide.Shapes.AddPicture($path, 0, -1, $left, $top, $width, $height)
  $pic.LockAspectRatio = 0
  $pic.Line.Visible = -1
  $pic.Line.ForeColor.RGB = $C.rule
  $pic.Line.Weight = 1
  return $pic
}

$ppt = New-Object -ComObject PowerPoint.Application
$ppt.Visible = -1
$pres = $ppt.Presentations.Add()
$pres.PageSetup.SlideWidth = 960
$pres.PageSetup.SlideHeight = 540

# Slide 1: cover
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddShape $s $msoShapeRectangle 0 0 16 540 $C.teal -1 | Out-Null
AddText $s "EV CHARGER PLATFORM" 58 48 280 18 11 $C.teal $true | Out-Null
AddText $s "ภาพรวมระบบที่เราจะทำให้ผู้ใช้เห็น" 58 108 540 44 29 $C.ink $true | Out-Null
AddText $s "ตั้งแต่ Login จนเติมเงินเข้า Wallet${nl}แล้วนำไปใช้ชาร์จรถ" 58 170 520 68 22 $C.ink | Out-Null
AddShape $s $msoShapeRoundedRectangle 58 286 492 78 $C.darkTeal -1 | Out-Null
AddText $s "แนวทาง" 84 302 110 18 12 $C.orange $true | Out-Null
AddText $s "ทำ Mockup ให้เห็นก่อน แล้วค่อยต่อระบบจริง" 84 328 430 22 17 $C.white $true | Out-Null
AddText $s "Login  →  Dashboard  →  Wallet  →  Omise  →  ชาร์จ" 58 410 520 24 14 $C.muted $true | Out-Null
AddText $s "EXECUTIVE USER JOURNEY" 58 468 260 18 11 $C.muted $true | Out-Null

AddActualImage $s $homePng 612 96 300 220 | Out-Null
AddText $s "ภาพจากระบบจริง" 612 328 300 18 11 $C.teal $true $ppAlignCenter | Out-Null
AddNotes $s ("ภาพหลักของสไลด์นี้เป็น screenshot จากระบบจริง เพื่อให้เห็นหน้าตาและบริบทของระบบก่อนเข้าสู่ user journey ที่จะเพิ่ม Payment/Omise" + $nl + $nl + "[Sources]" + $nl + "- Local screenshot: presentation_capture/screens/02-home.png" + $nl + "- Local code: app/static/login.html, app/static/index.html:26-196")

# Slide 2: full flow
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddHeader $s "ภาพรวมการใช้งานทั้งเส้นของลูกค้า" "FULL USER FLOW" 2
AddText $s "ให้ผู้บริหารเห็นตั้งแต่ผู้ใช้เข้าระบบ จนเงินเข้า Wallet และพร้อมเริ่มชาร์จ" 48 126 840 26 15 $C.muted | Out-Null

AddRule $s 86 286 788 $C.rule 2 | Out-Null
AddShape $s $msoShapeOval 60 260 52 52 $C.teal -1 | Out-Null
AddText $s "01" 60 276 52 18 12 $C.white $true $ppAlignCenter | Out-Null
AddText $s "Login" 48 330 76 20 14 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "ยืนยันตัวตน" 42 360 88 18 11 $C.muted $false $ppAlignCenter | Out-Null

AddArrow $s 118 286 170 286 $C.teal 2 | Out-Null
AddShape $s $msoShapeOval 174 260 52 52 $C.blue -1 | Out-Null
AddText $s "02" 174 276 52 18 12 $C.white $true $ppAlignCenter | Out-Null
AddText $s "Dashboard" 158 330 84 20 14 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "เห็นเครื่องชาร์จ" 152 360 96 18 11 $C.muted $false $ppAlignCenter | Out-Null

AddArrow $s 232 286 284 286 $C.blue 2 | Out-Null
AddShape $s $msoShapeOval 288 260 52 52 $C.teal -1 | Out-Null
AddText $s "03" 288 276 52 18 12 $C.white $true $ppAlignCenter | Out-Null
AddText $s "Wallet" 274 330 80 20 14 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "ดูยอด / เติมเงิน" 268 360 92 18 11 $C.muted $false $ppAlignCenter | Out-Null

AddArrow $s 346 286 398 286 $C.teal 2 | Out-Null
AddShape $s $msoShapeOval 402 260 52 52 $C.orange -1 | Out-Null
AddText $s "04" 402 276 52 18 12 $C.white $true $ppAlignCenter | Out-Null
AddText $s "ชำระเงิน" 388 330 80 20 14 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "ผ่าน Omise" 384 360 88 18 11 $C.muted $false $ppAlignCenter | Out-Null

AddArrow $s 460 286 512 286 $C.orange 2 | Out-Null
AddShape $s $msoShapeOval 516 260 52 52 $C.green -1 | Out-Null
AddText $s "05" 516 276 52 18 12 $C.white $true $ppAlignCenter | Out-Null
AddText $s "ยืนยันผล" 502 330 80 20 14 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "เงินสำเร็จ" 500 360 84 18 11 $C.muted $false $ppAlignCenter | Out-Null

AddArrow $s 574 286 626 286 $C.green 2 | Out-Null
AddShape $s $msoShapeOval 630 260 52 52 $C.darkTeal -1 | Out-Null
AddText $s "06" 630 276 52 18 12 $C.white $true $ppAlignCenter | Out-Null
AddText $s "Wallet +" 612 330 88 20 14 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "เครดิตยอดเงิน" 606 360 100 18 11 $C.muted $false $ppAlignCenter | Out-Null

AddArrow $s 688 286 740 286 $C.darkTeal 2 | Out-Null
AddShape $s $msoShapeOval 744 260 52 52 $C.teal -1 | Out-Null
AddText $s "07" 744 276 52 18 12 $C.white $true $ppAlignCenter | Out-Null
AddText $s "เริ่มชาร์จ" 730 330 80 20 14 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "ใช้ Wallet" 728 360 84 18 11 $C.muted $false $ppAlignCenter | Out-Null

AddShape $s $msoShapeRoundedRectangle 48 430 864 46 $C.paleGreen -1 | Out-Null
AddText $s "เป้าหมายของ Mockup: เห็นภาพประสบการณ์ผู้ใช้ครบ ก่อนเริ่มแก้ code และต่อ Omise จริง" 64 444 832 20 14 $C.green $true $ppAlignCenter | Out-Null
AddNotes $s ("สไลด์นี้เป็นภาพรวมที่ควรใช้เป็นหน้าหลักในการนำเสนอ: เป็น flow เดียวตั้งแต่ login ถึง charging และช่วยให้ทีมเห็นว่าจุดที่เพิ่มคือขั้นตอนชำระเงินก่อนเครดิต Wallet" + $nl + $nl + "[Sources]" + $nl + "- Local code: app/static/login.html, app/static/index.html, app/main.py:524-573" + $nl + "- Local code: app/ocpp_handler.py:217-352")

# Slide 3: actual login and home screenshots
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddHeader $s "หน้าจอจริง 1: Login → หน้าแรก" "ACTUAL SYSTEM" 3
AddText $s "หน้าจอจริงจากระบบที่รันอยู่" 48 120 840 18 12 $C.muted | Out-Null

AddText $s "01  Login" 48 140 400 18 12 $C.teal $true | Out-Null
AddActualImage $s $loginPng 48 160 420 309 | Out-Null
AddText $s "02  Home / Charger" 492 140 420 18 12 $C.blue $true | Out-Null
AddActualImage $s $homePng 492 160 420 309 | Out-Null
AddNotes $s ("นี่คือ screenshot จากระบบจริง: หน้า login และหน้า Home ของ customer หลัง login. เครื่องที่เห็นคือ yc0117126030096 จากฐานข้อมูล manual" + $nl + $nl + "[Sources]" + $nl + "- Local screenshot: presentation_capture/screens/01-login.png" + $nl + "- Local screenshot: presentation_capture/screens/02-home.png" + $nl + "- Local code: app/static/login.html, app/static/index.html, app/static/app.js")

# Slide 4: actual wallet screenshot
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddHeader $s "หน้าจอจริง 2: Wallet ปัจจุบัน" "ACTUAL SYSTEM" 4
AddText $s "ภาพจริงของ Wallet และจุดที่ต้องเปลี่ยน" 48 120 840 18 12 $C.muted | Out-Null

AddText $s "03  Settings / Wallet จริง" 48 140 420 18 12 $C.green $true | Out-Null
AddActualImage $s $walletPng 48 160 440 386 | Out-Null

AddText $s "สิ่งที่มีอยู่แล้ว" 536 166 350 24 20 $C.ink $true | Out-Null
AddRule $s 536 204 350 $C.rule 1 | Out-Null
AddText $s "ยอดคงเหลือ  ฿141.20" 536 232 350 24 17 $C.green $true | Out-Null
AddText $s "ตั้งงบชาร์จได้" 536 286 350 22 16 $C.teal $true | Out-Null
AddText $s "เติมเงินยังเป็นโหมดทดสอบ" 536 340 350 22 16 $C.red $true | Out-Null
AddText $s "เพิ่ม Payment + สถานะ" 536 408 350 22 16 $C.orange $true | Out-Null
AddText $s "เครดิต Wallet หลังยืนยันสำเร็จ" 536 444 350 20 13 $C.muted | Out-Null
AddNotes $s ("นี่คือ screenshot จากหน้า Settings/Wallet จริงของระบบ. Wallet และการตั้งงบมีอยู่แล้ว แต่ self-service top-up ยังเป็น mock และถูกทำเครื่องหมายไว้ใน UI" + $nl + $nl + "[Sources]" + $nl + "- Local screenshot: presentation_capture/screens/03-settings-wallet.png" + $nl + "- Local code: app/static/index.html:164-196" + $nl + "- Local code: app/static/app.js:159-178" + $nl + "- Local code: app/main.py:870-892")

# Slide 5: actual charger detail and transaction screenshots
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddHeader $s "หน้าจอจริง 3: รายละเอียดเครื่องและประวัติ" "ACTUAL SYSTEM" 5
AddText $s "ภาพจริงของส่วนควบคุมเครื่องและประวัติการชาร์จ" 48 120 850 18 12 $C.muted | Out-Null

AddText $s "04  Charger Detail" 48 140 400 18 12 $C.teal $true | Out-Null
AddActualImage $s $detailPng 48 160 420 309 | Out-Null
AddText $s "05  Transactions" 492 140 420 18 12 $C.blue $true | Out-Null
AddActualImage $s $transactionsPng 492 160 420 309 | Out-Null
AddNotes $s ("นี่คือ screenshot จากหน้ารายละเอียดเครื่องและประวัติการชาร์จจริง. สองส่วนนี้เป็น OCPP operational flow เดิม ไม่ควรผูกเข้ากับ payment gateway โดยตรง" + $nl + $nl + "[Sources]" + $nl + "- Local screenshot: presentation_capture/screens/04-charger-detail.png" + $nl + "- Local screenshot: presentation_capture/screens/05-transactions.png" + $nl + "- Local code: app/static/index.html, app/static/app.js, app/ocpp_handler.py")

# Slide 6: proposed wallet to charging flow
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddHeader $s "Mockup ที่จะเพิ่ม: Payment → Omise → Wallet → ชาร์จ" "PROPOSED ADDITION" 6
AddText $s "ส่วนนี้ยังไม่มีภาพจากระบบจริง เพราะเป็นหน้าจอใหม่ที่ต้องออกแบบและพัฒนาต่อ" 48 126 850 26 15 $C.muted | Out-Null

AddBrowserFrame $s 48 184 404 260 "06  Wallet สำเร็จ (เสนอเพิ่ม)" $C.green
AddText $s "กระเป๋าเงินของฉัน" 78 226 300 20 15 $C.ink $true | Out-Null
AddShape $s $msoShapeRoundedRectangle 78 266 344 70 $C.paleGreen -1 | Out-Null
AddText $s "ยอดคงเหลือ" 96 280 130 14 9 $C.muted | Out-Null
AddText $s "฿500.00" 96 298 170 28 22 $C.green $true | Out-Null
AddText $s "รายการล่าสุด: เติมเงินสำเร็จ" 96 344 300 18 11 $C.green $true | Out-Null
AddShape $s $msoShapeRoundedRectangle 78 378 164 30 $C.white $C.rule | Out-Null
AddText $s "ตั้งงบชาร์จ" 88 386 144 14 10 $C.teal $true $ppAlignCenter | Out-Null
AddShape $s $msoShapeRoundedRectangle 258 378 164 30 $C.teal -1 | Out-Null
AddText $s "ไปเลือกเครื่อง" 268 386 144 14 10 $C.white $true $ppAlignCenter | Out-Null

AddArrow $s 470 314 520 314 $C.teal 3 | Out-Null
AddText $s "ใช้ยอดที่ยืนยันแล้ว" 466 270 58 30 9 $C.teal $true $ppAlignCenter | Out-Null

AddBrowserFrame $s 538 184 374 260 "07  Charger พร้อมเริ่ม (ของเดิม)" $C.teal
AddText $s "เครื่องชาร์จ: yc0117126030096" 562 226 314 20 14 $C.ink $true | Out-Null
AddShape $s $msoShapeRoundedRectangle 562 268 326 66 $C.paleBlue -1 | Out-Null
AddText $s "Available" 580 282 120 20 15 $C.green $true | Out-Null
AddText $s "Wallet ฿500.00  •  งบ session ฿100" 580 308 280 16 11 $C.muted | Out-Null
AddShape $s $msoShapeRoundedRectangle 562 360 156 30 $C.teal -1 | Out-Null
AddText $s "เริ่มชาร์จ" 572 368 136 14 11 $C.white $true $ppAlignCenter | Out-Null
AddShape $s $msoShapeRoundedRectangle 732 360 156 30 $C.white $C.rule | Out-Null
AddText $s "ดูรายละเอียด" 742 368 136 14 11 $C.teal $true $ppAlignCenter | Out-Null

AddShape $s $msoShapeRoundedRectangle 48 466 864 32 $C.darkTeal -1 | Out-Null
AddText $s "Wallet > 0  →  Authorize  →  Start  →  MeterValues  →  Stop  →  หักค่าไฟ" 64 475 832 16 13 $C.white $true $ppAlignCenter | Out-Null
AddNotes $s ("หน้าจอฝั่งซ้ายเป็น proposed mockup เพราะระบบจริงยังไม่มี payment flow. หลัง Wallet สำเร็จ ผู้ใช้จึงเลือกเครื่องและเริ่มชาร์จด้วย OCPP flow เดิม" + $nl + $nl + "[Sources]" + $nl + "- Proposed UI: payment-to-wallet flow" + $nl + "- Local code: app/ocpp_handler.py:217-352" + $nl + "- Local code: app/main.py:491-573")

# Slide 7: system modules
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddHeader $s "จาก Mockup สู่ระบบจริง: แต่ละส่วนต้องปรับอะไร" "SYSTEM MAP" 7
AddText $s "แบ่งให้เห็นชัดว่าอะไรมีอยู่แล้ว อะไรต้องปรับ และอะไรต้องสร้างใหม่" 48 126 840 26 15 $C.muted | Out-Null

AddShape $s $msoShapeRoundedRectangle 48 178 264 118 $C.paleBlue -1 | Out-Null
AddText $s "มีอยู่แล้ว" 72 198 100 18 12 $C.teal $true | Out-Null
AddText $s "Login / Users / Roles" 72 230 210 20 16 $C.ink $true | Out-Null
AddText $s "JWT auth + customer account" 72 262 210 16 11 $C.muted | Out-Null

AddShape $s $msoShapeRoundedRectangle 348 178 264 118 $C.paleBlue -1 | Out-Null
AddText $s "มีอยู่แล้ว" 372 198 100 18 12 $C.teal $true | Out-Null
AddText $s "Dashboard / Charger" 372 230 210 20 16 $C.ink $true | Out-Null
AddText $s "OCPP status + remote command" 372 262 210 16 11 $C.muted | Out-Null

AddShape $s $msoShapeRoundedRectangle 648 178 264 118 $C.paleOrange -1 | Out-Null
AddText $s "ปรับเพิ่ม" 672 198 100 18 12 $C.orange $true | Out-Null
AddText $s "Wallet UI" 672 230 210 20 16 $C.ink $true | Out-Null
AddText $s "เพิ่ม payment method + status" 672 262 210 16 11 $C.muted | Out-Null

AddShape $s $msoShapeRoundedRectangle 48 326 264 118 $C.paleOrange -1 | Out-Null
AddText $s "สร้างใหม่" 72 346 100 18 12 $C.orange $true | Out-Null
AddText $s "Omise Payment" 72 378 210 20 16 $C.ink $true | Out-Null
AddText $s "source / charge / QR / webhook" 72 410 210 16 11 $C.muted | Out-Null

AddShape $s $msoShapeRoundedRectangle 348 326 264 118 $C.paleGreen -1 | Out-Null
AddText $s "สร้างใหม่" 372 346 100 18 12 $C.green $true | Out-Null
AddText $s "Payment Status" 372 378 210 20 16 $C.ink $true | Out-Null
AddText $s "pending / success / failed / expired" 372 410 220 16 11 $C.muted | Out-Null

AddShape $s $msoShapeRoundedRectangle 648 326 264 118 $C.paleGreen -1 | Out-Null
AddText $s "สร้างใหม่" 672 346 100 18 12 $C.green $true | Out-Null
AddText $s "Ledger / Reconciliation" 672 378 220 20 16 $C.ink $true | Out-Null
AddText $s "Charge ID + audit + กันเครดิตซ้ำ" 672 410 220 16 11 $C.muted | Out-Null

AddShape $s $msoShapeRoundedRectangle 48 466 864 32 $C.darkTeal -1 | Out-Null
AddText $s "OCPP Charging Flow เดิมยังคงใช้ต่อ ไม่ต้องผูก Omise เข้ากับทุก session" 64 475 832 16 13 $C.white $true $ppAlignCenter | Out-Null
AddNotes $s ("สไลด์นี้สรุป scope งานจาก mockup ให้เป็น workstream: Auth และ OCPP มีอยู่แล้ว, Wallet ต้องปรับ UI, ส่วน Omise, payment status และ reconciliation ต้องสร้างเพิ่ม" + $nl + $nl + "[Sources]" + $nl + "- Local code: app/auth.py:18-38, app/static/index.html:164-196" + $nl + "- Local code: app/database.py:145-175, app/ocpp_handler.py:217-352")

# Slide 8: roadmap and decision
$s = $pres.Slides.Add($pres.Slides.Count + 1, $ppLayoutBlank)
$s.Background.Fill.ForeColor.RGB = $C.bg
AddHeader $s "แผนทำงาน: ตกลงภาพก่อน แล้วค่อยเชื่อมเงินจริง" "NEXT STEPS" 8
AddText $s "สิ่งแรกที่ต้องส่งมอบคือภาพหน้าจอและ flow ที่ทุกฝ่ายเข้าใจตรงกัน" 48 126 840 26 15 $C.muted | Out-Null

AddText $s "1" 72 196 42 42 18 $C.white $true $ppAlignCenter | Out-Null
AddShape $s $msoShapeOval 68 192 50 50 $C.teal -1 | Out-Null
AddText $s "1" 68 208 50 18 13 $C.white $true $ppAlignCenter | Out-Null
AddText $s "Approve Mockup" 50 264 146 22 14 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "Login → Wallet → Payment" 50 300 146 34 11 $C.muted $false $ppAlignCenter | Out-Null

AddRule $s 116 217 170 $C.rule 2 | Out-Null
AddShape $s $msoShapeOval 278 192 50 50 $C.blue -1 | Out-Null
AddText $s "2" 278 208 50 18 13 $C.white $true $ppAlignCenter | Out-Null
AddText $s "Test Mode" 264 264 78 22 14 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "PromptPay + QR + webhook" 238 300 130 34 11 $C.muted $false $ppAlignCenter | Out-Null

AddRule $s 328 217 170 $C.rule 2 | Out-Null
AddShape $s $msoShapeOval 488 192 50 50 $C.orange -1 | Out-Null
AddText $s "3" 488 208 50 18 13 $C.white $true $ppAlignCenter | Out-Null
AddText $s "Hardening" 464 264 98 22 14 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "กันซ้ำ + audit + กระทบยอด" 446 300 134 34 11 $C.muted $false $ppAlignCenter | Out-Null

AddRule $s 538 217 170 $C.rule 2 | Out-Null
AddShape $s $msoShapeOval 698 192 50 50 $C.green -1 | Out-Null
AddText $s "4" 698 208 50 18 13 $C.white $true $ppAlignCenter | Out-Null
AddText $s "Pilot → Live" 674 264 98 22 14 $C.ink $true $ppAlignCenter | Out-Null
AddText $s "เปิดกลุ่มเล็ก + monitoring" 664 300 118 34 11 $C.muted $false $ppAlignCenter | Out-Null

AddShape $s $msoShapeRoundedRectangle 48 382 864 92 $C.darkTeal -1 | Out-Null
AddText $s "มติที่ต้องการ" 76 404 150 20 13 $C.orange $true | Out-Null
AddText $s "1  อนุมัติ Prepaid Wallet" 76 432 250 22 15 $C.white $true | Out-Null
AddText $s "2  เริ่มจาก PromptPay ใน Test Mode" 354 432 280 22 15 $C.white $true | Out-Null
AddText $s "3  ทำ Mockup ให้ครบก่อน implement" 662 432 226 22 14 $C.orange $true | Out-Null
AddNotes $s ("ข้อเสนอการทำงานคือเริ่มจาก mockup ให้ทุกฝ่าย approve ก่อน จากนั้นจึงเชื่อม Omise Test, ทำ production controls และเปิด pilot" + $nl + $nl + "[Sources]" + $nl + "- Omise test/live account: https://docs.omise.co/thailand" + $nl + "- Omise webhooks: https://docs.omise.co/th/api-webhooks/thailand")

if (Test-Path -LiteralPath $pptxPath) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $pptxPath = Join-Path $outDir "EV_Charger_Full_User_Journey_Mockup-$stamp.pptx"
  $pdfPath = Join-Path $outDir "EV_Charger_Full_User_Journey_Mockup-$stamp.pdf"
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
