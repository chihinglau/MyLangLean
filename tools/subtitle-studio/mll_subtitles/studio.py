# -*- coding: utf-8 -*-
"""
MyLangLean 字幕工坊 - tkinter GUI.

Pipeline: 打开媒体 → 开始识别（后台线程）→ 在表格里修词/时间/译文/分句
→ 校验并导出与 App 同 schema 的逐词字幕 JSON。

Run:
    python mll_subtitles/studio.py           (from the subtitle-studio dir)
    or double-click 启动字幕工坊.bat
"""
from __future__ import annotations

import os
import queue
import sys
import threading
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:  # package-relative when launched as a module, flat when run as a file
    from .schema import Segment, Transcript, Word, validate
    from .transcriber import MODEL_SIZES, transcribe_file
    from .translator import normalize_lang, translate_transcript
except ImportError:  # pragma: no cover - direct script launch
    from schema import Segment, Transcript, Word, validate
    from transcriber import MODEL_SIZES, transcribe_file
    from translator import normalize_lang, translate_transcript

LANGUAGES = ("自动检测", "en", "zh", "ja", "ko", "de", "fr", "es", "ru")
# Keyless translation targets offered in the GUI (zh-CN is the default:
# the app's bilingual view pairs foreign audio with Chinese glosses).
TARGET_LANGS = ("zh-CN", "en", "ja", "ko", "fr", "de", "es", "ru")


