# Standalone Crashlytics Engine Architecture

This document provides a comprehensive architectural overview of the standalone crash-handling engine that was stripped from the Firebase Crashlytics SDK. It details how crashes are caught, how stack unwinding works, what data is collected securely during a crash, and how reports are processed and unified on the next application launch.

---

## 1. High-Level Overview

The standalone Crashlytics engine operates in two distinct phases:

*   **Phase 1: Crash Time (Execution)**
    Occurs when the app experiences a fatal event. The engine intercepts the crash, suspends all threads, unwinds the stack of the crashed thread (and all other threads), gathers device state and binary image information, and writes this data to disk. **Crucially, all operations in Phase 1 must be async-signal-safe.**
*   **Phase 2: Next Launch (Processing)**
    Occurs the next time the application starts. The engine detects reports left from previous sessions, parses the raw data, attempts on-device symbolication, and prepares a final unified report payload.

---

## 2. Initialization Flow

The engine has been decoupled from `FirebaseCore` and `FIRApp`. Initialization is now handled via a straightforward standalone method:

```objc
[FIRCrashlytics startWithGoogleAppID:@"YOUR_APP_ID"];
```

### What happens during initialization:
1.  **File System Setup:** `FIRCLSFileManager` ensures the required directory structure exists (`active`, `processing`, `prepared`).
2.  **Context Setup:** `FIRCLSContextManager` initializes the central `FIRCLSContext` (a mapped memory region holding crucial app and device state).
3.  **Phase 2 Trigger:** `FIRCLSReportManager` calls `checkAndUpdateUnsentReports` via `FIRCLSExistingReportManager` to process any crashes from a previous session.
4.  **Crash Handlers Installation:** The SDK registers its three tiers of exception handlers (Mach, POSIX, NSException/C++).
5.  **Current Session Report Creation:** A new `.clsrecords` file is created in the `active` directory for the *current* execution.

---

## 3. Crash Capture Mechanisms (The 3 Tiers)

The engine employs a robust, three-tiered approach to ensure no crash goes unnoticed, regardless of where it originates.

### A. Mach Exceptions (`FIRCLSMachException.c`)
*   **What it catches:** Hardware-level faults (e.g., `EXC_BAD_ACCESS` for memory issues, `EXC_BAD_INSTRUCTION`, `EXC_GUARD`).
*   **How it works:** Mach exceptions are the lowest level of error reporting in macOS/iOS. The SDK creates a dedicated, high-priority background thread running a Mach message server (`mach_msg_server`). It uses `task_set_exception_ports` to route exception messages from the kernel to this dedicated thread.
*   **Advantage:** Because the exception is handled on a completely separate thread, the crashed thread is naturally suspended by the kernel, making stack unwinding incredibly reliable.

### B. POSIX Signals (`FIRCLSSignal.c`)
*   **What it catches:** OS-level signals (e.g., `SIGABRT` for aborts, `SIGSEGV` for segmentation faults, `SIGILL`, `SIGBUS`, `SIGFPE`).
*   **How it works:** Uses `sigaction` with the `SA_SIGINFO` flag to register a custom signal handler. When a signal occurs, the kernel interrupts the thread to execute the handler.
*   **Advantage:** Catches errors that may not trigger a Mach exception or catchable software exception, such as `abort()` calls or force-quits (if catchable).

### C. Language Exceptions (`FIRCLSException.mm`)
*   **What it catches:** Unhandled Objective-C exceptions (`NSException`) and unhandled C++ exceptions (`std::terminate`).
*   **How it works:**
    *   **Obj-C:** Registers an `NSUncaughtExceptionHandler`.
    *   **C++:** Replaces `std::set_terminate` with a custom handler.
*   **Advantage:** Allows the SDK to capture the actual exception object, reason, and name, providing much more context than just an instruction pointer fault.

> **Note on Handler Interception:** When a software exception occurs, it is recorded, and the SDK then typically allows the process to abort naturally, which then triggers the POSIX/Mach handlers. Crashlytics prevents double-recording by maintaining an atomic flag (`FIRCLSContext.crash.crashed`).

---

## 4. The Stack Unwinding Process (`FIRCLSUnwind.c`)

