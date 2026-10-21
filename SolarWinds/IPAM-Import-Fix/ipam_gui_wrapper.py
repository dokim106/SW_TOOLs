#!/usr/bin/env python3
"""IPAM Import Fix — GUI wrapper. Double-click to open, pick a folder, done."""
import os
import sys
import threading
import tkinter as tk
from tkinter import filedialog

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ipam_import_fix

import queue
log_queue = queue.Queue()


def run_folder_scan(folder):
    exts = (".csv", ".xlsx", ".xlsm")
    files = []
    for root, dirs, fnames in os.walk(folder):
        for f in fnames:
            if f.lower().endswith(exts):
                files.append(os.path.join(root, f))

    if not files:
        log_queue.put(f"No CSV/XLSX files found in {folder}\n")
        return

    log_queue.put(f"Found {len(files)} file(s):\n")
    for fp in files:
        log_queue.put(f"  - {os.path.basename(fp)} ({os.path.getsize(fp):,} bytes)\n")

    log_queue.put("\n" + "=" * 60 + "\nProcessing...\n" + "=" * 60 + "\n")

    for fp in files:
        log_queue.put(f"\n--- {os.path.basename(fp)} ---\n")
        try:
            rc = ipam_import_fix.main([fp, "--quiet"])
            if rc == 0:
                log_queue.put("  [OK] Done\n")
            elif rc == 2:
                log_queue.put("  [WARN] Some rows rejected\n")
            elif rc == 3:
                log_queue.put("  [ERR] Errors occurred\n")
            else:
                log_queue.put(f"  Exit code {rc}\n")
        except Exception as e:
            log_queue.put(f"  [ERR] {e}\n")

    log_queue.put("\n" + "=" * 60 + "\nAll done.\n")


def on_browse():
    folder = filedialog.askdirectory(title="Select folder containing CSV/XLSX files")
    if not folder:
        return
    log.insert(tk.END, f"\nSelected: {folder}\n")
    log.see(tk.END)
    threading.Thread(target=run_folder_scan, args=(folder,), daemon=True).start()


def poll_log():
    try:
        while True:
            msg = log_queue.get_nowait()
            log.insert(tk.END, msg)
            log.see(tk.END)
    except queue.Empty:
        pass
    root.after(100, poll_log)


def main():
    global root, log
    root = tk.Tk()
    root.title("IPAM Import Fix - SolarWinds CSV/XLSX Processor")
    root.geometry("700x500")

    frame = tk.Frame(root, padx=10, pady=5)
    frame.pack(fill=tk.X)

    tk.Button(frame, text="Browse Folder...", command=on_browse, width=25).pack(side=tk.LEFT)
    tk.Label(frame, text="(pick the folder with your CSV/XLSX files)").pack(side=tk.LEFT, padx=10)

    global log
    log = tk.Text(root, state="normal", wrap="word", font=("Courier", 10))
    log.pack(fill=tk.BOTH, expand=True, padx=10, pady=5)

    poll_log()
    root.mainloop()


if __name__ == "__main__":
    main()
