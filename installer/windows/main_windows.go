package main

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"syscall"
	"unsafe"
)

var (
	user32        = syscall.NewLazyDLL("user32.dll")
	kernel32      = syscall.NewLazyDLL("kernel32.dll")
	shell32       = syscall.NewLazyDLL("shell32.dll")
	ole32         = syscall.NewLazyDLL("ole32.dll")
	gdi32         = syscall.NewLazyDLL("gdi32.dll")
	defWindowProc = user32.NewProc("DefWindowProcW")
	createWindow  = user32.NewProc("CreateWindowExW")
	setText       = user32.NewProc("SetWindowTextW")
	enableWindow  = user32.NewProc("EnableWindow")
	postMessage   = user32.NewProc("PostMessageW")
	sendMessage   = user32.NewProc("SendMessageW")
	app           installerWindow
)

const (
	chooseID      = 101
	installID     = 102
	revealID      = 103
	changeID      = 104
	statusChanged = 0x8001
)

type windowClass struct {
	Size, Style                        uint32
	Procedure                          uintptr
	ClassExtra, WindowExtra            int32
	Instance, Icon, Cursor, Background uintptr
	MenuName, ClassName, SmallIcon     uintptr
}

type message struct {
	Window         uintptr
	Message        uint32
	WParam, LParam uintptr
	Time           uint32
	X, Y           int32
	Private        uint32
}

type browseInfo struct {
	Owner, Root, Name, Title uintptr
	Flags                    uint32
	Callback, Data           uintptr
	Image                    int32
}

type statusUpdate struct {
	text string
	done bool
	err  error
}

type installerWindow struct {
	window, sourceLabel, targetLabel, status, choose, install, reveal, change uintptr
	instance, font                                                            uintptr
	source, destination                                                       string
	working                                                                   bool
	updates                                                                   chan statusUpdate
}

func putText(hwnd uintptr, value string) {
	text, _ := syscall.UTF16PtrFromString(value)
	setText.Call(hwnd, uintptr(unsafe.Pointer(text)))
	runtime.KeepAlive(text)
}

func alert(hwnd uintptr, title, text string, icon uintptr) {
	caption, _ := syscall.UTF16PtrFromString(title)
	message, _ := syscall.UTF16PtrFromString(text)
	user32.NewProc("MessageBoxW").Call(hwnd, uintptr(unsafe.Pointer(message)), uintptr(unsafe.Pointer(caption)), icon)
	runtime.KeepAlive(caption)
	runtime.KeepAlive(message)
}

func browse(owner uintptr, title string) string {
	caption, _ := syscall.UTF16PtrFromString(title)
	var name [260]uint16
	info := browseInfo{Owner: owner, Name: uintptr(unsafe.Pointer(&name[0])),
		Title: uintptr(unsafe.Pointer(caption)), Flags: 0x51}
	id, _, _ := shell32.NewProc("SHBrowseForFolderW").Call(uintptr(unsafe.Pointer(&info)))
	runtime.KeepAlive(caption)
	if id == 0 {
		return ""
	}
	defer ole32.NewProc("CoTaskMemFree").Call(id)
	buffer := make([]uint16, 32768)
	ok, _, _ := shell32.NewProc("SHGetPathFromIDListEx").Call(id, uintptr(unsafe.Pointer(&buffer[0])), uintptr(len(buffer)), 0)
	if ok == 0 {
		return ""
	}
	return syscall.UTF16ToString(buffer)
}

func (a *installerWindow) control(class, text string, x, y, w, h, id, extraStyle uintptr) uintptr {
	kind, _ := syscall.UTF16PtrFromString(class)
	title, _ := syscall.UTF16PtrFromString(text)
	result, _, _ := createWindow.Call(0, uintptr(unsafe.Pointer(kind)), uintptr(unsafe.Pointer(title)), 0x50000000|extraStyle,
		x, y, w, h, a.window, id, a.instance, 0)
	runtime.KeepAlive(kind)
	runtime.KeepAlive(title)
	sendMessage.Call(result, 0x30, a.font, 1)
	return result
}

func (a *installerWindow) build() {
	a.font, _, _ = gdi32.NewProc("GetStockObject").Call(17)
	a.control("STATIC", "Use your own matching copy of classic PC Vice City. The installer downloads the mod and creates a separate playable copy.", 20, 14, 555, 45, 0, 0)
	a.control("STATIC", "Classic Vice City folder", 20, 73, 555, 22, 0, 0)
	a.sourceLabel = a.control("STATIC", "", 20, 102, 388, 37, 0, 0)
	a.choose = a.control("BUTTON", "Choose Game Files...", 414, 99, 158, 28, chooseID, 0x10000)
	a.control("STATIC", "Install location", 20, 148, 550, 22, 0, 0)
	a.targetLabel = a.control("STATIC", "", 20, 178, 388, 37, 0, 0)
	a.change = a.control("BUTTON", "Change Location...", 414, 175, 158, 28, changeID, 0x10000)
	a.status = a.control("STATIC", "", 20, 228, 555, 41, 0, 0)
	a.reveal = a.control("BUTTON", "Show Game Folder", 243, 279, 155, 30, revealID, 0x10000)
	a.install = a.control("BUTTON", "Install Mod", 414, 279, 158, 30, installID, 0x10000)
	a.refresh()
}

