//! ParsiDesk support toolbox: one-click fixes a supporter runs on a Windows peer.
//!
//! Each action returns `(ok, text)`. `text` is JSON for `system_info`; otherwise it is
//! empty, a translation key, or the raw output of the failed command.

use hbb_common::{
    base64::{engine::general_purpose::STANDARD, Engine},
    log,
};
use std::{os::windows::process::CommandExt, process::Command};

const CREATE_NO_WINDOW: u32 = 0x0800_0000;

pub const SYSTEM_INFO: &str = "system_info";
pub const FLUSH_DNS: &str = "flush_dns";
pub const RESET_NETWORK: &str = "reset_network";
pub const SAFE_MODE: &str = "safe_mode";
pub const NORMAL_MODE: &str = "normal_mode";

/// Actions that restart the peer and so also need the restart permission.
pub fn restarts(action: &str) -> bool {
    action == SAFE_MODE || action == NORMAL_MODE
}

pub fn run(action: &str) -> (bool, String) {
    let elevated =
        crate::platform::is_root() || crate::platform::is_elevated(None).unwrap_or(false);
    let res = match action {
        SYSTEM_INFO => powershell(SYSTEM_INFO_SCRIPT),
        FLUSH_DNS => run_cmd("ipconfig.exe", &["/flushdns"]),
        RESET_NETWORK if !elevated => Err(
            "This action needs ParsiDesk to run as administrator on the remote computer."
                .to_owned(),
        ),
        // Detached: the session drops while the adapters restart, so answer first.
        RESET_NETWORK => spawn_powershell(RESET_NETWORK_SCRIPT),
        SAFE_MODE | NORMAL_MODE if !crate::platform::is_installed() || !elevated => {
            Err("This action needs ParsiDesk to be installed on the remote computer.".to_owned())
        }
        SAFE_MODE => set_safe_mode(true),
        NORMAL_MODE => set_safe_mode(false),
        _ => Err("The remote computer does not support this action.".to_owned()),
    };
    log::info!("Support tool {}: {}", action, res.is_ok());
    match res {
        Ok(text) => (true, text),
        Err(text) => (false, text),
    }
}

/// Points the next boot at Safe Mode with Networking (or back to normal) and restarts.
fn set_safe_mode(on: bool) -> Result<String, String> {
    if on {
        // Without this key the ParsiDesk service does not start in safe mode and the
        // supporter loses the peer until someone at the PC turns safe mode off.
        let key = format!(
            "HKLM\\SYSTEM\\CurrentControlSet\\Control\\SafeBoot\\Network\\{}",
            crate::get_app_name()
        );
        run_cmd("reg.exe", &["add", &key, "/ve", "/d", "Service", "/f"])?;
        run_cmd("bcdedit.exe", &["/set", "{current}", "safeboot", "network"])?;
    } else if run_cmd("bcdedit.exe", &["/deletevalue", "{current}", "safeboot"]).is_err() {
        return Err("The remote computer is not set to start in safe mode.".to_owned());
    }
    // A short delay lets the result reach the supporter before the restart.
    Command::new(system32("shutdown.exe"))
        .args(["/r", "/f", "/t", "5"])
        .creation_flags(CREATE_NO_WINDOW)
        .spawn()
        .map_err(|e| e.to_string())?;
    Ok(String::new())
}

fn system32(exe: &str) -> String {
    let root = std::env::var("SystemRoot").unwrap_or_else(|_| "C:\\Windows".to_owned());
    format!("{root}\\System32\\{exe}")
}

fn run_cmd(exe: &str, args: &[&str]) -> Result<String, String> {
    let output = Command::new(system32(exe))
        .args(args)
        .creation_flags(CREATE_NO_WINDOW)
        .output()
        .map_err(|e| e.to_string())?;
    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_owned();
    if output.status.success() {
        Ok(stdout)
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_owned();
        log::error!("{} {:?} failed: {} {}", exe, args, stdout, stderr);
        Err(if stderr.is_empty() { stdout } else { stderr })
    }
}

fn powershell_command(script: &str) -> Command {
    let utf16: Vec<u8> = script
        .encode_utf16()
        .flat_map(|c| c.to_le_bytes())
        .collect();
    let encoded = STANDARD.encode(utf16);
    let mut cmd = Command::new(system32("WindowsPowerShell\\v1.0\\powershell.exe"));
    cmd.args([
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy",
        "Bypass",
        "-EncodedCommand",
        encoded.as_str(),
    ])
    .creation_flags(CREATE_NO_WINDOW);
    cmd
}

fn powershell(script: &str) -> Result<String, String> {
    let output = powershell_command(script)
        .output()
        .map_err(|e| e.to_string())?;
    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_owned();
    if output.status.success() && !stdout.is_empty() {
        Ok(stdout)
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_owned();
        log::error!("powershell failed: {}", stderr);
        Err(stderr)
    }
}

fn spawn_powershell(script: &str) -> Result<String, String> {
    powershell_command(script)
        .spawn()
        .map(|_| String::new())
        .map_err(|e| e.to_string())
}

const RESET_NETWORK_SCRIPT: &str = r#"
Start-Sleep -Seconds 2
Get-NetAdapter -Physical | Where-Object Status -eq 'Up' | Restart-NetAdapter -Confirm:$false
"#;

const SYSTEM_INFO_SCRIPT: &str = r#"
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$net = Get-NetIPConfiguration | Where-Object { $_.IPv4Address -and $_.NetAdapter.Status -eq 'Up' }
[pscustomobject]@{
  computer = $env:COMPUTERNAME
  user = $cs.UserName
  os = $os.Caption
  version = $cv.DisplayVersion
  build = "$($os.BuildNumber).$($cv.UBR)"
  arch = $os.OSArchitecture
  boot = $cs.BootupState
  uptime_minutes = [int]((Get-Date) - $os.LastBootUpTime).TotalMinutes
  cpu = "$($cpu.Name)".Trim()
  cores = $cpu.NumberOfLogicalProcessors
  ram_total = [int64]$os.TotalVisibleMemorySize * 1024
  ram_free = [int64]$os.FreePhysicalMemory * 1024
  disks = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
    [pscustomobject]@{ name = $_.DeviceID; total = [int64]$_.Size; free = [int64]$_.FreeSpace }
  })
  networks = @($net | ForEach-Object {
    [pscustomobject]@{
      name = $_.InterfaceAlias
      ip = @($_.IPv4Address.IPAddress) -join ', '
      gateway = @($_.IPv4DefaultGateway.NextHop) -join ', '
      dns = @($_.DNSServer | Where-Object AddressFamily -eq 2 | ForEach-Object { $_.ServerAddresses }) -join ', '
    }
  })
} | ConvertTo-Json -Compress -Depth 4
"#;
