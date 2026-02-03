#!/usr/bin/env python3
"""
Repo-wide AI Debugger for Jenkins
Deterministically locates errors (file + line) before invoking AI.
"""

import os
import sys
import argparse
import datetime
from pathlib import Path
import requests
import re

# ---------------- CONFIG ---------------- #

SUPPORTED_EXTENSIONS = {
    '.py', '.sh', '.bash', '.js', '.ts', '.java', '.go', '.yaml', '.yml',
    '.json', '.groovy', '.tf', '.sql', '.md', '.txt', 'Jenkinsfile'
}

SKIP_DIRS = {
    '.git', 'node_modules', 'venv', '.venv', '__pycache__',
    'dist', 'build', 'target', '.idea', '.vscode', 'helm'
}

MAX_FILE_SIZE = 1024 * 1024  # 1 MB

# ---------------- INGESTER ---------------- #

class CodebaseIngester:
    def __init__(self, repo_path):
        self.repo_path = Path(repo_path).resolve()
        self.index = []

    def ingest(self, exclude_files=None):
        if exclude_files is None:
            exclude_files = set()
        
        for root, dirs, files in os.walk(self.repo_path):
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
            for file in files:
                path = Path(root) / file
                
                # Exclude the report output file and other non-source files
                if file in exclude_files or file == "report.txt" or file.endswith(".log"):
                    continue
                    
                if path.suffix.lower() not in SUPPORTED_EXTENSIONS and file != "Jenkinsfile":
                    continue
                if path.stat().st_size > MAX_FILE_SIZE:
                    continue

                try:
                    content = path.read_text(errors="ignore")
                except Exception:
                    continue

                self.index.append({
                    "file": str(path.relative_to(self.repo_path)),
                    "lines": content.splitlines()
                })

        print(f"✓ Indexed {len(self.index)} files")

# ---------------- LOG PARSER ---------------- #

def extract_runtime_error(log_text):
    """
    Extracts concrete runtime errors from Jenkins logs
    """
    patterns = [
        r'line \d+: (\w+): command not found',
        r'(\w+): command not found',
        r'NameError: name \'(\w+)\' is not defined',
        r'File ".*?", line \d+, in .*?\n\s+(.*)', # Captures the failing line content
        r'ImportError: No module named (\w+)',
        r'ModuleNotFoundError: No module named \'(\w+)\'',
        r'No such file or directory.*?(\w+\.\w+)',
        r'SyntaxError:.*?(\w+)',
        r'AttributeError:.*?object has no attribute \'(\w+)\'',
        r'Exception: (.+)',
        r'curl: \(22\) The requested URL returned error: (\d+)',
        r'HTTP/1.1 (\d+) ',
        r'Status: (\d+)',
        r'Error: UPGRADE FAILED: .*? (no matches for kind "(\w+)")',
        r'Error: UPGRADE FAILED: .*? (resource mapping not found for name: "([\w-]+)")',
        r'error: (\w+) is not a valid resource type',
        r'(\w+): Permission denied',
    ]

    for pattern in patterns:
        match = re.search(pattern, log_text, re.MULTILINE)
        if match:
            return match.group(1)

    return None

# ---------------- REPO SEARCH ---------------- #

def locate_token_in_repo(token, repo_index):
    findings = []

    for file_entry in repo_index:
        for idx, line in enumerate(file_entry["lines"], start=1):
            if token in line:
                findings.append({
                    "file": file_entry["file"],
                    "line": idx,
                    "code": line.strip()
                })

    return findings

# ---------------- AI ANALYZER ---------------- #

