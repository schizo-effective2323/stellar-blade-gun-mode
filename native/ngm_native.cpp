// NikkeGunMode native part: does, outside a NIKKE stage, the switches the NIKKE stage entry turns on that a Lua mod
// cannot reach (Ghidra: FUN_141c2ede0 in the shared SB project, Steam build 26123051 - the build StellarCoop pins).
//
//   ngm_on  : remember the old values, then
//             - game-state singleton (FUN_141adc360): +0x43 = 1, +0x4c = 3
//             - global switch DAT_147032aa8 = 1
//             - EVE's equipped bullet -> Bullet_Nikke through the game's own setter FUN_141a8cab0
//               (EVE = FUN_141aace90(*(FUN_141a97c40() + 200), *(FUN_141a978c0() + 0x58)), as the stage entry finds her)
//   ngm_off : put the remembered values back
//   ngm_probe: write the current values to NikkeGunMode_native.log
//
// Every export has lua_CFunction's shape and ignores the Lua state (the DLL links no Lua), as StellarCoop's do: Lua
// calls f(0,0,0,0,0,0,0,0) and the number it returns is how many of those arguments come back, so
// select('#', f(...)) is the result code. 1 = done, 2 = not the pinned build, 3 = fault (caught), 4 = EVE not found.
// Each call runs on the game thread (the Lua side calls it inside ExecuteInGameThread) under an SEH guard.
#include <windows.h>
#include <cstdint>
#include <cstdio>
#include <cwchar>

namespace {

constexpr uint64_t kImageBase = 0x140000000ull;
// The pinned executable (same pin as StellarCoop's native/src/pose/engine.h): PE TimeDateStamp and SizeOfImage.
constexpr uint32_t kTimeDateStamp = 0x6ad8eff1, kSizeOfImage = 0x15fa3000;

constexpr uint64_t kSingletonFn = 0x141adc360;  // longlong FUN_141adc360(void)
constexpr uint64_t kSwitch      = 0x147032aa8;  // byte DAT_147032aa8
constexpr uint64_t kClientFn    = 0x141a978c0;  // longlong FUN_141a978c0(void); +0x58 = local player's actor id
constexpr uint64_t kWorldFn     = 0x141a97c40;  // longlong FUN_141a97c40(void); +200 = actor map
constexpr uint64_t kFindActorFn = 0x141aace90;  // longlong FUN_141aace90(longlong map, uint32 id)
constexpr uint64_t kFNameFn     = 0x142938950;  // uint64* FUN_142938950(uint64* out, const wchar_t* text, int add)
constexpr uint64_t kSetBulletFn = 0x141a8cab0;  // void FUN_141a8cab0(longlong actor, uint64 fname)
constexpr size_t kBulletOffset = 0x28bc;        // actor: equipped bullet FName
constexpr size_t kFlagA = 0x43, kModeB = 0x4c;  // singleton fields the stage sets to 1 and 3

using VoidRet = int64_t(__fastcall *)();
using FindActor = int64_t(__fastcall *)(int64_t, uint32_t);
using MakeFName = uint64_t *(__fastcall *)(uint64_t *, const wchar_t *, int);
using SetBullet = void(__fastcall *)(int64_t, uint64_t);

uintptr_t base = 0;
bool pinned_checked = false, pinned = false;

struct Saved {
  bool valid = false;
  uint8_t flagA = 0, sw = 0;
  int32_t modeB = 0;
  uint64_t bullet = 0;
} saved;

template <class T> T at(uintptr_t a) { return *reinterpret_cast<volatile T *>(a); }
template <class T> void put(uintptr_t a, T v) { *reinterpret_cast<volatile T *>(a) = v; }
uintptr_t rva(uint64_t va) { return base + (va - kImageBase); }

bool check_pin() {
  if (pinned_checked) return pinned;
  pinned_checked = true;
  base = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
  if (!base || at<uint16_t>(base) != 0x5a4d) return pinned = false;
  uintptr_t nt = base + at<uint32_t>(base + 0x3c);
  if (at<uint32_t>(nt) != 0x00004550) return pinned = false;
  return pinned = at<uint32_t>(nt + 8) == kTimeDateStamp && at<uint32_t>(nt + 24 + 56) == kSizeOfImage;
}

void log_line(const char *text) {
  wchar_t path[MAX_PATH];
  HMODULE self = nullptr;
  GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                     reinterpret_cast<LPCWSTR>(&log_line), &self);
  DWORD n = GetModuleFileNameW(self, path, MAX_PATH);
  if (!n || n >= MAX_PATH) return;
  wchar_t *slash = wcsrchr(path, L'\\');
  if (!slash) return;
  wcscpy_s(slash + 1, MAX_PATH - (slash + 1 - path), L"NikkeGunMode_native.log");
  FILE *f = nullptr;
  if (_wfopen_s(&f, path, L"a") != 0 || !f) return;
  SYSTEMTIME t;
  GetLocalTime(&t);
  fprintf(f, "%02d:%02d:%02d.%03d %s\n", t.wHour, t.wMinute, t.wSecond, t.wMilliseconds, text);
  fclose(f);
}

// v0.8: NO calls into game code. The shipping exe is wrapped by a protector (sections .debug$P/.edata/.xtls/.code,
// code only decrypted at run time) and v0.6/v0.7 killed the process with no crash report the moment they called
// FUN_141adc360 - the protector's silent kill. So everything here is plain data reads/writes:
//   singleton = DAT_147032598 (what FUN_141adc360 returns once created), switch = DAT_147032aa8; both in .sbss.
// The bullet swap is left to the Lua side (ServerRequest_ChangeBulletItem).
constexpr uint64_t kSingletonPtr = 0x147032598;

