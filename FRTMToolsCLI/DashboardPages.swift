import Foundation

enum DashboardPages {
    static func index(runs: [DashboardRun]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let items = runs.map { run in
            let created = formatter.string(from: run.createdAt)
            let platformTag = run.platform == .ipa ? "IPA" : "APK/AAB"
            let status = statusLabel(for: run.status)
            let error = (run.status == .failed ? run.errorMessage : nil).map { "<div class=\"run-error\">\(escapeHTML($0))</div>" } ?? ""

            return """
            <div class="run" data-run-id="\(run.id.uuidString)" data-run-title="\(escapeHTML(run.originalFileName).lowercased())">
              <label class="run-select" title="Select for compare">
                <input type="checkbox" class="run-checkbox" value="\(run.id.uuidString)" />
              </label>
              <div class="run-main">
                <div class="run-title">\(escapeHTML(run.originalFileName))</div>
                <div class="run-meta">
                  <span class="tag">\(platformTag)</span>
                  <span class="dot">•</span>
                  <span class="mono">\(created)</span>
                </div>
                \(error)
              </div>
              <div class="run-status">\(status)</div>
              <div class="run-actions">
                <a class="btn btn-ghost" href="/runs/\(run.id.uuidString)" title="Open report">Open</a>
                <button class="btn btn-ghost btn-danger" data-delete="\(run.id.uuidString)" title="Delete run">Delete</button>
              </div>
            </div>
            """
        }.joined(separator: "\n")

        let list = runs.isEmpty
        ? """
          <div class="empty">
            <div class="empty-title">No runs yet</div>
            <div class="empty-subtitle">Upload an IPA/APK/AAB to generate a report. Runs are saved locally for later.</div>
          </div>
          """
        : "<div id=\"runs\" class=\"run-list\">\(items)</div>"

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <title>FRTMTools Dashboard</title>
          <style>
          \(DashboardHTMLStyle.baseCSS)
          body { margin: 0; background: var(--color-bg); color: var(--color-text); font-family: var(--font-sans); }
          .shell { max-width: 980px; margin: 48px auto; padding: 0 18px; }
          .topbar { display: flex; align-items: center; justify-content: space-between; gap: 14px; margin-bottom: 18px; }
          .brand { display: grid; gap: 6px; }
          .brand h1 { margin: 0; font-size: 18px; letter-spacing: -0.02em; }
          .brand p { margin: 0; color: var(--color-muted); font-size: 13px; line-height: 1.4; }

          .card { border-radius: 18px; background: var(--color-surface); border: 1px solid var(--color-border); box-shadow: var(--shadow-faint); overflow: hidden; }
          .card + .card { margin-top: 14px; }
          .card-header { padding: 14px 16px; border-bottom: 1px solid var(--color-border); display: flex; align-items: center; justify-content: space-between; gap: 12px; }
          .card-title { font-weight: 800; font-size: 13px; letter-spacing: 0.08em; text-transform: uppercase; color: var(--color-muted); }
          .card-body { padding: 16px; }

          .row { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
          .spacer { flex: 1; }

          .btn { display: inline-flex; align-items: center; justify-content: center; padding: 10px 12px; border-radius: 12px; border: 1px solid var(--color-border); background: var(--color-surface); color: var(--color-text); text-decoration: none; font-weight: 700; cursor: pointer; }
          .btn:hover { border-color: var(--color-border-strong); }
          .btn:disabled { opacity: 0.5; cursor: not-allowed; }
          .btn-primary { border-color: rgba(37, 99, 235, 0.45); background: rgba(37, 99, 235, 0.14); }
          .btn-ghost { background: transparent; }
          .btn-danger { border-color: rgba(220, 38, 38, 0.45); color: var(--color-negative); }

          .input { padding: 10px 12px; border-radius: 12px; border: 1px solid var(--color-border); background: var(--color-elevated); color: var(--color-text); }
          .input:focus { outline: none; border-color: var(--color-border-strong); }
          .mono { font-family: var(--font-mono); }

          .drop { border-radius: 16px; border: 1px dashed var(--color-border-strong); background: var(--color-elevated); padding: 14px; display: flex; align-items: center; justify-content: space-between; gap: 12px; }
          .drop strong { display: block; font-size: 14px; }
          .drop span { display: block; color: var(--color-muted); font-size: 13px; margin-top: 4px; }
          .drop.is-dragover { border-color: rgba(37,99,235,0.7); box-shadow: 0 0 0 3px rgba(37,99,235,0.12) inset; }

          .notice { display:none; padding: 12px 12px; border-radius: 12px; background: var(--color-elevated); border: 1px solid var(--color-border); color: var(--color-muted); margin-top: 12px; }
          .notice.bad { border-color: rgba(220,38,38,0.4); background: rgba(220,38,38,0.10); color: var(--color-text); }

          .run-list { display: grid; gap: 10px; }
          .run { display: grid; grid-template-columns: 26px 1fr auto auto; gap: 12px; align-items: start; padding: 12px; border-radius: 14px; border: 1px solid var(--color-border); background: var(--color-surface); }
          .run:hover { border-color: var(--color-border-strong); }
          .run-select { padding-top: 3px; }
          .run-checkbox { width: 16px; height: 16px; }
          .run-title { font-weight: 800; letter-spacing: -0.01em; }
          .run-meta { margin-top: 6px; color: var(--color-muted); font-size: 12px; display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
          .tag { display: inline-flex; align-items: center; padding: 4px 8px; border-radius: 999px; font-weight: 800; font-size: 11px; border: 1px solid var(--color-border); background: var(--color-elevated); color: var(--color-text); }
          .dot { color: var(--color-subtle); }
          .run-error { margin-top: 10px; padding: 10px 12px; border-radius: 12px; border: 1px solid rgba(220,38,38,0.35); background: rgba(220,38,38,0.08); color: var(--color-text); font-size: 12px; line-height: 1.4; }
          .run-status { padding-top: 2px; }
          .run-actions { display: flex; gap: 8px; padding-top: 0; }

          .pill { display: inline-flex; align-items: center; padding: 6px 10px; border-radius: 999px; font-weight: 800; font-size: 11px; border: 1px solid var(--color-border); background: var(--color-elevated); }
          .pill.ok { border-color: rgba(16,185,129,0.4); background: rgba(16,185,129,0.12); }
          .pill.bad { border-color: rgba(220,38,38,0.4); background: rgba(220,38,38,0.12); }
          .pill.warn { border-color: rgba(249,115,22,0.4); background: rgba(249,115,22,0.12); }

          .empty { border-radius: 16px; border: 1px dashed var(--color-border-strong); background: var(--color-elevated); padding: 18px; }
          .empty-title { font-weight: 900; }
          .empty-subtitle { margin-top: 6px; color: var(--color-muted); font-size: 13px; line-height: 1.5; }

          @media (max-width: 720px) {
            .run { grid-template-columns: 26px 1fr; }
            .run-status, .run-actions { grid-column: 2 / 3; }
            .run-actions { padding-top: 10px; }
          }
          </style>
        </head>
        <body>
          <div class="shell">
            <div class="topbar">
              <div class="brand">
                <h1>FRTMTools • Dashboard</h1>
                <p>Minimal, local analysis for IPA/APK/AAB with persistent history.</p>
              </div>
              <div class="row">
                <button id="compare" class="btn btn-ghost" disabled>Compare</button>
                <a class="btn btn-ghost" href="/" title="Refresh">Refresh</a>
              </div>
            </div>

            <div class="card">
              <div class="card-header">
                <div class="card-title">Upload</div>
                <div class="row">
                  <input id="search" class="input" placeholder="Search runs…" />
                </div>
              </div>
              <div class="card-body">
                <div id="drop" class="drop">
                  <div>
                    <strong>Drop a package here</strong>
                    <span>Accepts <span class="mono">.ipa</span>, <span class="mono">.apk</span>, <span class="mono">.aab</span></span>
                  </div>
                  <div class="row">
                    <input id="file" type="file" accept=".ipa,.apk,.aab,.abb" />
                    <button id="upload" class="btn btn-primary">Analyze</button>
                  </div>
                </div>
                <div id="notice" class="notice"></div>
              </div>
            </div>

            <div class="card">
              <div class="card-header">
                <div class="card-title">History</div>
                <div class="row">
                  <span class="mono" style="color: var(--color-muted); font-size: 12px;">\(runs.count) runs</span>
                </div>
              </div>
              <div class="card-body">
                \(list)
              </div>
            </div>
          </div>
          <script>
          const fileInput = document.getElementById('file');
          const uploadButton = document.getElementById('upload');
          const notice = document.getElementById('notice');
          const drop = document.getElementById('drop');
          const search = document.getElementById('search');
          const compare = document.getElementById('compare');

          function show(msg) {
            notice.style.display = 'block';
            notice.classList.remove('bad');
            notice.textContent = msg;
          }

          function showError(msg) {
            notice.style.display = 'block';
            notice.classList.add('bad');
            notice.textContent = msg;
          }

          async function createRun(file) {
            const url = '/api/runs?filename=' + encodeURIComponent(file.name);
            const response = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/octet-stream' }, body: file });
            if (!response.ok) {
              const text = await response.text();
              throw new Error(text || ('HTTP ' + response.status));
            }
            return await response.json();
          }

          function selectedRunIds() {
            return Array.from(document.querySelectorAll('.run-checkbox:checked')).map(x => x.value);
          }

          function updateCompareButton() {
            const ids = selectedRunIds();
            compare.disabled = ids.length !== 2;
            compare.textContent = ids.length === 2 ? 'Compare selected' : 'Compare';
          }

          uploadButton.addEventListener('click', async () => {
            const file = fileInput.files[0];
            if (!file) {
              showError('Pick an IPA/APK/AAB file first.');
              return;
            }
            uploadButton.disabled = true;
            try {
              show('Uploading…');
              const result = await createRun(file);
              window.location.href = '/runs/' + result.id;
            } catch (e) {
              showError('Upload failed: ' + (e && e.message ? e.message : String(e)));
              uploadButton.disabled = false;
            }
          });

          document.querySelectorAll('[data-delete]').forEach((button) => {
            button.addEventListener('click', async () => {
              const id = button.getAttribute('data-delete');
              if (!id || !confirm('Delete this run?')) return;
              button.disabled = true;
              try {
                const response = await fetch('/api/runs/' + id + '/delete', { method: 'POST' });
                if (!response.ok) throw new Error('HTTP ' + response.status);
                window.location.reload();
              } catch (e) {
                showError('Delete failed: ' + (e && e.message ? e.message : String(e)));
                button.disabled = false;
              }
            });
          });

          document.querySelectorAll('.run-checkbox').forEach((checkbox) => {
            checkbox.addEventListener('change', updateCompareButton);
          });
          updateCompareButton();

          compare.addEventListener('click', () => {
            const ids = selectedRunIds();
            if (ids.length !== 2) return;
            window.location.href = '/compare?before=' + encodeURIComponent(ids[0]) + '&after=' + encodeURIComponent(ids[1]);
          });

          if (search) {
            search.addEventListener('input', () => {
              const term = (search.value || '').trim().toLowerCase();
              document.querySelectorAll('[data-run-id]').forEach((row) => {
                const title = row.getAttribute('data-run-title') || '';
                row.style.display = term === '' || title.includes(term) ? '' : 'none';
              });
            });
          }

          if (drop) {
            ['dragenter','dragover'].forEach(ev => {
              drop.addEventListener(ev, (e) => {
                e.preventDefault();
                e.stopPropagation();
                drop.classList.add('is-dragover');
              });
            });
            ['dragleave','drop'].forEach(ev => {
              drop.addEventListener(ev, (e) => {
                e.preventDefault();
                e.stopPropagation();
                drop.classList.remove('is-dragover');
              });
            });
            drop.addEventListener('drop', (e) => {
              const dt = e.dataTransfer;
              if (!dt || !dt.files || !dt.files.length) return;
              fileInput.files = dt.files;
              uploadButton.click();
            });
          }
          </script>
        </body>
        </html>
        """
    }

    static func runStatus(run: DashboardRun) -> String {
        let title = escapeHTML(run.originalFileName)
        let statusLabel = statusText(for: run.status)
        let errorBlock: String
        if let error = run.errorMessage, run.status == .failed {
            errorBlock = "<div class=\"error\">\(escapeHTML(error))</div>"
        } else {
            errorBlock = ""
        }

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <title>Analyzing • \(title)</title>
          <style>
          \(DashboardHTMLStyle.baseCSS)
          body { margin: 0; background: var(--color-bg); font-family: var(--font-sans); color: var(--color-text); }
          .shell { max-width: 820px; margin: 60px auto; padding: 0 20px; }
          .card { border-radius: 18px; background: var(--color-surface); box-shadow: var(--shadow-card); padding: 24px; border: 1px solid var(--color-border); }
          .title { margin: 0; font-size: 18px; letter-spacing: -0.02em; }
          .meta { margin-top: 10px; color: var(--color-muted); font-family: var(--font-mono); font-size: 12px; }
          .status { margin-top: 16px; display: flex; align-items: center; gap: 10px; padding: 12px 12px; border-radius: 14px; background: var(--color-elevated); border: 1px solid var(--color-border); font-weight: 800; }
          .spinner { width: 14px; height: 14px; border-radius: 999px; border: 2px solid rgba(148,163,184,0.55); border-top-color: var(--color-primary); animation: spin 0.8s linear infinite; }
          @keyframes spin { to { transform: rotate(360deg); } }
          .links { margin-top: 16px; display: flex; gap: 10px; flex-wrap: wrap; }
          .btn { display: inline-flex; align-items: center; justify-content: center; padding: 10px 12px; border-radius: 12px; border: 1px solid var(--color-border); background: var(--color-surface); color: var(--color-text); text-decoration: none; font-weight: 700; }
          .btn:hover { border-color: var(--color-border-strong); }
          .error { margin-top: 18px; padding: 14px 16px; border-radius: var(--radius-md); background: rgba(220,38,38,0.12); border: 1px solid rgba(220,38,38,0.4); color: var(--color-text); }
          </style>
        </head>
        <body>
          <div class="shell">
            <div class="card">
              <h1 class="title">\(title)</h1>
              <div class="meta">Run id: <span id="runId">\(run.id.uuidString)</span></div>
              <div class="status"><span class="spinner"></span><span id="status">\(statusLabel)</span><span style="margin-left:auto; color: var(--color-muted); font-weight: 700; font-size: 12px;">Auto-refreshing</span></div>
              \(errorBlock)
              <div class="links">
                <a class="btn" href="/">Back to history</a>
                <a class="btn" href="/runs/\(run.id.uuidString)">Reload</a>
              </div>
            </div>
          </div>
          <script>
          const runId = document.getElementById('runId').textContent;
          const status = document.getElementById('status');

          async function poll() {
            try {
              const response = await fetch('/api/runs/' + runId);
              if (!response.ok) throw new Error('HTTP ' + response.status);
              const run = await response.json();
              status.textContent = run.status;
              if (run.status === 'complete') {
                window.location.href = '/runs/' + run.id;
                return;
              }
              if (run.status === 'failed') {
                return;
              }
              setTimeout(poll, 900);
            } catch (e) {
              setTimeout(poll, 1500);
            }
          }
          poll();
          </script>
        </body>
        </html>
        """
    }

    static func errorPage(title: String, message: String) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <title>\(escapeHTML(title))</title>
          <style>
          \(DashboardHTMLStyle.baseCSS)
          body { margin: 0; background: var(--color-bg); font-family: var(--font-sans); color: var(--color-text); }
          .shell { max-width: 820px; margin: 60px auto; padding: 0 20px; }
          .card { border-radius: 18px; background: var(--color-surface); box-shadow: var(--shadow-card); padding: 24px; border: 1px solid var(--color-border); }
          .title { margin: 0; font-size: 18px; letter-spacing: -0.02em; }
          .msg { margin-top: 14px; color: var(--color-muted); line-height: 1.6; }
          .btn { margin-top: 18px; display: inline-flex; align-items: center; justify-content: center; gap: 8px; padding: 10px 12px; border-radius: 12px; border: 1px solid var(--color-border); background: var(--color-surface); color: var(--color-text); text-decoration: none; font-weight: 700; }
          .btn:hover { border-color: var(--color-border-strong); }
          </style>
        </head>
        <body>
          <div class="shell">
            <div class="card">
              <h1 class="title">\(escapeHTML(title))</h1>
              <div class="msg">\(escapeHTML(message))</div>
              <a class="btn" href="/">Back</a>
            </div>
          </div>
        </body>
        </html>
        """
    }

    private static func statusText(for status: DashboardRunStatus) -> String {
        switch status {
        case .queued: return "Queued"
        case .running: return "Running"
        case .complete: return "Complete"
        case .failed: return "Failed"
        }
    }

    private static func statusLabel(for status: DashboardRunStatus) -> String {
        let cls: String
        let text: String
        switch status {
        case .queued:
            cls = "warn"
            text = "Queued"
        case .running:
            cls = "warn"
            text = "Running"
        case .complete:
            cls = "ok"
            text = "Complete"
        case .failed:
            cls = "bad"
            text = "Failed"
        }
        return "<span class=\"pill \(cls)\">\(text)</span>"
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