class OllamaAnalyzer:
    def __init__(self, model, url):
        self.url = url.rstrip("/")
        self.model = model

    def analyze(self, error_token, findings, log_content):
        if not findings:
            return "AI analysis failed: No codebase findings provided."

        # Prioritize source files (non-txt, non-md) for the main error location
        primary_finding = findings[0]
        for f in findings:
            if not f['file'].endswith(('.txt', '.md')):
                primary_finding = f
                break

        context = "\n".join(
            f"{f['file']}:{f['line']} -> {f['code']}"
            for f in findings
        )

        prompt = f"""You are a senior DevOps debugging expert.

Runtime error token: {error_token}

Exact source locations:
{context}

Jenkins logs:
{log_content}

Respond in this EXACT format:

## Build Status: FAILURE ❌

## Error Location
*File:* {primary_finding['file']}
*Line Number:* {primary_finding['line']}
*Error String:* {error_token}

## Issue Analysis
[Explain WHY this specific line caused the failure]

## Proposed Solution
```diff
- {primary_finding['code']}
+ [corrected line]
```

## Additional Context
[Any other relevant information]
"""

        try:
            r = requests.post(
                f"{self.url}/api/generate",
                json={
                    "model": self.model,
                    "prompt": prompt,
                    "stream": False,
                    "options": {"temperature": 0.2, "num_predict": 1024}
                },
                timeout=300
            )
            return r.json().get("response", "AI analysis failed")
        except Exception as e:
            return f"AI analysis failed: {e}"

# ---------------- REPORT ---------------- #

def write_report(text, output):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(output, "w") as f:
        f.write(f"# AI Debugger Report ({ts})\n\n{text}\n\n---\n*Report Generated:* {ts}\n*Analyzer:* Ollama AI Root Cause Analysis Agent\n")
    print(f"✅ Report saved to {output}")

# ---------------- MAIN ---------------- #

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-path", required=True)
    parser.add_argument("--log-path", required=True)
    parser.add_argument("--output-path", default="report.txt")
    parser.add_argument("--model", default="qwen2.5-coder:7b")
    parser.add_argument("--ollama-url", default="http://localhost:11434")
    parser.add_argument("--status", choices=['success', 'failure'], default='failure')
    args = parser.parse_args()

    print("=" * 80)
    print(f"🚀 AI Debugger Agent for Jenkins (Mode: {args.status.upper()})")
    print("=" * 80)

    # Success mode
    if args.status == 'success':
        report = """## Build Status: SUCCESS ✅

All pipeline stages completed successfully. No issues detected.

*Conclusion:* No action required. System is healthy."""
        write_report(report, args.output_path)
        print("✅ Analysis complete")
        return

    # Failure mode
    print("\n📂 Step 1: Ingesting codebase...")
    ingester = CodebaseIngester(args.repo_path)
    ingester.ingest(exclude_files={Path(args.output_path).name})

    print("\n📋 Step 2: Parsing Jenkins logs...")
    try:
        log_content = Path(args.log_path).read_text(errors="ignore")
    except Exception as e:
        print(f"❌ Error reading log file: {e}")
        return
    print(f"✓ Log file loaded: {len(log_content)} characters")

    print("\n🔍 Step 3: Extracting error token...")
    token = extract_runtime_error(log_content)
    if not token:
        report = "## Build Status: FAILURE ❌\n\nNo detectable runtime error pattern found in logs.\nPlease review Jenkins console manually."
        write_report(report, args.output_path)
        print("⚠️  No error token found")
        return

    print(f"✓ Found error token: '{token}'")

    print("\n🎯 Step 4: Locating in codebase...")
    findings = locate_token_in_repo(token, ingester.index)

    automated_block = "\n=== AUTOMATED ERROR LOCATION FINDINGS ===\n"
    if findings:
        for f in findings:
            automated_block += (
                f"*FOUND ERROR*: '{token}' in file '{f['file']}' at line {f['line']}\n"
                f"  Line {f['line']}: {f['code']}\n"
            )
    else:
        automated_block += "No matching tokens found in the codebase.\n"
    automated_block += "=" * 80 + "\n\n"

    print(automated_block)

    if not findings:
        report = f"## Build Status: FAILURE ❌\n\nError token '{token}' found in logs but not in codebase.\nThis may be a runtime-only error."
        write_report(automated_block + report, args.output_path)
        print("⚠️  Token not found in codebase")
        return

    print(f"\n🧠 Step 5: Analyzing with Ollama ({args.model})...")
    analyzer = OllamaAnalyzer(args.model, args.ollama_url)
    ai_result = analyzer.analyze(token, findings, log_content)

    write_report(automated_block + ai_result, args.output_path)

    print("\n" + "=" * 80)
    print("✅ Analysis complete!")
    print("=" * 80)

if __name__ == "__main__":
    main()
