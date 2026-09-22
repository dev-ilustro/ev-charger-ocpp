$ErrorActionPreference = "Stop"

$captureDir = Join-Path (Get-Location) "presentation_capture"
$screenDir = Join-Path $captureDir "screens"
[System.IO.Directory]::CreateDirectory($screenDir) | Out-Null

$chromePath = "C:\Program Files\Google\Chrome\Application\chrome.exe"
$debugPort = 9223
$profileDir = Join-Path $captureDir "chrome-profile"
$url = "http://127.0.0.1:9001/login.html"

function Receive-CdpMessage($socket) {
  $buffer = New-Object byte[] 1048576
  $builder = New-Object System.Text.StringBuilder
  do {
    $result = $socket.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buffer)), [Threading.CancellationToken]::None).GetAwaiter().GetResult()
    if ($result.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Close) {
      throw "Chrome DevTools connection closed"
    }
    [void]$builder.Append([Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count))
  } while (-not $result.EndOfMessage)
  return ($builder.ToString() | ConvertFrom-Json)
}

$script:messageId = 0
function Send-CdpCommand($socket, [string]$method, $params = @{}) {
  $script:messageId++
  $id = $script:messageId
  $payload = @{ id = $id; method = $method; params = $params } | ConvertTo-Json -Compress -Depth 20
  $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
  $segment = New-Object System.ArraySegment[byte] -ArgumentList @(,$bytes)
  $socket.SendAsync($segment, [Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
  do {
    $response = Receive-CdpMessage $socket
  } while ($response.id -ne $id)
  return $response
}

function Wait-Cdp($socket, [int]$milliseconds) {
  $expr = "new Promise(resolve => setTimeout(resolve, $milliseconds))"
  [void](Send-CdpCommand $socket "Runtime.evaluate" @{ expression = $expr; awaitPromise = $true; returnByValue = $true })
}

function Evaluate-Cdp($socket, [string]$expression) {
  return Send-CdpCommand $socket "Runtime.evaluate" @{ expression = $expression; awaitPromise = $true; returnByValue = $true }
}

function Save-Screenshot($socket, [string]$name) {
  $result = $null
  for ($attempt = 0; $attempt -lt 5; $attempt++) {
    $result = Send-CdpCommand $socket "Page.captureScreenshot" @{ format = "png"; fromSurface = $true; captureBeyondViewport = $true }
    if ($result.result.data) { break }
    Wait-Cdp $socket 500
  }
  if (-not $result.result.data) { throw "Chrome ไม่ส่งภาพกลับสำหรับ $name" }
  $path = Join-Path $screenDir ($name + ".png")
  [IO.File]::WriteAllBytes($path, [Convert]::FromBase64String($result.result.data))
  Write-Output $path
}

$chrome = $null
$socket = $null
try {
  $chrome = Start-Process -FilePath $chromePath -WindowStyle Hidden -PassThru -ArgumentList @(
    "--headless=new",
    "--disable-gpu",
    "--no-sandbox",
    "--no-first-run",
    "--no-default-browser-check",
    "--hide-scrollbars",
    "--remote-debugging-port=$debugPort",
    "--user-data-dir=$profileDir",
    "--window-size=900,800",
    $url
  )

  $target = $null
  for ($i = 0; $i -lt 30 -and -not $target; $i++) {
    Start-Sleep -Milliseconds 300
    try {
      $targets = Invoke-RestMethod -Uri "http://127.0.0.1:$debugPort/json/list"
      $target = @($targets | Where-Object { $_.type -eq "page" } | Select-Object -First 1)
    } catch {}
  }
  if (-not $target) { throw "หา Chrome DevTools page ไม่พบ" }

  $socket = New-Object Net.WebSockets.ClientWebSocket
  $socket.ConnectAsync([Uri]$target.webSocketDebuggerUrl, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
  [void](Send-CdpCommand $socket "Page.enable")
  [void](Send-CdpCommand $socket "Runtime.enable")
  Wait-Cdp $socket 1200

  Save-Screenshot $socket "01-login"

  $login = "document.querySelector('#login-username').value='korakots'; document.querySelector('#login-password').value='Demo123!'; document.querySelector('#login-form').requestSubmit();"
  [void](Evaluate-Cdp $socket $login)
  Wait-Cdp $socket 1800
  Save-Screenshot $socket "02-home"

  [void](Evaluate-Cdp $socket "switchScreen('settings')")
  Wait-Cdp $socket 800
  Save-Screenshot $socket "03-settings-wallet"

  [void](Evaluate-Cdp $socket "openDetailScreen('yc0117126030096')")
  Wait-Cdp $socket 1200
  Save-Screenshot $socket "04-charger-detail"

  [void](Evaluate-Cdp $socket "switchScreen('transactions')")
  Wait-Cdp $socket 1000
  Save-Screenshot $socket "05-transactions"
} finally {
  if ($socket) {
    try { $socket.CloseAsync([Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "done", [Threading.CancellationToken]::None).GetAwaiter().GetResult() } catch {}
    $socket.Dispose()
  }
  if ($chrome) {
    Stop-Process -Id $chrome.Id -Force -ErrorAction SilentlyContinue
  }
}
