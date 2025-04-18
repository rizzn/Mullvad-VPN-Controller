#Requires AutoHotkey v2.0
Persistent

AppVersion := "1.2"
AppAuthor := "rizzn"
AppName := "Mullvad VPN Controller"

AutoSwitch := false
Interval := 120
TimerRunning := false

countries := Map(
	"Switzerland", "ch",
	"Romania", "ro",
	"Malaysia", "my",
	"Norway", "no",
	"Finland", "fi",
	"Estonia", "ee",
	"Czech Republic", "cz",
	"Croatia", "hr",
	"Slovenia", "si"
)
LogMessages := []

myGui := Gui()
myGui.BackColor := "White"
myGui.SetFont("s10 Bold", "Segoe UI")
myGui.AddPicture("x170 y16 w64 h64", GetAppIconPath())
myGui.AddText("x10 y90 w380 h30 Center", AppName)
myGui.SetFont("s9 Norm", "Segoe UI")

myGui.AddText("x10 y126 w100 h20", "Current IP:")
IPField := myGui.AddEdit("x76 y125 w190 h20 Disabled ReadOnly Center")
FlagIcon := myGui.AddPicture("x274 y120 w34 h30")
PingButton := myGui.AddButton("x316 y125 w82 h21", "Check Ping")
PingButton.OnEvent("Click", (*) => RunPingCheck())

row := 0
for name, code in countries {
	x := Mod(row, 3) * 132 + 10
	y := Floor(row / 3) * 40 + 160
	btn := myGui.AddButton("x" x " y" y " w124 h30", name)
	btn.OnEvent("Click", SwitchVPNButtonHandler(code, name))
	row++
}

AutoCheck := myGui.AddCheckbox("x10 y290", "Enable auto-switch")
AutoCheck.OnEvent("Click", ToggleAuto)
myGui.AddText("x280 y292 w90 h20", "Interval (min.):")
IntervalBox := myGui.AddEdit("x360 y290 w40 h20 Number Center", Interval)
IntervalBox.OnEvent("Change", SaveIntervalToRegistry)

LogBox := myGui.AddEdit("x10 y320 w390 h60 ReadOnly -Wrap +Multi")
StartupCheck := myGui.AddCheckbox("x10 y390", "Start with Windows")
StartupCheck.OnEvent("Click", ToggleStartup)
myGui.SetFont("s8 cGray")
myGui.AddText("x180 y390 w220 h20 Right", AppName " v" AppVersion " by " AppAuthor)
myGui.SetFont("s9 cBlack")

myGui.Title := AppName
SetTimer(() => ShowGui(), -100)

MenuSet := A_TrayMenu
MenuSet.Delete()
MenuSet.Add("Show " AppName, ShowGui)
MenuSet.Add("Exit", (*) => ExitApp())
MenuSet.Default := "Show " AppName
MenuSet.ClickCount := 2

UpdateIPInfo()
AppendLog("App started.")
CheckStartupStatus()

ToggleAuto(*) {
	Interval := IntervalBox.Value
	if (!IsInteger(Interval) || Interval < 1) {
		AppendLog("Invalid interval. Must be a number >= 1.")
		IntervalBox.Value := Interval
		return
	}

	AutoSwitch := AutoCheck.Value
	RegWrite(AutoSwitch ? "1" : "0", "REG_SZ", "HKCU\Software\MullvadVPNController", "AutoSwitch")
	RegWrite(Interval, "REG_SZ", "HKCU\Software\MullvadVPNController", "Interval")

	if (AutoSwitch) {
		SetTimer(AutoSwitchLocation, Interval * 60000)
		TimerRunning := true
		AppendLog("Auto-switch enabled every " Interval " min.")
	} else {
		SetTimer(AutoSwitchLocation, 0)
		TimerRunning := false
		AppendLog("Auto-switch disabled.")
	}
}

AutoSwitchLocation(*) {
	Interval := IntervalBox.Value
	keys := []
	for k, v in countries
		keys.Push({ name: k, code: v })
	index := Random(1, keys.Length)
	selected := keys[index]
	SwitchVPN(selected.code, selected.name)
}

SwitchVPN(code, name) {
	AppendLog("Switching to " name "...")
	RunWait("mullvad relay set location " code, , "Hide")
	RunWait("mullvad disconnect", , "Hide")
	IPField.Value := "Reconnecting..."
	Sleep 1000
	RunWait("mullvad connect", , "Hide")

	prevIP := IPField.Value
	Loop 10 {
		Sleep 100
		newIP := GetPublicIP()
		if (newIP != prevIP && newIP != "Unknown")
			break
	}

	UpdateIPInfo()
	AppendLog("Connected to " name)
	TrayTip("Mullvad Updated", "Location switched to " name)
	RunPingCheck()
}

SwitchVPNButtonHandler(code, name) {
	return (*) => SwitchVPN(code, name)
}

UpdateIPInfo() {
	ip := GetPublicIP()
	if (ip != "Unknown")
		IPField.Value := ip

	location := GetIPLocation()
	flag := GetFlagPath(location["country_code"])
	FlagIcon.Value := flag
}