func (a *installerWindow) refresh() {
	source := a.source
	if source == "" {
		source = "Choose a classic Vice City installation folder."
	}
	putText(a.sourceLabel, source)
	putText(a.targetLabel, a.destination)
	enabled := uintptr(0)
	if !a.working {
		enabled = 1
	}
	enableWindow.Call(a.choose, enabled)
	enableWindow.Call(a.change, enabled)
	var canInstall uintptr
	if !a.working && a.source != "" {
		canInstall = 1
	}
	enableWindow.Call(a.install, canInstall)
	var canReveal uintptr
	if _, err := os.Stat(filepath.Join(a.destination, edition+".exe")); err == nil && !a.working {
		canReveal = 1
	}
	enableWindow.Call(a.reveal, canReveal)
}

func (a *installerWindow) start() {
	if a.working || a.source == "" {
		return
	}
	a.working = true
	a.refresh()
	source, dest := a.source, a.destination
	go func() {
		update := func(value statusUpdate) {
			a.updates <- value
			postMessage.Call(a.window, statusChanged, 0, 0)
		}
		err := install(source, dest, "", func(text string) { update(statusUpdate{text: text}) })
		update(statusUpdate{text: "Installation complete.", done: true, err: err})
	}()
}

func windowProc(hwnd uintptr, msg uint32, wparam, lparam uintptr) uintptr {
	switch msg {
	case 1:
		app.window = hwnd
		app.build()
		return 0
	case 0x111:
		switch wparam & 0xffff {
		case chooseID:
			if folder := browse(hwnd, "Choose the original Vice City folder"); folder != "" {
				root, err := gameRoot(folder)
				if err != nil {
					alert(hwnd, edition, err.Error(), 0x30)
					return 0
				}
				app.source = root
				putText(app.status, "")
				app.refresh()
			}
		case changeID:
			if folder := browse(hwnd, "Choose a parent folder for the mod"); folder != "" {
				app.destination = filepath.Join(folder, edition)
				app.refresh()
			}
		case installID:
			app.start()
		case revealID:
			command, _ := syscall.UTF16PtrFromString("open")
			folder, _ := syscall.UTF16PtrFromString(app.destination)
			shell32.NewProc("ShellExecuteW").Call(hwnd, uintptr(unsafe.Pointer(command)), uintptr(unsafe.Pointer(folder)), 0, 0, 1)
			runtime.KeepAlive(command)
			runtime.KeepAlive(folder)
		}
		return 0
	case statusChanged:
		update := <-app.updates
		if update.done {
			app.working = false
			app.refresh()
		}
		if update.err != nil {
			putText(app.status, "Installation stopped.")
			alert(hwnd, edition, update.err.Error(), 0x30)
		} else {
			putText(app.status, update.text)
		}
		return 0
	case 0x10:
		if app.working {
			return 0
		}
	case 2:
		user32.NewProc("PostQuitMessage").Call(0)
		return 0
	}
	result, _, _ := defWindowProc.Call(hwnd, uintptr(msg), wparam, lparam)
	return result
}

func initialSource() string {
	if steam := os.Getenv("ProgramFiles(x86)"); steam != "" {
		if root, err := gameRoot(filepath.Join(steam, "Steam", "steamapps", "common", "Grand Theft Auto Vice City")); err == nil {
			return root
		}
	}
	return ""
}

func main() {
	runtime.LockOSThread()
	if len(os.Args) == 5 && os.Args[1] == "--verify-install" {
		err := install(os.Args[2], os.Args[4], os.Args[3], func(text string) { fmt.Println(text) })
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}
	home, err := os.UserCacheDir()
	if err != nil {
		alert(0, edition, err.Error(), 0x10)
		return
	}
	app = installerWindow{source: initialSource(), destination: filepath.Join(home, edition), updates: make(chan statusUpdate, 8)}
	ole32.NewProc("OleInitialize").Call(0)
	defer ole32.NewProc("OleUninitialize").Call()
	app.instance, _, _ = kernel32.NewProc("GetModuleHandleW").Call(0)
	cursor, _, _ := user32.NewProc("LoadCursorW").Call(0, 32512)
	icon, _, _ := user32.NewProc("LoadIconW").Call(0, 32512)
	name, _ := syscall.UTF16PtrFromString("HawkingInstaller")
	title, _ := syscall.UTF16PtrFromString("Install GTA Stephen Hawking Edition")
	wc := windowClass{Size: uint32(unsafe.Sizeof(windowClass{})), Procedure: syscall.NewCallback(windowProc),
		Instance: app.instance, Icon: icon, Cursor: cursor, Background: 16, ClassName: uintptr(unsafe.Pointer(name))}
	ok, _, _ := user32.NewProc("RegisterClassExW").Call(uintptr(unsafe.Pointer(&wc)))
	if ok == 0 {
		alert(0, edition, "Could not initialize the installer window.", 0x10)
		return
	}
	window, _, _ := createWindow.Call(0, uintptr(unsafe.Pointer(name)), uintptr(unsafe.Pointer(title)), 0x00ca0000,
		0x80000000, 0x80000000, 610, 362, 0, 0, app.instance, 0)
	runtime.KeepAlive(name)
	runtime.KeepAlive(title)
	if window == 0 {
		alert(0, edition, "Could not open the installer window.", 0x10)
		return
	}
	user32.NewProc("ShowWindow").Call(window, 5)
	var event message
	for {
		result, _, _ := user32.NewProc("GetMessageW").Call(uintptr(unsafe.Pointer(&event)), 0, 0, 0)
		if int32(result) <= 0 {
			break
		}
		user32.NewProc("TranslateMessage").Call(uintptr(unsafe.Pointer(&event)))
		user32.NewProc("DispatchMessageW").Call(uintptr(unsafe.Pointer(&event)))
	}
}
