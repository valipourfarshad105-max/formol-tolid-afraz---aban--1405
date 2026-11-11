$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$dataDir = Join-Path $root 'data'
$initial = Join-Path $dataDir 'initial.json'
$state = Join-Path $dataDir 'state.json'
$previous = Join-Path $dataDir 'previous.json'
$utf8 = New-Object System.Text.UTF8Encoding($false)
if (!(Test-Path $state)) { [System.IO.File]::Copy($initial, $state) }
$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = $listener.LocalEndpoint.Port
$token = [Guid]::NewGuid().ToString('N') + [Guid]::NewGuid().ToString('N')
$url = "http://127.0.0.1:$port/?token=$token"
Write-Host "Afraz is running at $url"
Write-Host 'Keep this window open. Close this window to stop the program.'
Start-Process $url
function Reply($stream, [int]$status, [string]$type, [byte[]]$body) {
  $message = switch ($status) { 200 {'OK'} 400 {'Bad Request'} 403 {'Forbidden'} 404 {'Not Found'} 405 {'Method Not Allowed'} 413 {'Payload Too Large'} default {'Internal Server Error'} }
  $headers = "HTTP/1.1 $status $message`r`nContent-Type: $type`r`nContent-Length: $($body.Length)`r`nCache-Control: no-store`r`nX-Content-Type-Options: nosniff`r`nConnection: close`r`n`r`n"
  $head = [System.Text.Encoding]::ASCII.GetBytes($headers)
  $stream.Write($head, 0, $head.Length)
  if ($body.Length -gt 0) { $stream.Write($body, 0, $body.Length) }
  $stream.Flush()
}
try {
 while ($true) {
  $client = $listener.AcceptTcpClient()
  $client.ReceiveTimeout = 15000; $client.SendTimeout = 15000
  $stream = $client.GetStream()
  try {
   $buf = New-Object System.Collections.Generic.List[byte]
   $last = ''
   while ($buf.Count -lt 32768) {
    $b = $stream.ReadByte(); if ($b -lt 0) { throw 'Incomplete header' }
    $buf.Add([byte]$b); $last += [char]$b
    if ($last.Length -gt 4) { $last = $last.Substring($last.Length - 4) }
    if ($last -eq "`r`n`r`n") { break }
   }
   if ($last -ne "`r`n`r`n") { throw 'Header too large' }
   $head = [System.Text.Encoding]::ASCII.GetString($buf.ToArray())
   $lines = $head -split "`r`n"; $first = $lines[0] -split ' '
   if ($first.Length -lt 2) { throw 'Bad request' }
   $method = $first[0]; $path = ($first[1] -split '\?')[0]
   $headers = @{}
   foreach ($line in $lines[1..($lines.Length-1)]) { $pos = $line.IndexOf(':'); if ($pos -gt 0) { $headers[$line.Substring(0,$pos).Trim().ToLowerInvariant()] = $line.Substring($pos+1).Trim() } }
   if ($path -eq '/' -and $method -eq 'GET') {
    Reply $stream 200 'text/html; charset=utf-8' ([System.IO.File]::ReadAllBytes((Join-Path $root 'index.html')))
   } elseif ($path -eq '/api/data') {
    if ($headers['x-afraz-token'] -ne $token) { Reply $stream 403 'text/plain' ($utf8.GetBytes('Forbidden')) }
    elseif ($method -eq 'GET') { Reply $stream 200 'application/json; charset=utf-8' ([System.IO.File]::ReadAllBytes($state)) }
    elseif ($method -eq 'POST') {
     $length = 0
     if (-not [int]::TryParse($headers['content-length'], [ref]$length) -or $length -le 0 -or $length -gt 5242880) { Reply $stream 413 'text/plain' ($utf8.GetBytes('Invalid size')) }
     else {
      $body = New-Object byte[] $length; $offset = 0
      while ($offset -lt $length) { $n = $stream.Read($body, $offset, $length - $offset); if ($n -le 0) { throw 'Incomplete body' }; $offset += $n }
      $json = $utf8.GetString($body); $obj = ConvertFrom-Json -InputObject $json
      if ($null -eq $obj.version -or $null -eq $obj.resources -or $null -eq $obj.recipes -or $null -eq $obj.products) { throw 'Invalid data' }
      [System.IO.File]::Copy($state, $previous, $true)
      $temp = Join-Path $dataDir 'state.tmp'
      [System.IO.File]::WriteAllText($temp, $json, $utf8)
      [System.IO.File]::Copy($temp, $state, $true); [System.IO.File]::Delete($temp)
      Reply $stream 200 'application/json; charset=utf-8' ($utf8.GetBytes('{"ok":true}'))
     }
    } else { Reply $stream 405 'text/plain' ($utf8.GetBytes('Method not allowed')) }
   } else { Reply $stream 404 'text/plain' ($utf8.GetBytes('Not found')) }
  } catch { try { Reply $stream 400 'text/plain; charset=utf-8' ($utf8.GetBytes('Request failed: ' + $_.Exception.Message)) } catch {} }
  finally { $stream.Close(); $client.Close() }
 }
} finally { $listener.Stop() }