When a crash is intercepted, the engine must "unwind" the call stack to determine the sequence of function calls that led to the crash.

1.  **Thread Suspension:** If the crash was caught via a Signal or Exception, the handler immediately suspends all other threads in the process to freeze the application state.
2.  **Register State:** The engine retrieves the CPU registers (Instruction Pointer `pc`, Link Register `lr`, Frame Pointer `fp`, Stack Pointer `sp`) from the thread context (`ucontext_t` or Mach thread state).
3.  **Walking the Stack:**
    *   **Compact Unwind:** The engine first attempts to read the Compact Unwind Info (a highly optimized table stored in the Mach-O binary) to determine how to restore the registers for the previous frame.
    *   **DWARF Unwind:** If Compact Unwind fails or isn't present, it falls back to parsing DWARF `.eh_frame` data.
    *   **Frame Pointer Heuristic:** As a last resort (or for older architectures), it walks the stack using the Frame Pointer (`fp`) chain.
4.  **Recording:** For each frame, it records the memory address (Program Counter / `pc`).

---

## 5. Async-Signal-Safe Data Collection (Phase 1)

**The Golden Rule of Crash Handlers:** Once an app has crashed, memory is in an undefined state. You cannot allocate memory (`malloc`), you cannot use Objective-C/Swift objects, and you cannot use standard locks (`dispatch_sync`, `@synchronized`), as doing so will cause deadlocks.

To safely record data during a crash, the SDK relies on:
*   **Pre-allocated Memory:** `FIRCLSContext` pre-allocates memory for the crash state during initialization.
*   **`FIRCLSSDKFileLog`:** A custom logging macro that uses raw C string formatting and writes directly to a file descriptor using the `write()` syscall.
*   **Append-Only `.clsrecords`:** The engine writes data to disk in a proprietary append-only format (`.clsrecords`).

### What is collected:
*   **Crash Metadata:** Timestamp, crashing thread ID, exception type/code/reason.
*   **Thread States:** The unwound stack frames (addresses) and register values for *all* threads.
*   **Binary Images:** A list of all dynamically loaded libraries (Mach-O images) in the process, their load addresses, sizes, and **UUIDs**. (Crucial for later symbolication).
*   **Device/App Info:** OS version, device model, free RAM/disk, app version, orientation.
*   **Custom Data:** Any custom keys, logs, or user IDs previously recorded by the developer (stored safely in memory-mapped files during normal execution).

---

## 6. Phase 2: Next Launch Unification & Processing

Because a crashed process cannot safely format a complex JSON payload or make network requests, that work is deferred to the next time the app launches.

### Step A: Discovery (`FIRCLSExistingReportManager`)
1.  On startup, the manager scans the `reports/active/` directory.
2.  It identifies directories belonging to previous sessions.
3.  It groups the raw `.clsrecords` files written during the crash.

### Step B: Processing & On-Device Symbolication (`FIRCLSReportUploader` & `FIRCLSProcessReportOperation`)
1.  The raw report directory is moved from `active/` to **`processing/`**.
2.  `FIRCLSProcessReportOperation` is executed on a background queue.
3.  **Parsing:** It parses the raw, fragmented `.clsrecords` files.
4.  **Symbolication (`FIRCLSSymbolResolver`):** It attempts basic on-device symbolication. It compares the raw memory addresses of the stack frames against the loaded Binary Images to calculate the exact offset within the binary.
5.  **Formatting:** It consolidates the thread data, exception data, and binary images into a structured internal object (`FIRCLSInternalReport`).

### Step C: Prepared State
1.  Once the processing operation is complete, the report directory is moved from `processing/` to **`prepared/`**.
2.  *In the original Firebase SDK, this is the exact moment `GoogleDataTransport` was invoked to upload the payload.*
3.  **In our Standalone Engine:** The report halts here. The processed files rest safely in the `reports/prepared/` directory, ready to be read, extracted, or transmitted by your custom host application logic.

---

## Summary of Directory Flow
1.  `active/` ➔ Raw append-only data written synchronously as the process dies.
2.  `processing/` ➔ Moved here on next launch. Data is parsed and structured.
3.  `prepared/` ➔ Final output destination. Contains the consolidated, ready-to-consume crash report.