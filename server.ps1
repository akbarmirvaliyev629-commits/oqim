param(
	[int]$Port = 8787,
	[string]$DataPath = ""
)

$ErrorActionPreference = "Stop"
$script:RootPath = $PSScriptRoot
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:Accounts = New-Object 'System.Collections.Generic.List[object]'
$script:Sessions = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
$script:LoginFailures = @{}
$script:SessionCookie = "oqim_session"
$script:HashIterations = 310000
$script:AllowedAccents = @("#176b61", "#5865f2", "#23a55a", "#f0b232", "#eb459e", "#f23f43", "#00a8fc")
$script:AllowedPatterns = @("grid", "diagonal", "dots", "lines", "solid")

if ($Port -lt 1 -or $Port -gt 65535) {
	throw "Port must be between 1 and 65535. Received: $Port"
}

if ([string]::IsNullOrWhiteSpace($DataPath)) {
	$dataDirectory = Join-Path $env:LOCALAPPDATA "Oqim"
	if (-not (Test-Path $dataDirectory)) {
		New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
	}
	$script:DataPath = Join-Path $dataDirectory "accounts.json"
} else {
	$script:DataPath = [System.IO.Path]::GetFullPath($DataPath)
	$parentDirectory = Split-Path -Parent $script:DataPath
	if (-not [string]::IsNullOrWhiteSpace($parentDirectory) -and -not (Test-Path $parentDirectory)) {
		New-Item -ItemType Directory -Path $parentDirectory -Force | Out-Null
	}
}

function Save-AccountStore {
	$store = [ordered]@{ users = @($script:Accounts.ToArray()) }
	$json = ConvertTo-Json -InputObject $store -Depth 60 -Compress
	$tempPath = "$($script:DataPath).tmp"
	[System.IO.File]::WriteAllText($tempPath, $json, $script:Utf8)
	Move-Item -LiteralPath $tempPath -Destination $script:DataPath -Force
}

function Load-AccountStore {
	if (-not (Test-Path $script:DataPath)) { return }
	$store = Get-Content -LiteralPath $script:DataPath -Raw -Encoding UTF8 | ConvertFrom-Json
	foreach ($account in @($store.users)) {
		if ($null -ne $account -and -not [string]::IsNullOrWhiteSpace([string]$account.id)) {
			$script:Accounts.Add($account)
		}
	}
}

function Find-AccountById([string]$Id) {
	foreach ($account in $script:Accounts) {
		if ($account.id -eq $Id) { return $account }
	}
	return $null
}

function Find-AccountByUsername([string]$UsernameKey) {
	foreach ($account in $script:Accounts) {
		if ($account.usernameKey -eq $UsernameKey) { return $account }
	}
	return $null
}

function New-PasswordRecord([string]$Password) {
	$salt = New-Object byte[] 16
	$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
	$rng.GetBytes($salt)
	$derive = [System.Security.Cryptography.Rfc2898DeriveBytes]::new(
		$Password,
		$salt,
		$script:HashIterations,
		[System.Security.Cryptography.HashAlgorithmName]::SHA256
	)
	try {
		$hash = $derive.GetBytes(32)
	} finally {
		$derive.Dispose()
		$rng.Dispose()
	}
	return [pscustomobject]@{
		salt = [Convert]::ToBase64String($salt)
		hash = [Convert]::ToBase64String($hash)
		iterations = $script:HashIterations
	}
}

function Test-Password([string]$Password, $Account) {
	try {
		$salt = [Convert]::FromBase64String([string]$Account.passwordSalt)
		$expected = [Convert]::FromBase64String([string]$Account.passwordHash)
		$iterations = [int]$Account.passwordIterations
		$derive = [System.Security.Cryptography.Rfc2898DeriveBytes]::new(
			$Password,
			$salt,
			$iterations,
			[System.Security.Cryptography.HashAlgorithmName]::SHA256
		)
		try {
			$actual = $derive.GetBytes($expected.Length)
		} finally {
			$derive.Dispose()
		}
		if ($actual.Length -ne $expected.Length) { return $false }
		$difference = 0
		for ($index = 0; $index -lt $actual.Length; $index++) {
			$difference = $difference -bor ($actual[$index] -bxor $expected[$index])
		}
		return ($difference -eq 0)
	} catch {
		return $false
	}
}

function New-SessionToken {
	$bytes = New-Object byte[] 32
	$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
	try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
	return [Convert]::ToBase64String($bytes).TrimEnd("=").Replace("+", "-").Replace("/", "_")
}

