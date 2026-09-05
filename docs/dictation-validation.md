# Dictation validation protocol

Status: **Not executed.** Record the app commit, packaged app version, macOS version, Mac model, memory, microphone, and model file or cloud model before running this protocol.

Use the packaged Release app from the CI artifact or release workflow. Start each acceptance check with known text and rich content on the clipboard, then confirm whether Open Dictation restores both after a successful paste.

## Manual acceptance

Run each applicable check on one notched MacBook display and one non-notched display or Mac.

| Check | Procedure | Pass condition |
| --- | --- | --- |
| Toggle and audio tail | In toggle mode, start dictation, speak through the second shortcut press, and finish with a short final word. Repeat ten times. | One session starts per first press. Each second press stops it, captures the final word, and inserts one transcript. |
| Hold and release | Hold the shortcut, speak through release, and finish with a short final word. Repeat ten times, including one very short press. | Recording lasts only while held. Release captures the final word and causes at most one transcription. A too-short recording fails cleanly. |
| Cancel | Cancel with Escape while recording and again while transcription is pending. | No text is inserted, temporary audio is removed, and the next session works. |
| Permissions | Test first launch, denied Microphone access, and denied Accessibility access. | The app requests Microphone access when recording is attempted. Denial gives an actionable error. Without Accessibility access, the transcript is copied and the app does not claim it was pasted. |
| Selected microphone | Select a non-default microphone, record, unplug it while idle, and try again. Reconnect and retry. | The saved stable device selection is used. A missing device produces the selected-microphone error and does not fall back silently. Reconnection restores operation. |
| Disconnect while recording | Unplug the selected wired or USB microphone during a recording. | The session stops with an error, inserts no partial transcript, releases recording state, and permits a new session after recovery. |
| Bluetooth | Record ten phrases on a Bluetooth microphone. Disconnect and reconnect it between two runs and once during recording. | Normal runs retain the chosen input and phrase endings. Disconnect behavior matches the wired-device checks, without a stuck recording. |
| Notch and display changes | Run start, processing, success, copied, error, and cancel paths on notched and non-notched setups. Connect or disconnect an external display during an active session. | The notch UI appears only where supported. Audio feedback and dictation still work without it. A display interruption cancels safely and the following session works. |
| Clipboard and target apps | Paste into one native field, one browser field, and one Electron app. Repeat without Accessibility access and once while changing the clipboard immediately after paste. | Each granted run inserts text once. The original clipboard returns after paste unless the user changed it. The denied run leaves the transcript on the clipboard. |
| Model readiness | Select each Parakeet model before download, cancel one download, complete it, relaunch offline, and switch among all local engines. | Selection before download gives a clear error. Only the explicit prepare action downloads. Cancellation leaves no false ready state. Installed models load offline and engine changes do not transcribe with the previous model. |
| Dictionary and cleanup | Dictate saved terms, literal replacement sources, filler words, punctuation, and words containing filler-like fragments with each engine. | Whisper and compatible cloud requests receive bounded hints. All engines apply standalone literal replacements. Filler removal stays off by default; when enabled, it removes listed fillers without damaging surrounding words or punctuation. |

## Repeatable benchmark

Benchmark these three local configurations separately: the default Whisper model, Parakeet TDT v2, and Parakeet TDT v3. Use the same Mac, power mode, input WAV files, language setting, and app build throughout. Close unrelated high-load processes and report the exact model artifacts.

Prepare a fixed corpus of at least 30 clips that includes short commands, 30 to 60 second prose, phrase-final words after brief pauses, names and technical terms, punctuation, quiet speech, and representative background noise. Keep a verbatim reference transcript for every clip.

For each engine:

1. Obtain at least 20 fresh-process runs by fully quitting and relaunching the app with the selected model already downloaded. Measure launch-to-model-ready time separately from the first stop-to-transcript time, since startup prewarming can finish before recording ends. Do not delete downloaded weights. Report whether the operating system's file cache was warm or reset by a reboot.
2. Keep the model loaded and run the full corpus at least three times. Report p50 and p95 for model preparation, first dictation, and warm stop-to-transcript latency separately. Keep audio duration separate so results can be reproduced.
3. Report word error rate for each corpus category and exact-match accuracy for the chosen names and technical terms. Preserve raw transcripts with the measurements.
4. Cancel ten runs during transcription. Report cancellation latency, any text insertion, and whether the next session succeeds.
5. Record app resident memory before model load, after prewarm, at peak transcription, after cancellation, and after switching away from the engine. Repeat the warm corpus and report retained-memory growth.

Do not publish latency, quality, cancellation, or memory comparisons until this protocol has been run against the packaged app and the raw results are available.