ShowGui(*) {
	try
		myGui.Show("w410 h420")
	catch
		myGui.Opt("+AlwaysOnTop")
}

AppendLog(msg) {
	time := FormatTime(A_Now, "HH:mm:ss")
	entry := "[" time "] " msg
	LogMessages.Push(entry)
	if (LogMessages.Length > 3)
		LogMessages.RemoveAt(1)
	LogBox.Value := JoinLog(LogMessages)
}

JoinLog(arr) {
	output := ""
	for index, val in arr
		output .= val "`n"
	return Trim(output, "`n")
}

GetPublicIP() {
	try {
		req := ComObject("WinHttp.WinHttpRequest.5.1")
		req.Open("GET", "https://api.ipify.org", false)
		req.Send()
		ip := req.ResponseText
		return RegExMatch(ip, "^\d{1,3}(\.\d{1,3}){3}$") ? ip : "Unknown"
	} catch {
		return "Unknown"
	}
}

GetIPLocation() {
	try {
		req := ComObject("WinHttp.WinHttpRequest.5.1")
		req.Open("GET", "https://ipapi.co/json/", false)
		req.Send()
		json := req.ResponseText
		return ParseIPLocation(json)
	} catch {
		return Map("country_code", "XX")
	}
}

ParseIPLocation(json) {
	return RegExMatch(json, '"country_code":\s*"([A-Z]{2})', &m) ? Map("country_code", m[1]) : Map("country_code", "XX")
}

GetFlagPath(code) {
	code := StrUpper(code)
	tempPath := A_Temp "\flag_" code ".png"
	if FileExist(tempPath)
		return tempPath
	url := "https://flagsapi.com/" code "/flat/64.png"
	try {
		req := ComObject("WinHttp.WinHttpRequest.5.1")
		req.Open("GET", url, false)
		req.Send()
		if (req.Status = 200) {
			stream := ComObject("ADODB.Stream")
			stream.Type := 1
			stream.Open()
			stream.Write(req.ResponseBody)
			stream.SaveToFile(tempPath, 2)
			stream.Close()
			return tempPath
		} else {
			AppendLog("Flag download failed. Status: " req.Status)
			return ""
		}
	} catch {
		AppendLog("Failed to load flag.")
		return ""
	}
}

GetAppIconPath() {
	iconPath := A_Temp "\mullvad_app_icon.png"
	if !FileExist(iconPath) {
		try {
			req := ComObject("WinHttp.WinHttpRequest.5.1")
			req.Open("GET", "https://raw.githubusercontent.com/rizzn/Mullvad-VPN-Controller/refs/heads/master/assets/app.ico", false)
			req.Send()
			if (req.Status = 200) {
				stream := ComObject("ADODB.Stream")
				stream.Type := 1  ; binary
				stream.Open()
				stream.Write(req.ResponseBody)
				stream.SaveToFile(iconPath, 2)
				stream.Close()
			}
		}
	}
	return iconPath
}

GetPing(host := "mullvad.net") {
    try {
        shell := ComObject("WScript.Shell")
        exec := shell.Exec(A_ComSpec " /c ping -n 1 " host)
        result := exec.StdOut.ReadAll()
        if RegExMatch(result, "Zeit[=<]\s*(\d+)\s*ms", &match)
            return match[1] " ms"
        else
            return "Timeout or no reply"
    } catch {
        return "Error"
    }
}

ToggleStartup(*) {
	if StartupCheck.Value {
		try RegWrite(A_ScriptFullPath, "REG_SZ", "HKCU\Software\Microsoft\Windows\CurrentVersion\Run", "MullvadVPNController")
		AppendLog("Startup enabled.")
	} else {
		try RegDelete("HKCU\Software\Microsoft\Windows\CurrentVersion\Run", "MullvadVPNController")
		AppendLog("Startup disabled.")
	}
}

CheckStartupStatus() {
	global AutoSwitch, Interval
	try {
		value := RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Run", "MullvadVPNController")
		StartupCheck.Value := (value = A_ScriptFullPath)
	} catch {
		StartupCheck.Value := false
	}

	try AutoSwitch := RegRead("HKCU\Software\MullvadVPNController", "AutoSwitch") = "1"
	try Interval := RegRead("HKCU\Software\MullvadVPNController", "Interval")
	AutoCheck.Value := AutoSwitch
	IntervalBox.Value := Interval
	if AutoSwitch
		ToggleAuto()
}

SaveIntervalToRegistry(*) {
	val := IntervalBox.Value
	if (IsInteger(val) && val >= 1) {
		RegWrite(val, "REG_SZ", "HKCU\Software\MullvadVPNController", "Interval")
		AppendLog("Interval changed to " val " min.")
	} else {
		AppendLog("Invalid interval entered.")
	}
}

RunPingCheck() {
	global PingButton
	ping := GetPing("mullvad.net")
	AppendLog("Ping: " ping)
}

OnGuiClose(*) {
	myGui.Hide()
	static shown := false
	if !shown {
		TrayTip(AppName, "App is still running in tray.", 5)
		shown := true
	}
}
myGui.OnEvent("Close", OnGuiClose)