function Set-SessionCookie($Response, [string]$Token) {
	$Response.Headers["Set-Cookie"] = "$($script:SessionCookie)=$Token; Path=/; HttpOnly; SameSite=Strict; Max-Age=28800"
}

function Clear-SessionCookie($Response) {
	$Response.Headers["Set-Cookie"] = "$($script:SessionCookie)=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT"
}

function Get-SessionAccount($Request) {
	$cookie = $Request.Cookies[$script:SessionCookie]
	if ($null -eq $cookie -or [string]::IsNullOrWhiteSpace($cookie.Value)) { return $null }
	$token = $cookie.Value
	if (-not $script:Sessions.ContainsKey($token)) { return $null }
	$session = $script:Sessions[$token]
	if ($session.expiresAt -lt [DateTime]::UtcNow) {
		$script:Sessions.Remove($token) | Out-Null
		return $null
	}
	return Find-AccountById ([string]$session.userId)
}

function Test-RequestOrigin($Request) {
	$origin = [string]$Request.Headers["Origin"]
	if ([string]::IsNullOrWhiteSpace($origin)) { return $false }
	$expected = $Request.Url.GetLeftPart([System.UriPartial]::Authority)
	return ($origin -eq $expected)
}

function Read-JsonBody($Request) {
	if ($Request.ContentLength64 -gt 1048576) { throw "Request body too large" }
	$reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
	try {
		$text = $reader.ReadToEnd()
	} finally {
		$reader.Dispose()
	}
	if ([string]::IsNullOrWhiteSpace($text)) { return $null }
	return ConvertFrom-Json -InputObject $text
}

function Send-Json($Context, [int]$Status, $Payload) {
	$response = $Context.Response
	$response.StatusCode = $Status
	$response.ContentType = "application/json; charset=utf-8"
	$response.Headers["Cache-Control"] = "no-store"
	$json = ConvertTo-Json -InputObject $Payload -Depth 60 -Compress
	$bytes = $script:Utf8.GetBytes($json)
	$response.ContentLength64 = $bytes.Length
	$response.OutputStream.Write($bytes, 0, $bytes.Length)
	$response.Close()
}

function Send-Empty($Context, [int]$Status) {
	$Context.Response.StatusCode = $Status
	$Context.Response.Headers["Cache-Control"] = "no-store"
	$Context.Response.Close()
}

function Send-StaticIndex($Context) {
	$bytes = [System.IO.File]::ReadAllBytes((Join-Path $script:RootPath "index.html"))
	$Context.Response.StatusCode = 200
	$Context.Response.ContentType = "text/html; charset=utf-8"
	$Context.Response.ContentLength64 = $bytes.Length
	$Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
	$Context.Response.Close()
}

function Get-PublicUser($Account) {
	return [ordered]@{
		id = $Account.id
		username = $Account.username
		profile = $Account.profile
		createdAt = $Account.createdAt
	}
}

function Get-AccountPayload($Account) {
	return [ordered]@{
		user = Get-PublicUser $Account
		data = $Account.data
	}
}

function Start-UserSession($Context, $Account) {
	$oldCookie = $Context.Request.Cookies[$script:SessionCookie]
	if ($null -ne $oldCookie -and $script:Sessions.ContainsKey($oldCookie.Value)) {
		$script:Sessions.Remove($oldCookie.Value) | Out-Null
	}
	$token = New-SessionToken
	$script:Sessions[$token] = [pscustomobject]@{
		userId = $Account.id
		expiresAt = [DateTime]::UtcNow.AddHours(8)
	}
	Set-SessionCookie $Context.Response $token
}

function Set-SecurityHeaders($Response) {
	$Response.Headers["X-Content-Type-Options"] = "nosniff"
	$Response.Headers["X-Frame-Options"] = "DENY"
	$Response.Headers["Referrer-Policy"] = "no-referrer"
	$Response.Headers["Content-Security-Policy"] = "default-src 'self'; img-src 'self' https://covers.openlibrary.org data:; connect-src 'self' https://openlibrary.org; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'"
}

