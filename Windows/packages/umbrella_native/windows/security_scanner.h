#ifndef UMBRELLA_SECURITY_SCANNER_H_
#define UMBRELLA_SECURITY_SCANNER_H_

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <winsock2.h>
#include <windows.h>

#include <cstdint>
#include <string>
#include <vector>

namespace umbrella {

struct InstalledAppEntry {
  std::string name;
  std::string process_name;
  std::string path;
  std::string publisher;
  bool running = false;
  bool is_system = false;
};

struct SecurityThreatEntry {
  std::string key;
  std::string name;
  std::string category;          // malware | conflicting_vpn | adware | suspicious
  std::string severity;          // critical | high | medium
  std::string target;            // process name or full path
  std::string detail;
  std::string remediation_kind;  // process | uninstall | file | registry_run | composite
  std::string path;
  std::string process_name;
  std::string uninstall_cmd;
  std::string registry_root;     // HKCU | HKLM
  std::string registry_path;
  std::string registry_value;
  std::string sha256;
  bool active = false;
  bool signed_valid = false;
  bool blocked_by_policy = true;
};

struct SecurityScanReport {
  bool clean = true;
  int scanned_processes = 0;
  int scanned_apps = 0;
  int scanned_files = 0;
  int64_t scanned_at_ms = 0;
  std::vector<SecurityThreatEntry> threats;
};

struct RemediationOutcome {
  bool ok = false;
  bool action_taken = false;
  bool still_present = false;
  std::string message;
};

class SecurityScanner {
 public:
  static SecurityScanner& Instance();

  /// Lists running user applications, Registry Uninstall entries, and Start Menu shortcuts.
  std::vector<InstalledAppEntry> CollectInstalledApps();

  /// Shows standard Windows executable file picker dialog.
  std::string PickExecutableFile();

  /// Performs real multi-layer security scan across processes, installed programs,
  /// Run/Startup persistence, high-risk directories, PE heuristics, Authenticode, and AMSI.
  SecurityScanReport ScanDeviceSecurity();

  /// Actively terminates, cleans startup entries, deletes malicious files, or invokes uninstallers.
  RemediationOutcome RemediateThreat(const SecurityThreatEntry& target);
};

}  // namespace umbrella

#endif  // UMBRELLA_SECURITY_SCANNER_H_