class Studio(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("MyLangLean 字幕工坊 — 音视频转逐词字幕")
        self.geometry("1060x760")
        self.minsize(900, 620)

        self.media_path: str | None = None
        self.transcript: Transcript | None = None
        self.current_seg = -1
        self._row_vars: list[dict] = []
        self._events: queue.Queue = queue.Queue()
        self._busy = False
        # Guards against stale word rows being committed back while the
        # segment tree is programmatically rebuilt (Tk fires
        # <<TreeviewSelect>> synchronously inside selection_set).
        self._suspend_commit = False

        self._build_controls()
        self._build_body()
        self._build_log()
        self._set_status("就绪。打开音视频文件后开始识别。")
        self.after(150, self._drain_events)

    # ------------------------------------------------------------ layout

    def _build_controls(self):
        bar = ttk.Frame(self, padding=(10, 8, 10, 4))
        bar.pack(fill=tk.X)

        ttk.Button(bar, text="打开媒体", command=self.pick_media).grid(
            row=0, column=0, padx=(0, 6))
        self.media_var = tk.StringVar(value="未选择文件")
        ttk.Label(bar, textvariable=self.media_var, foreground="#555").grid(
            row=0, column=1, columnspan=6, sticky=tk.W)

        ttk.Label(bar, text="模型").grid(row=1, column=0, sticky=tk.W,
                                         pady=(6, 0))
        self.model_var = tk.StringVar(value="small")
        ttk.Combobox(bar, textvariable=self.model_var, values=MODEL_SIZES,
                     width=9, state="readonly").grid(row=1, column=1,
                                                     sticky=tk.W, padx=4)

        ttk.Label(bar, text="语言").grid(row=1, column=2, sticky=tk.E)
        self.lang_var = tk.StringVar(value="自动检测")
        ttk.Combobox(bar, textvariable=self.lang_var, values=LANGUAGES,
                     width=8, state="readonly").grid(row=1, column=3,
                                                     sticky=tk.W, padx=4)

        self.run_btn = ttk.Button(bar, text="开始识别",
                                  command=self.start_transcribe)
        self.run_btn.grid(row=1, column=4, padx=6)
        ttk.Button(bar, text="打开字幕(JSON)",
                   command=self.pick_transcript).grid(row=1, column=5, padx=4)
        ttk.Button(bar, text="导出字幕",
                   command=self.export).grid(row=1, column=6, padx=4)

        ttk.Label(bar, text="精度").grid(row=2, column=0, sticky=tk.W,
                                         pady=(6, 0))
        self.compute_var = tk.StringVar(value="int8")
        ttk.Combobox(bar, textvariable=self.compute_var,
                     values=("int8", "float32"), width=9,
                     state="readonly").grid(row=2, column=1, sticky=tk.W,
                                            padx=4, pady=(6, 0))

        ttk.Label(bar, text="译成").grid(row=2, column=2, sticky=tk.E,
                                         pady=(6, 0))
        self.target_var = tk.StringVar(value="zh-CN")
        ttk.Combobox(bar, textvariable=self.target_var, values=TARGET_LANGS,
                     width=7, state="readonly").grid(
            row=2, column=3, sticky=tk.W, padx=4, pady=(6, 0))
        self.translate_btn = ttk.Button(
            bar, text="一键翻译", command=self.start_translate)
        self.translate_btn.grid(row=2, column=4, padx=6, pady=(6, 0))
        self.retranslate_btn = ttk.Button(
            bar, text="全部重译",
            command=lambda: self.start_translate(force=True))
        self.retranslate_btn.grid(row=2, column=5, padx=4, pady=(6, 0))

    def _build_body(self):
        paned = ttk.Panedwindow(self, orient=tk.VERTICAL)
        paned.pack(fill=tk.BOTH, expand=True, padx=10, pady=4)

        # Segment list -----------------------------------------------------
        top = ttk.Frame(paned)
        cols = ("idx", "range", "text", "trans")
        self.seg_tree = ttk.Treeview(top, columns=cols, show="headings",
                                     height=8, selectmode="browse")
        self.seg_tree.heading("idx", text="句")
        self.seg_tree.heading("range", text="时间 (秒)")
        self.seg_tree.heading("text", text="原文")
        self.seg_tree.heading("trans", text="译文")
        self.seg_tree.column("idx", width=50, anchor=tk.CENTER)
        self.seg_tree.column("range", width=170, anchor=tk.CENTER)
        self.seg_tree.column("text", width=640)
        self.seg_tree.column("trans", width=44, anchor=tk.CENTER)
        vs = ttk.Scrollbar(top, orient=tk.VERTICAL,
                           command=self.seg_tree.yview)
        self.seg_tree.configure(yscrollcommand=vs.set)
        self.seg_tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        vs.pack(side=tk.RIGHT, fill=tk.Y)
        self.seg_tree.bind("<<TreeviewSelect>>", self._on_select_segment)
        paned.add(top, weight=1)

        # Word editor ------------------------------------------------------
        bottom = ttk.Frame(paned)
        head = ttk.Frame(bottom)
        head.pack(fill=tk.X)
        ttk.Label(head, text="译文").pack(side=tk.LEFT, padx=(2, 4))
        self.translation_var = tk.StringVar()
        ttk.Entry(head, textvariable=self.translation_var).pack(
            side=tk.LEFT, fill=tk.X, expand=True)
        ttk.Button(head, text="保存译文", command=self._save_translation).pack(
            side=tk.LEFT, padx=4)
        ttk.Button(head, text="在末尾加词", command=self._add_word).pack(
            side=tk.LEFT, padx=2)
        ttk.Button(head, text="与下句合并",
                   command=self._merge_next).pack(side=tk.LEFT, padx=2)
        ttk.Button(head, text="删除整句",
                   command=self._delete_segment).pack(side=tk.LEFT, padx=2)

        canvas = tk.Canvas(bottom, highlightthickness=0)
        sb = ttk.Scrollbar(bottom, orient=tk.VERTICAL, command=canvas.yview)
        self.words_frame = ttk.Frame(canvas)
        self.words_frame.bind(
            "<Configure>",
            lambda _: canvas.configure(scrollregion=canvas.bbox("all")))
        canvas.create_window((0, 0), window=self.words_frame, anchor="nw")
        canvas.configure(yscrollcommand=sb.set)
        canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, pady=(4, 0))
        sb.pack(side=tk.RIGHT, fill=tk.Y)
        canvas.bind_all("<MouseWheel>",
                        lambda e: canvas.yview_scroll(
                            int(-e.delta / 120), "units"))
        paned.add(bottom, weight=3)

    def _build_log(self):
        foot = ttk.Frame(self)
        foot.pack(fill=tk.X, padx=10, pady=(0, 8))
        self.status_var = tk.StringVar()
        ttk.Label(foot, textvariable=self.status_var,
                  foreground="#1a6").pack(anchor=tk.W)
        self.log = tk.Text(foot, height=6, state=tk.DISABLED,
                           background="#101418", foreground="#cfe8d8",
                           font=("Consolas", 9))
        self.log.pack(fill=tk.X)

    # ------------------------------------------------------------ helpers

    def _set_status(self, msg):
        self.status_var.set(msg)

    def _logln(self, msg):
        self.log.configure(state=tk.NORMAL)
        self.log.insert(tk.END, msg + "\n")
        self.log.see(tk.END)
        self.log.configure(state=tk.DISABLED)

    def _post(self, kind, payload=None):
        self._events.put((kind, payload))

    def _drain_events(self):
        try:
            while True:
                kind, payload = self._events.get_nowait()
                if kind == "log":
                    self._logln(payload)
                elif kind == "done":
                    self.transcript = payload
                    self._refresh_segments()
                    self._set_busy(False)
                    self._set_status("识别完成，可直接修正后导出。")
                    if self.transcript.segments:
                        self.seg_tree.selection_set(
                            self.seg_tree.get_children()[0])
                elif kind == "error":
                    self._set_busy(False)
                    self._set_status("识别失败")
                    messagebox.showerror("识别失败", str(payload))
                elif kind == "translate_done":
                    done, already, failed = payload
                    self._set_busy(False)
                    sel = self.current_seg
                    self._refresh_segments(
                        select=sel if 0 <= sel < len(
                            self.transcript.segments) else 0)
                    if failed:
                        nums = "、".join(str(i + 1) for i in failed[:10])
                        self._set_status(
                            f"翻译结束：新译 {done} 句，{len(failed)} 句失败"
                            "（成功部分已保留，可再点一键翻译重试）。")
                        messagebox.showwarning(
                            "部分句子翻译失败",
                            f"新译 {done} 句，失败 {len(failed)} 句"
                            f"（第 {nums} 句）。\n\n"
                            "成功的译文已保留，可再次点击「一键翻译」重试，"
                            "或手工在下方译文栏补译。")
                    else:
                        self._set_status(
                            f"翻译完成：本次新译 {done} 句"
                            f"（跳过已有译文 {already} 句）。")
                elif kind == "translate_error":
                    self._set_busy(False)
                    self._set_status("翻译失败")
                    messagebox.showerror("翻译失败", str(payload))
        except queue.Empty:
            pass
        self.after(150, self._drain_events)

    def _set_busy(self, busy):
        self._busy = busy
        state = tk.DISABLED if busy else tk.NORMAL
        self.run_btn.configure(state=state)
        self.translate_btn.configure(state=state)
        self.retranslate_btn.configure(state=state)

    # ------------------------------------------------------------ actions

    def pick_media(self):
        path = filedialog.askopenfilename(
            title="选择音频或视频",
            filetypes=[("音视频", "*.mp3 *.m4a *.wav *.flac *.ogg *.aac "
                        "*.mp4 *.mkv *.mov *.avi *.webm *.m4v"),
                       ("所有文件", "*.*")])
        if path:
            self.media_path = path
            self.media_var.set(path)

    def pick_transcript(self):
        path = filedialog.askopenfilename(
            title="打开字幕 JSON",
            filetypes=[("字幕 JSON", "*.json"), ("所有文件", "*.*")])
        if not path:
            return
        try:
            self.transcript = Transcript.load_json(path)
        except Exception as e:
            messagebox.showerror("打开失败", f"字幕文件无法解析：\n{e}")
            return
        self._refresh_segments()
        self._set_status(f"已载入字幕：{os.path.basename(path)}")

    def start_transcribe(self):
        if not self.media_path:
            messagebox.showinfo("提示", "请先打开音频或视频文件")
            return
        if self._busy:
            return
        lang = self.lang_var.get()
        kwargs = dict(media_path=self.media_path,
                      model_size=self.model_var.get(),
                      language=(None if lang == "自动检测" else lang),
                      compute_type=self.compute_var.get(),
                      log=lambda m: self._post("log", m))
        self._set_busy(True)
        self._set_status("识别中（窗口可拖动，日志见下方）…")

        def work():
            try:
                t = transcribe_file(**kwargs)
                self._post("done", t)
            except Exception as e:  # surface every failure to the UI
                self._post("error", e)

        threading.Thread(target=work, daemon=True).start()

    def start_translate(self, force=False, providers=None, pause=0.4):
        """Translate every segment on a background thread.

        Existing non-empty translations are kept unless *force* is set
        (manual corrections survive re-runs). *providers* / *pause* exist
        for the automated GUI smoke test (injected fake, no real network).
        """
        if self._busy:
            return
        t = self.transcript
        if not t or not t.segments:
            messagebox.showinfo("提示", "请先「开始识别」或「打开字幕(JSON)」，再翻译")
            return
        target = self.target_var.get().strip()
        source = normalize_lang(t.language)
        if source != "auto" and normalize_lang(target) == source:
            messagebox.showerror(
                "无需翻译",
                f"字幕语言（{source}）与目标译文语言相同，请换一个目标语言。")
            return
        pending = sum(1 for s in t.segments
                      if force or not (s.translation or "").strip())
        if pending == 0:
            if not messagebox.askyesno(
                    "重新翻译", "所有句子都已有译文，是否全部重新翻译？\n"
                               "（手工修改的译文也会被覆盖）"):
                return
            force = True
        self._commit_current_segment()
        self._set_busy(True)
        self._set_status(f"翻译中：{source or '自动检测'} → {target}，"
                         f"共 {pending} 句（日志见下方）…")

        def work():
            try:
                stats = translate_transcript(
                    t, target, force=force, providers=providers,
                    log=lambda m: self._post("log", m), pause=pause)
                self._post("translate_done", stats)
            except Exception as e:  # including the same-language guard
                self._post("translate_error", e)

        threading.Thread(target=work, daemon=True).start()

    def export(self):
        self._commit_current_segment()
        t = self.transcript
        if not t or not t.segments:
            messagebox.showinfo("提示", "没有可导出的字幕")
            return
        t.recompute_bounds()
        errors = validate(t)
        if errors:
            messagebox.showerror(
                "校验未通过",
                "请修正以下问题后再导出：\n\n" + "\n".join("· " + e for e in errors))
            return
        initial = os.path.splitext(
            os.path.basename(self.media_path or "transcript"))[0] + ".mll.json"
        initial_dir = (os.path.dirname(self.media_path)
                       if self.media_path else os.getcwd())
        path = filedialog.asksaveasfilename(
            title="导出字幕", initialdir=initial_dir, initialfile=initial,
            defaultextension=".json",
            filetypes=[("字幕 JSON", "*.json")])
        if not path:
            return
        try:
            t.save_json(path)
        except Exception as e:
            messagebox.showerror("导出失败", str(e))
            return
        self._set_status(f"已导出：{path}")
        messagebox.showinfo("完成", f"字幕已导出：\n{path}\n\n"
                                    "把它与媒体一起导入 App 即可逐词跟读。")

    # ------------------------------------------------ segment / word editor

    def _refresh_segments(self, select=-1):
        # selection_set fires <<TreeviewSelect>> synchronously; suspend the
        # commit handler so stale word rows from the old selection cannot
        # overwrite the structural change that triggered this refresh.
        self._suspend_commit = True
        try:
            for row in self.seg_tree.get_children():
                self.seg_tree.delete(row)
            for i, seg in enumerate(self.transcript.segments):
                self.seg_tree.insert(
                    "", tk.END, iid=str(i),
                    values=(i + 1, f"{seg.start:7.2f} – {seg.end:7.2f}",
                            seg.text, "✓" if (seg.translation or "").strip()
                            else ""))
            if select >= 0 and str(select) in self.seg_tree.get_children():
                self.seg_tree.selection_set(str(select))
        finally:
            self._suspend_commit = False
        if select >= 0 and 0 <= select < len(self.transcript.segments):
            self._load_segment(select)
        else:
            self.current_seg = -1

    def _on_select_segment(self, _evt):
        if self._suspend_commit:
            return
        sel = self.seg_tree.selection()
        if not sel:
            return
        idx = int(sel[0])
        # A tree rebuild re-announces the already-loaded row asynchronously;
        # ignore it so the editor isn't re-committed and the operation's
        # status message (e.g. 翻译完成) isn't clobbered by live validation.
        if idx == self.current_seg:
            return
        self._commit_current_segment()
        self._load_segment(idx)
        self._live_validate()

    def _live_validate(self):
        """FR-3: surface the first timing problem in the status bar as soon
        as an edit lands, instead of waiting for the export dialog."""
        if not self.transcript:
            return
        self.transcript.recompute_bounds()
        errors = validate(self.transcript)
        if errors:
            self._set_status("实时校验：" + errors[0])
        else:
            self._set_status(
                f"实时校验通过（{len(self.transcript.segments)} 句）。")

    def _load_segment(self, idx):
        self.current_seg = idx
        for child in self.words_frame.winfo_children():
            child.destroy()
        self._row_vars = []
        seg = self.transcript.segments[idx]
        self.translation_var.set(seg.translation or "")
        headers = ttk.Frame(self.words_frame)
        headers.grid(row=0, column=0, sticky=tk.EW, padx=2)
        for col, text, width in [
                (0, "#", 3), (1, "词", 20),
                (2, "开始", 8), (3, "", 2), (4, "", 2),
                (5, "结束", 8), (6, "", 2), (7, "", 2),
                (8, "拆", 3), (9, "删", 3)]:
            ttk.Label(headers, text=text, width=width).grid(row=0, column=col)

        for i, word in enumerate(seg.words):
            self._make_word_row(i + 1, word)

    def _make_word_row(self, n, word):
        r = len(self._row_vars) + 1
        wv = tk.StringVar(value=word.w)
        sv = tk.StringVar(value=f"{word.s:.3f}")
        ev = tk.StringVar(value=f"{word.e:.3f}")
        f = self.words_frame

        ttk.Label(f, text=str(n), width=3).grid(row=r, column=0)
        ttk.Entry(f, textvariable=wv, width=20).grid(row=r, column=1,
                                                     sticky=tk.W, padx=2)
        ttk.Entry(f, textvariable=sv, width=8).grid(row=r, column=2, padx=2)
        ttk.Button(f, text="-", width=2,
                   command=lambda v=sv: self._nudge(v, -0.05)).grid(
            row=r, column=3, padx=1)
        ttk.Button(f, text="+", width=2,
                   command=lambda v=sv: self._nudge(v, 0.05)).grid(
            row=r, column=4, padx=1)
        ttk.Entry(f, textvariable=ev, width=8).grid(row=r, column=5, padx=2)
        ttk.Button(f, text="-", width=2,
                   command=lambda v=ev: self._nudge(v, -0.05)).grid(
            row=r, column=6, padx=1)
        ttk.Button(f, text="+", width=2,
                   command=lambda v=ev: self._nudge(v, 0.05)).grid(
            row=r, column=7, padx=1)
        ttk.Button(f, text="拆", width=3,
                   command=lambda i=(r - 1): self._split_at(i)).grid(
            row=r, column=8, padx=1)
        ttk.Button(f, text="✕", width=3,
                   command=lambda i=(r - 1): self._delete_word(i)).grid(
            row=r, column=9, padx=1)
        self._row_vars.append({"w": wv, "s": sv, "e": ev})

    @staticmethod
    def _nudge(var, delta):
        try:
            var.set(f"{float(var.get()) + delta:.3f}")
        except ValueError:
            pass

    def _commit_current_segment(self):
        """Write the editor rows back into the segment model.

        A non-numeric time cell must never silently delete the word: the
        previous timing for that row position is kept and the problem is
        surfaced in the status bar. The model's probability ``p`` is carried
        over for rows whose text is unchanged."""
        if self.current_seg < 0 or not self.transcript:
            return 0
        if self.current_seg >= len(self.transcript.segments):
            self.current_seg = -1
            return 0
        seg = self.transcript.segments[self.current_seg]
        old = seg.words
        words = []
        bad = 0
        for i, row in enumerate(self._row_vars):
            text = row["w"].get().strip()
            if not text:
                continue  # empty text = intentionally removed word
            prev = old[i] if i < len(old) else None
            try:
                s = float(row["s"].get())
                e = float(row["e"].get())
            except ValueError:
                bad += 1
                if prev is not None:
                    s, e = prev.s, prev.e
                else:
                    continue
            prob = prev.p if (prev is not None and prev.w == text) else None
            words.append(Word(text, s, e, prob))
        seg.words = words
        seg.translation = self.translation_var.get().strip() or None
        seg.recompute_text(self.transcript.language)
        if bad:
            self._set_status(f"有 {bad} 个词的时间不是数字，已保留其原时间；"
                             "请修正后再导出。")
        return bad

    def _save_translation(self):
        if 0 <= self.current_seg < len(self.transcript.segments):
            value = self.translation_var.get().strip() or None
            self.transcript.segments[self.current_seg].translation = value
            self._set_status("译文已保存")

    def _add_word(self):
        if self.current_seg < 0:
            return
        self._commit_current_segment()
        seg = self.transcript.segments[self.current_seg]
        start = round((seg.words[-1].e if seg.words else seg.start) + 0.01, 3)
        seg.words.append(Word("新词", start, round(start + 0.2, 3)))
        seg.recompute_text(self.transcript.language)
        self.transcript.recompute_bounds()
        self._refresh_segments(select=self.current_seg)
        self._live_validate()

    def _delete_word(self, i):
        self._commit_current_segment()
        seg = self.transcript.segments[self.current_seg]
        if 0 <= i < len(seg.words):
            seg.words.pop(i)
        seg.recompute_text(self.transcript.language)
        self.transcript.recompute_bounds()
        self._refresh_segments(select=self.current_seg)
        self._live_validate()

    def _split_at(self, i):
        self._commit_current_segment()
        si = self.current_seg
        seg = self.transcript.segments[si]
        if i <= 0 or i >= len(seg.words):
            return
        moved = seg.words[i:]
        seg.words = seg.words[:i]
        seg.recompute_text(self.transcript.language)
        new = Segment(id=si + 1, start=moved[0].s, end=moved[-1].e,
                      words=moved)
        new.recompute_text(self.transcript.language)
        self.transcript.segments.insert(si + 1, new)
        self.transcript.recompute_bounds()
        self._refresh_segments(select=si)
        self._live_validate()

    def _merge_next(self):
        self._commit_current_segment()
        si = self.current_seg
        segs = self.transcript.segments
        if si < 0 or si + 1 >= len(segs):
            return
        first, second = segs[si], segs[si + 1]
        first.words.extend(second.words)
        # Keep the second sentence's translation instead of dropping it.
        if second.translation:
            first.translation = " / ".join(
                t for t in (first.translation, second.translation) if t)
        segs.pop(si + 1)
        first.recompute_text(self.transcript.language)
        self.transcript.recompute_bounds()
        self._refresh_segments(select=si)
        self._live_validate()

    def _delete_segment(self):
        if self.current_seg < 0:
            return
        if not messagebox.askyesno("确认", "删除当前整句？"):
            return
        self.transcript.segments.pop(self.current_seg)
        self.current_seg = -1
        self.transcript.recompute_bounds()
        self._refresh_segments(select=0)
        self._live_validate()


def main():
    Studio().mainloop()


if __name__ == "__main__":
    main()