function Handle-ApiRequest($Context) {
	$request = $Context.Request
	$response = $Context.Response
	$path = $request.Url.AbsolutePath
	$method = $request.HttpMethod.ToUpperInvariant()

	if ($path -eq "/api/health" -and $method -eq "GET") {
		Send-Json $Context 200 @{ status = "ok" }
		return
	}

	if (($path -eq "/api/register" -or $path -eq "/api/login" -or $method -eq "PUT" -or $path -eq "/api/logout") -and -not (Test-RequestOrigin $request)) {
		Send-Json $Context 403 @{ error = "So‘rov manbasi tekshiruvdan o‘tmadi." }
		return
	}

	if ($path -eq "/api/register" -and $method -eq "POST") {
		$body = Read-JsonBody $request
		$username = ([string]$body.username).Trim()
		$usernameKey = $username.ToLowerInvariant()
		$password = [string]$body.password
		$displayName = ([string]$body.displayName).Trim()
		if ($username -notmatch '^[A-Za-z0-9_.-]{3,24}$') {
			Send-Json $Context 400 @{ error = "Login 3–24 ta belgi bo‘lsin: harf, raqam, nuqta, chiziqcha yoki pastki chiziq." }
			return
		}
		if ($password.Length -lt 10 -or $password.Length -gt 128) {
			Send-Json $Context 400 @{ error = "Parol 10–128 ta belgidan iborat bo‘lishi kerak." }
			return
		}
		if ($displayName.Length -lt 2 -or $displayName.Length -gt 32) {
			Send-Json $Context 400 @{ error = "Profil nomi 2–32 ta belgidan iborat bo‘lsin." }
			return
		}
		if ($null -ne (Find-AccountByUsername $usernameKey)) {
			Send-Json $Context 409 @{ error = "Bu login band. Boshqasini tanlang." }
			return
		}
		$passwordRecord = New-PasswordRecord $password
		$account = [pscustomobject]@{
			id = [Guid]::NewGuid().ToString("N")
			username = $username
			usernameKey = $usernameKey
			passwordSalt = $passwordRecord.salt
			passwordHash = $passwordRecord.hash
			passwordIterations = $passwordRecord.iterations
			createdAt = [DateTime]::UtcNow.ToString("o")
			profile = [pscustomobject]@{
				displayName = $displayName
				bio = ""
				accent = "#176b61"
				pattern = "grid"
			}
			data = [pscustomobject]@{
				tasks = @()
				notes = ""
				focus = [pscustomobject]@{ date = ""; minutes = 0 }
				library = @()
				presentations = @()
				activeDeck = ""
			}
		}
		$script:Accounts.Add($account)
		try {
			Save-AccountStore
		} catch {
			$script:Accounts.Remove($account) | Out-Null
			Send-Json $Context 500 @{ error = "Akkauntni saqlab bo‘lmadi." }
			return
		}
		Start-UserSession $Context $account
		Send-Json $Context 201 (Get-AccountPayload $account)
		return
	}

	if ($path -eq "/api/login" -and $method -eq "POST") {
		$body = Read-JsonBody $request
		$usernameKey = ([string]$body.username).Trim().ToLowerInvariant()
		$password = [string]$body.password
		$remoteAddress = [string]$request.RemoteEndPoint.Address
		$attempts = $script:LoginFailures[$remoteAddress]
		if ($null -ne $attempts -and $attempts.until -gt [DateTime]::UtcNow -and $attempts.count -ge 10) {
			Send-Json $Context 429 @{ error = "Juda ko‘p urinish bo‘ldi. Birozdan keyin urinib ko‘ring." }
			return
		}
		$account = Find-AccountByUsername $usernameKey
		if ($null -eq $account -or -not (Test-Password $password $account)) {
			if ($null -eq $attempts -or $attempts.until -lt [DateTime]::UtcNow) {
				$attempts = [pscustomobject]@{ count = 0; until = [DateTime]::UtcNow.AddMinutes(5) }
			}
			$attempts.count++
			$script:LoginFailures[$remoteAddress] = $attempts
			Send-Json $Context 401 @{ error = "Login yoki parol noto‘g‘ri." }
			return
		}
		$script:LoginFailures.Remove($remoteAddress)
		Start-UserSession $Context $account
		Send-Json $Context 200 (Get-AccountPayload $account)
		return
	}

	if ($path -eq "/api/logout" -and $method -eq "POST") {
		$cookie = $request.Cookies[$script:SessionCookie]
		if ($null -ne $cookie -and $script:Sessions.ContainsKey($cookie.Value)) {
			$script:Sessions.Remove($cookie.Value) | Out-Null
		}
		Clear-SessionCookie $response
		Send-Empty $Context 204
		return
	}

	$account = Get-SessionAccount $request
	if ($null -eq $account) {
		Send-Json $Context 401 @{ error = "Davom etish uchun akkauntingizga kiring." }
		return
	}

	if ($path -eq "/api/me" -and $method -eq "GET") {
		Send-Json $Context 200 (Get-AccountPayload $account)
		return
	}

	if ($path -eq "/api/profile" -and $method -eq "PUT") {
		$body = Read-JsonBody $request
		$displayName = ([string]$body.displayName).Trim()
		$bio = [string]$body.bio
		$accent = [string]$body.accent
		$pattern = [string]$body.pattern
		if ($displayName.Length -lt 2 -or $displayName.Length -gt 32 -or $bio.Length -gt 160) {
			Send-Json $Context 400 @{ error = "Profil nomi yoki bio ruxsat etilgan uzunlikdan oshdi." }
			return
		}
		if ($script:AllowedAccents -notcontains $accent -or $script:AllowedPatterns -notcontains $pattern) {
			Send-Json $Context 400 @{ error = "Tanlangan profil dizayni qo‘llab-quvvatlanmaydi." }
			return
		}
		$account.profile.displayName = $displayName
		$account.profile.bio = $bio
		$account.profile.accent = $accent
		$account.profile.pattern = $pattern
		Save-AccountStore
		Send-Json $Context 200 (Get-AccountPayload $account)
		return
	}

	if ($path -eq "/api/data" -and $method -eq "GET") {
		Send-Json $Context 200 @{ data = $account.data }
		return
	}

	if ($path -eq "/api/data" -and $method -eq "PUT") {
		$body = Read-JsonBody $request
		$incoming = $body.data
		if ($null -eq $incoming) {
			Send-Json $Context 400 @{ error = "Saqlanadigan ma’lumot topilmadi." }
			return
		}
		$tasks = @($incoming.tasks)
		$library = @($incoming.library)
		$presentations = @($incoming.presentations)
		$notes = [string]$incoming.notes
		$activeDeck = [string]$incoming.activeDeck
		if ($tasks.Count -gt 500 -or $library.Count -gt 500 -or $presentations.Count -gt 100 -or $notes.Length -gt 20000) {
			Send-Json $Context 413 @{ error = "Saqlanadigan ma’lumot hajmi belgilangan chegaradan oshdi." }
			return
		}
		if ($activeDeck.Length -gt 100 -or ($activeDeck.Length -gt 0 -and @($presentations | Where-Object { $_.id -eq $activeDeck }).Count -eq 0)) {
			Send-Json $Context 400 @{ error = "Faol taqdimot ushbu akkauntga tegishli emas." }
			return
		}
		$account.data = [pscustomobject]@{
			tasks = $tasks
			notes = $notes
			focus = $incoming.focus
			library = $library
			presentations = $presentations
			activeDeck = $activeDeck
		}
		Save-AccountStore
		Send-Json $Context 200 @{ saved = $true }
		return
	}

	Send-Json $Context 404 @{ error = "API yo‘li topilmadi." }
}