int64_t singleton() { return at<int64_t>(rva(kSingletonPtr)); }

int on_inner(char *msg, size_t cap) {
  log_line("step: read singleton global");
  int64_t single = singleton();
  if (!saved.valid) {
    saved.sw = at<uint8_t>(rva(kSwitch));
    if (single) {
      saved.flagA = at<uint8_t>(static_cast<uintptr_t>(single) + kFlagA);
      saved.modeB = at<int32_t>(static_cast<uintptr_t>(single) + kModeB);
    }
    saved.valid = true;
  }
  log_line("step: write switches");
  if (single) {
    put<uint8_t>(static_cast<uintptr_t>(single) + kFlagA, 1);
    put<int32_t>(static_cast<uintptr_t>(single) + kModeB, 3);
  }
  put<uint8_t>(rva(kSwitch), 1);
  snprintf(msg, cap, "on: singleton %p (was +43=%u +4c=%d) switch was %u -> now +43=1 +4c=3 switch=1",
           reinterpret_cast<void *>(single), saved.flagA, saved.modeB, saved.sw);
  return 1;
}

int off_inner(char *msg, size_t cap) {
  if (!saved.valid) { snprintf(msg, cap, "off: nothing saved"); return 1; }
  int64_t single = singleton();
  if (single) {
    put<uint8_t>(static_cast<uintptr_t>(single) + kFlagA, saved.flagA);
    put<int32_t>(static_cast<uintptr_t>(single) + kModeB, saved.modeB);
  }
  put<uint8_t>(rva(kSwitch), saved.sw);
  snprintf(msg, cap, "off: restored +43=%u +4c=%d switch=%u", saved.flagA, saved.modeB, saved.sw);
  saved.valid = false;
  return 1;
}

int probe_inner(char *msg, size_t cap) {
  int64_t single = singleton();
  snprintf(msg, cap, "probe: singleton %p +43=%u +4c=%d switch=%u", reinterpret_cast<void *>(single),
           single ? at<uint8_t>(static_cast<uintptr_t>(single) + kFlagA) : 0,
           single ? at<int32_t>(static_cast<uintptr_t>(single) + kModeB) : 0, at<uint8_t>(rva(kSwitch)));
  return 1;
}


// v0.8b: ngm_vtable - read the controller address the Lua side wrote to NikkeGunMode_addr.txt and log the
// controller's vtable entries (as Ghidra addresses) around the ServerRequest_* _Validate/_Implementation slots
// (exec thunks: UseSkill +0x1580/+0x1588, ActorStancePressCommandKey +0x14d0/+0x14d8). Data reads only.
int vtable_inner(char *msg, size_t cap) {
  wchar_t path[MAX_PATH];
  HMODULE self = nullptr;
  GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                     reinterpret_cast<LPCWSTR>(&vtable_inner), &self);
  DWORD n = GetModuleFileNameW(self, path, MAX_PATH);
  wchar_t *slash = n ? wcsrchr(path, L'\\') : nullptr;
  if (!slash) { snprintf(msg, cap, "vtable: no module path"); return 3; }
  wcscpy_s(slash + 1, MAX_PATH - (slash + 1 - path), L"NikkeGunMode_addr.txt");
  FILE *f = nullptr;
  if (_wfopen_s(&f, path, L"r") != 0 || !f) { snprintf(msg, cap, "vtable: no addr file"); return 3; }
  unsigned long long obj = 0;
  int got = fscanf_s(f, "%llx", &obj);
  fclose(f);
  if (got != 1 || !obj) { snprintf(msg, cap, "vtable: bad addr file"); return 3; }
  uintptr_t vt = at<uintptr_t>(static_cast<uintptr_t>(obj));
  uintptr_t end = base + kSizeOfImage;
  char line[160];
  snprintf(line, sizeof line, "vtable: object %llx vtable %llx (ghidra %llx)", obj, (unsigned long long)vt,
           (unsigned long long)(vt - base + kImageBase));
  log_line(line);
  if (vt < base || vt >= end) { snprintf(msg, cap, "vtable: not inside the exe"); return 3; }
  const size_t offs[] = {0x14c8, 0x14d0, 0x14d8, 0x14e0, 0x1578, 0x1580, 0x1588, 0x1590};
  for (size_t o : offs) {
    uintptr_t e = at<uintptr_t>(vt + o);
    snprintf(line, sizeof line, "  +%04zx -> %llx  ghidra %llx%s", o, (unsigned long long)e,
             (unsigned long long)(e - base + kImageBase), (e >= base && e < end) ? "" : "  (outside exe)");
    log_line(line);
  }
  snprintf(msg, cap, "vtable: dumped");
  return 1;
}

int guarded(int (*fn)(char *, size_t)) {
  char msg[512] = {0};
  if (!check_pin()) { log_line("not the pinned build 26123051 - nothing done"); return 2; }
  log_line("call start");
  int r = 3;
  __try {
    r = fn(msg, sizeof msg);
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    snprintf(msg, sizeof msg, "fault %08lx - caught, nothing more done", GetExceptionCode());
    r = 3;
  }
  log_line(msg);
  return r;
}

} // namespace

extern "C" __declspec(dllexport) int ngm_on(void *) noexcept { return guarded(on_inner); }
extern "C" __declspec(dllexport) int ngm_off(void *) noexcept { return guarded(off_inner); }
extern "C" __declspec(dllexport) int ngm_probe(void *) noexcept { return guarded(probe_inner); }
extern "C" __declspec(dllexport) int ngm_vtable(void *) noexcept { return guarded(vtable_inner); }

BOOL WINAPI DllMain(HINSTANCE, DWORD, LPVOID) { return TRUE; }