function Invoke-Request($Context) {
	$response = $Context.Response
	Set-SecurityHeaders $response
	$path = $Context.Request.Url.AbsolutePath
	if ($path.StartsWith("/api/")) {
		Handle-ApiRequest $Context
		return
	}
	if ($path -eq "/" -and $Context.Request.HttpMethod -eq "GET") {
		Send-StaticIndex $Context
		return
	}
	Send-Json $Context 404 @{ error = "Sahifa topilmadi." }
}

Load-AccountStore
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
try {
	$listener.Start()
	Write-Host "Oqim ishga tushdi: http://localhost:$Port/"
	Write-Host "Hisoblar saqlanadi: $script:DataPath"
	while ($listener.IsListening) {
		$context = $listener.GetContext()
		try {
			Invoke-Request $context
		} catch {
			Write-Warning ("{0} {1}: {2}" -f $context.Request.HttpMethod, $context.Request.Url.AbsolutePath, $_.Exception.Message)
			try {
				if (-not $context.Response.OutputStream.CanWrite) { continue }
				Send-Json $context 500 @{ error = "Serverda xatolik yuz berdi." }
			} catch {
				try { $context.Response.Abort() } catch {}
			}
		}
	}
} catch {
	$rootException = $_.Exception.GetBaseException()
	$details = $rootException.Message
	if (($rootException -is [System.Net.Sockets.SocketException] -and $rootException.SocketErrorCode -eq [System.Net.Sockets.SocketError]::AddressAlreadyInUse) -or
		($rootException -is [System.Net.HttpListenerException] -and $rootException.ErrorCode -in @(183, 10048))) {
		throw "Port $Port is already in use. Start Oqim with another port, for example: .\server.ps1 -Port 8788"
	}
	if (-not $listener.IsListening) {
		throw "Oqim could not start on http://localhost:$Port/. $details"
	}
	throw
} finally {
	if ($listener.IsListening) { $listener.Stop() }
	$listener.Close()
}
